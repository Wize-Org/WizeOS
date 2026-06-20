#!/usr/bin/env bash
set -euo pipefail

DEVICE="${DEVICE:-mustang}"
SOURCE_KEYS_DIR="${SOURCE_KEYS_DIR:-keys}"
DEST_KEYS_DIR="${DEST_KEYS_DIR:-wizeos-keys-decrypted}"
BACKUP_ROOT="${BACKUP_ROOT:-wizeos-key-backups}"
BUILDER_USER="${BUILDER_USER:-builder}"
EMPTY_SIGNING_PASS_FILE="${EMPTY_SIGNING_PASS_FILE:-/home/${BUILDER_USER}/wizeos-secrets/signing-empty.pass}"

log() {
  echo "==> $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Run as root."
  fi
}

secure_file() {
  local path="$1"
  [ -e "$path" ] || return 0
  chown root:root "$path" 2>/dev/null || true
  chmod 0600 "$path" 2>/dev/null || true
}

secure_tree() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  chown -R root:root "$dir"
  find "$dir" -type d -exec chmod 0700 {} \;
  find "$dir" -type f -exec chmod 0600 {} \;
}

make_temp_pass_file() {
  local prompt="$1"
  local pass_file
  pass_file="$(mktemp)"

  read -rsp "$prompt" pass
  printf '\n' >&2

  printf '%s' "$pass" > "$pass_file"
  unset pass
  chmod 0600 "$pass_file"

  if [ ! -s "$pass_file" ]; then
    rm -f "$pass_file"
    die "Passphrase was empty. Refusing to continue."
  fi

  printf '%s\n' "$pass_file"
}

shred_or_rm() {
  local path="$1"
  [ -e "$path" ] || return 0
  shred -u "$path" 2>/dev/null || rm -f "$path"
}

is_pk8_unencrypted() {
  local key="$1"
  openssl pkcs8 -inform DER -nocrypt -in "$key" -out /dev/null >/dev/null 2>&1
}

decrypt_pk8_keys() {
  local device_dir="${DEST_KEYS_DIR}/${DEVICE}"
  local pk8_keys=()
  local encrypted_pk8_keys=()
  local key

  mapfile -t pk8_keys < <(find "$device_dir" -maxdepth 1 -type f -name '*.pk8' | sort)

  if [ "${#pk8_keys[@]}" -eq 0 ]; then
    log "No .pk8 keys found under ${device_dir}"
    return 0
  fi

  for key in "${pk8_keys[@]}"; do
    if is_pk8_unencrypted "$key"; then
      echo "    Already decrypted: $key"
    else
      encrypted_pk8_keys+=("$key")
    fi
  done

  if [ "${#encrypted_pk8_keys[@]}" -eq 0 ]; then
    log "All .pk8 keys are already decrypted"
    return 0
  fi

  log "Decrypting Android .pk8 signing keys"
  local pass_file
  pass_file="$(make_temp_pass_file "Enter Android .pk8 signing passphrase: ")"

  for key in "${encrypted_pk8_keys[@]}"; do
    echo "    Decrypting $key"

    local tmp_pem tmp_pk8
    tmp_pem="$(mktemp)"
    tmp_pk8="$(mktemp)"

    openssl pkcs8 \
      -inform DER \
      -in "$key" \
      -passin "file:${pass_file}" \
      -out "$tmp_pem"

    openssl pkcs8 \
      -topk8 \
      -inform PEM \
      -outform DER \
      -in "$tmp_pem" \
      -out "$tmp_pk8" \
      -nocrypt

    install -m 0600 -o root -g root "$tmp_pk8" "$key"

    rm -f "$tmp_pem" "$tmp_pk8"
  done

  shred_or_rm "$pass_file"

  log "Verifying decrypted .pk8 keys"
  for key in "${pk8_keys[@]}"; do
    echo "    Checking $key"
    openssl pkcs8 -inform DER -nocrypt -in "$key" -out /dev/null
  done
}

is_pem_unencrypted() {
  local key="$1"
  openssl pkey -in "$key" -noout >/dev/null 2>&1
}

decrypt_pem_key_if_needed() {
  local key="$1"
  local label="$2"

  if [ ! -f "$key" ]; then
    echo "    Missing, skipping: $key"
    return 0
  fi

  if is_pem_unencrypted "$key"; then
    echo "    Already decrypted: $key"
    return 0
  fi

  log "Decrypting ${label}: ${key}"
  local pass_file tmp_out
  pass_file="$(make_temp_pass_file "Enter passphrase for ${label}: ")"
  tmp_out="$(mktemp)"

  openssl pkey \
    -in "$key" \
    -passin "file:${pass_file}" \
    -out "$tmp_out"

  openssl pkey -in "$tmp_out" -noout

  install -m 0600 -o root -g root "$tmp_out" "$key"

  rm -f "$tmp_out"
  shred_or_rm "$pass_file"
}

decrypt_ssh_key_if_needed() {
  local key="$1"

  if [ ! -f "$key" ]; then
    return 0
  fi

  if ssh-keygen -y -P "" -f "$key" >/dev/null 2>&1; then
    echo "    SSH key already has no passphrase: $key"
    chmod 0600 "$key"
    return 0
  fi

  log "Removing SSH key passphrase: $key"
  echo "    ssh-keygen will ask for the current SSH key passphrase."
  ssh-keygen -p -f "$key" -N ""
  chmod 0600 "$key"
}

prepare_destination() {
  [ -d "$SOURCE_KEYS_DIR" ] || die "SOURCE_KEYS_DIR does not exist: ${SOURCE_KEYS_DIR}"

  if [ "$(readlink -f "$SOURCE_KEYS_DIR")" = "$(readlink -f "$DEST_KEYS_DIR" 2>/dev/null || true)" ]; then
    die "SOURCE_KEYS_DIR and DEST_KEYS_DIR must be different. Refusing to decrypt in-place."
  fi

  mkdir -p "$BACKUP_ROOT"
  chmod 0700 "$BACKUP_ROOT"

  if [ -d "$DEST_KEYS_DIR" ]; then
    local backup
    backup="${BACKUP_ROOT}/decrypted-keys-before-refresh-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing decrypted keys folder to ${backup}"
    mkdir -p "$backup"
    rsync -a "${DEST_KEYS_DIR%/}/" "$backup/"
    chmod -R go-rwx "$backup"
    rm -rf "$DEST_KEYS_DIR"
  fi

  log "Copying encrypted source keys"
  echo "    From: $SOURCE_KEYS_DIR"
  echo "    To  : $DEST_KEYS_DIR"
  mkdir -p "$DEST_KEYS_DIR"
  rsync -a "${SOURCE_KEYS_DIR%/}/" "${DEST_KEYS_DIR%/}/"

  secure_tree "$DEST_KEYS_DIR"
}

prepare_ota_avbroot_key_if_missing() {
  local device_dir="${DEST_KEYS_DIR}/${DEVICE}"
  local ota_key="${device_dir}/ota-avbroot.key"
  local release_pk8="${device_dir}/releasekey.pk8"

  if [ -f "$ota_key" ]; then
    return 0
  fi

  if [ ! -f "$release_pk8" ]; then
    echo "    Missing releasekey.pk8, cannot create ${ota_key}"
    return 0
  fi

  log "Creating unencrypted ota-avbroot.key from decrypted releasekey.pk8"
  openssl pkcs8 \
    -inform DER \
    -nocrypt \
    -in "$release_pk8" \
    -out "$ota_key"

  secure_file "$ota_key"
}

prepare_ssh_keys() {
  local device_dir="${DEST_KEYS_DIR}/${DEVICE}"
  local top_private="${DEST_KEYS_DIR}/id_ed25519"
  local top_public="${DEST_KEYS_DIR}/id_ed25519.pub"
  local device_private="${device_dir}/id_ed25519"
  local device_public="${device_dir}/id_ed25519.pub"

  if [ -f "$device_private" ] && [ ! -f "$top_private" ]; then
    log "Copying device SSH signing key to top-level keys/id_ed25519"
    cp -a "$device_private" "$top_private"
  fi

  if [ -f "$device_public" ] && [ ! -f "$top_public" ]; then
    cp -a "$device_public" "$top_public"
  fi

  decrypt_ssh_key_if_needed "$device_private"
  decrypt_ssh_key_if_needed "$top_private"

  secure_file "$device_private"
  secure_file "$device_public"
  secure_file "$top_private"
  secure_file "$top_public"
}

create_empty_signing_pass_file() {
  log "Creating blank signing passphrase file for unattended generate-release.sh"
  install -d -m 0700 "/home/${BUILDER_USER}/wizeos-secrets"

  : > "$EMPTY_SIGNING_PASS_FILE"
  for _ in $(seq 1 200); do
    printf '\n' >> "$EMPTY_SIGNING_PASS_FILE"
  done

  if id -u "$BUILDER_USER" >/dev/null 2>&1; then
    chown "${BUILDER_USER}:${BUILDER_USER}" "$EMPTY_SIGNING_PASS_FILE"
  fi
  chmod 0600 "$EMPTY_SIGNING_PASS_FILE"

  echo "    Empty pass file: $EMPTY_SIGNING_PASS_FILE"
}

main() {
  require_root

  log "WizeOS key decryptor"
  echo "    Device: ${DEVICE}"
  echo "    Source keys: ${SOURCE_KEYS_DIR}"
  echo "    Decrypted keys: ${DEST_KEYS_DIR}"

  prepare_destination

  decrypt_pk8_keys

  decrypt_pem_key_if_needed "${DEST_KEYS_DIR}/${DEVICE}/avb.pem" "avb.pem"

  prepare_ota_avbroot_key_if_missing
  decrypt_pem_key_if_needed "${DEST_KEYS_DIR}/${DEVICE}/ota-avbroot.key" "ota-avbroot.key"

  prepare_ssh_keys
  create_empty_signing_pass_file

  secure_tree "$DEST_KEYS_DIR"

  log "Done"
  echo "Decrypted keys are here:"
  echo "    ${DEST_KEYS_DIR}"
  echo
  echo "Use this in unattended builds:"
  echo "    KEYS_SOURCE=${DEST_KEYS_DIR}"
  echo "    SIGNING_KEY_PASSPHRASE_FILE=${EMPTY_SIGNING_PASS_FILE}"
}

main "$@"
