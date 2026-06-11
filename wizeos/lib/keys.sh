#!/usr/bin/env bash
create_blank_signing_pass_file() {
  [ -n "${SIGNING_KEY_PASSPHRASE_FILE:-}" ] || return 0
  [ ! -f "${SIGNING_KEY_PASSPHRASE_FILE}" ] || return 0
  log "Creating blank signing passphrase file"
  install -d -m 0700 "/home/${BUILD_USER}/wizeos-secrets"
  : >"${SIGNING_KEY_PASSPHRASE_FILE}"
  for _ in $(seq 1 200); do printf '\n' >>"${SIGNING_KEY_PASSPHRASE_FILE}"; done
  chown "${BUILD_USER}:${BUILD_USER}" "${SIGNING_KEY_PASSPHRASE_FILE}" 2>/dev/null || true
  chmod 0600 "${SIGNING_KEY_PASSPHRASE_FILE}"
}
copy_keys_into_workdir() {
  log "Preparing keys folder"
  mkdir -p "${WORKDIR}"
  [ "${SIGNED:-0}" = "1" ] || return 0
  if [ -n "${KEYS_SOURCE:-}" ] && [ -d "${KEYS_SOURCE}" ]; then mkdir -p "${WORKDIR}/keys"; rsync -a "${KEYS_SOURCE%/}/" "${WORKDIR}/keys/"
  elif [ -d "${WORKDIR}/keys/${DEVICE}" ] || [ -d "${WORKDIR}/keys" ]; then echo "    Using existing keys in ${WORKDIR}/keys"
  elif [ -n "${KEYS_BACKUP:-}" ] && [ -d "${KEYS_BACKUP}" ]; then mkdir -p "${WORKDIR}/keys"; rsync -a "${KEYS_BACKUP%/}/" "${WORKDIR}/keys/"
  elif [ -d "/root/keys/${DEVICE}" ] || [ -d "/root/keys" ]; then mkdir -p "${WORKDIR}/keys"; rsync -a "/root/keys/" "${WORKDIR}/keys/"
  else warn "No keys folder auto-detected yet."
  fi
  chown -R "${BUILD_USER}:${BUILD_USER}" "${WORKDIR}" "/home/${BUILD_USER}"
}
valid_ssh_private_key() { [ -f "$1" ] && ssh-keygen -y -f "$1" >/dev/null 2>&1; }
copy_release_ssh_key_to_all_locations() {
  local keys_dir="${WORKDIR}/keys"
  local device_dir="${keys_dir}/${DEVICE}"
  local top_private="${keys_dir}/id_ed25519"
  local top_public="${keys_dir}/id_ed25519.pub"
  local device_private="${device_dir}/id_ed25519" device_public="${device_dir}/id_ed25519.pub"
  local release_keys_dir="${WORKDIR}/releases/${BUILD_NUMBER}/keys"
  local release_output_keys_dir="${WORKDIR}/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/keys"

  mkdir -p "${device_dir}" "${release_keys_dir}" "${release_output_keys_dir}"

  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0600 "${top_private}" "${device_private}"
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0644 "${top_public}" "${device_public}"
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0600 "${top_private}" "${release_keys_dir}/id_ed25519"
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0644 "${top_public}" "${release_keys_dir}/id_ed25519.pub"
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0600 "${top_private}" "${release_output_keys_dir}/id_ed25519"
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0644 "${top_public}" "${release_output_keys_dir}/id_ed25519.pub"
}
ensure_release_ssh_keys() {
  [ "${SIGNED:-0}" = "1" ] || return 0
  log "Ensuring release SSH metadata key exists"
  local keys_dir="${WORKDIR}/keys"
  local device_dir="${keys_dir}/${DEVICE}"
  local top_private="${keys_dir}/id_ed25519"
  local top_public="${keys_dir}/id_ed25519.pub"
  local device_private="${device_dir}/id_ed25519"
  local source_private="${KEYS_SOURCE:-}/${DEVICE}/id_ed25519"
  local selected_private=""
  mkdir -p "${device_dir}"
  for candidate in "${top_private}" "${device_private}" "${source_private}"; do if valid_ssh_private_key "${candidate}"; then selected_private="${candidate}"; break; fi; done
  if [ -z "${selected_private}" ]; then log "No valid release SSH key found. Creating a new one."; rm -f "${top_private}" "${top_public}"; ssh-keygen -t ed25519 -N "" -C "wizeos-${DEVICE}-release-metadata" -f "${top_private}"; selected_private="${top_private}"; fi
  install -o "${BUILD_USER}" -g "${BUILD_USER}" -m 0600 "${selected_private}" "${top_private}"
  ssh-keygen -y -f "${top_private}" >"${top_public}"
  chmod 0644 "${top_public}"
  if [ -n "${KEYS_SOURCE:-}" ]; then
    mkdir -p "${KEYS_SOURCE}/${DEVICE}"
    cp -a "${top_private}" "${KEYS_SOURCE}/${DEVICE}/id_ed25519" 2>/dev/null || true
    cp -a "${top_public}" "${KEYS_SOURCE}/${DEVICE}/id_ed25519.pub" 2>/dev/null || true
    chmod 0600 "${KEYS_SOURCE}/${DEVICE}/id_ed25519" 2>/dev/null || true
    chmod 0644 "${KEYS_SOURCE}/${DEVICE}/id_ed25519.pub" 2>/dev/null || true
  fi
  copy_release_ssh_key_to_all_locations
  sudo -H -u "${BUILD_USER}" bash -lc "cd '${WORKDIR}' && ssh-keygen -y -f keys/id_ed25519 >/dev/null"
  echo "    Release SSH key OK: ${top_private}"
}
prepare_keys() {
  [ "${SIGNED:-0}" = "1" ] || { log "SIGNED=0, skipping keys"; return 0; }
  create_blank_signing_pass_file; copy_keys_into_workdir; ensure_release_ssh_keys
}
