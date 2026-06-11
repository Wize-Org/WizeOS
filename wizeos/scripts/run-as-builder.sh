#!/usr/bin/env bash
set -eo pipefail
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
cd "$HOME"
mkdir -p "$BASE_DIR" "$HOME/.ssh" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
whoami; printf 'HOME=%s\n' "$HOME"; printf 'PWD=%s\n' "$(pwd)"; node -v; yarn --version
export GIT_AUTHOR_NAME="${GIT_USER_NAME:-WizeOS Builder}" GIT_AUTHOR_EMAIL="${GIT_USER_EMAIL:-builder@wizeos.local}" GIT_COMMITTER_NAME="${GIT_USER_NAME:-WizeOS Builder}" GIT_COMMITTER_EMAIL="${GIT_USER_EMAIL:-builder@wizeos.local}"

git_identity_check() { git config --global --get user.name >/dev/null 2>&1 && git config --global --get user.email >/dev/null 2>&1 && echo "    Git identity already configured in ${GIT_CONFIG_GLOBAL}" || echo "    WARNING: Git identity missing; using environment identity"; }

repo_init_sync() {
  cd "$BASE_DIR"; mkdir -p "$WORKDIR"; cd "$WORKDIR"
  [ -d .repo ] && echo "==> Existing .repo found. Re-initializing manifest." || echo "==> Initializing new source tree."
  echo "    Manifest URL: ${MANIFEST_URL}"; echo "    Manifest branch/ref: ${MANIFEST_BRANCH}"; echo "    Manifest file: ${MANIFEST_FILE:-default.xml}"
  REPO_INIT_ARGS=(-u "${MANIFEST_URL}" -b "${MANIFEST_BRANCH}" --no-clone-bundle)
  [ -z "${MANIFEST_FILE}" ] || REPO_INIT_ARGS+=(-m "${MANIFEST_FILE}")
  repo init "${REPO_INIT_ARGS[@]}"
  if [ "${VERIFY_MANIFEST_TAG}" = "1" ]; then
    curl -fsSL https://grapheneos.org/allowed_signers > "$HOME/.ssh/grapheneos_allowed_signers"
    cd .repo/manifests; git config gpg.ssh.allowedSignersFile "$HOME/.ssh/grapheneos_allowed_signers"; git verify-tag "$(git describe)"; cd ../..
  else echo "==> VERIFY_MANIFEST_TAG=0, skipping signed manifest tag verification"; fi
  repo sync -j"$SYNC_JOBS" --no-clone-bundle --current-branch
}

collect_patch_files() {
  local patch_dir="$1"
  find "${patch_dir}" -type f \( -name '*.patch' -o -name '*.diff' \) | sort
}

apply_patch_dir() {
  local label="$1" patch_dir="$2"
  [ -d "${patch_dir}" ] || { echo "==> ${label}: no patch dir at ${patch_dir}, skipping"; return 0; }
  mapfile -t patches < <(collect_patch_files "${patch_dir}")
  [ "${#patches[@]}" -gt 0 ] || { echo "==> ${label}: no .patch or .diff files found"; return 0; }
  cd "$WORKDIR"
  for p in "${patches[@]}"; do
    echo "==> ${label}: applying $p"
    git apply --check "$p"
    git apply "$p"
  done
}

apply_patch_dir_required_in_repo() {
  local label="$1" patch_dir="$2" repo_dir="$3"
  [ -d "${patch_dir}" ] || { echo "ERROR: ${label}: patch dir missing: ${patch_dir}"; exit 1; }
  mapfile -t patches < <(collect_patch_files "${patch_dir}")
  [ "${#patches[@]}" -gt 0 ] || { echo "ERROR: ${label}: no .patch or .diff files found in ${patch_dir}"; exit 1; }
  cd "${repo_dir}"
  for p in "${patches[@]}"; do
    echo "==> ${label}: applying $p"
    git apply --check "$p"
    git apply "$p"
  done
}

apply_lsposed_patch_dir() { apply_patch_dir "LSPOSED_COMPAT" "$1"; }

kernel_should_build() {
  case "${KERNEL_BUILD}" in
    1) return 0 ;;
    0) return 1 ;;
    auto) [ "${ROOT}" = "ksunext" ] && return 0 || return 1 ;;
  esac
}

kernel_sync() {
  mkdir -p "${KERNEL_BASE_DIR}"
  if [ ! -d "${KERNEL_WORKDIR}/.git" ]; then
    echo "==> Cloning GrapheneOS kernel tree"
    git clone "${KERNEL_REPO_URL}" -b "${KERNEL_REPO_BRANCH}" --recurse-submodules "${KERNEL_WORKDIR}"
  else
    echo "==> Updating existing GrapheneOS kernel tree"
    cd "${KERNEL_WORKDIR}"
    git remote set-url origin "${KERNEL_REPO_URL}" || true
    git fetch origin "${KERNEL_REPO_BRANCH}"
    git checkout "${KERNEL_REPO_BRANCH}"
    git reset --hard "origin/${KERNEL_REPO_BRANCH}"
    git clean -fdx
    git submodule sync --recursive
    git submodule update --init --recursive
  fi
}

run_ksu_setup_script() {
  cd "${KERNEL_WORKDIR}"
  local setup_script="${HOME}/wizeos-ksunext-setup.sh"
  [ -n "${KSU_SETUP_URL_RESOLVED}" ] || { echo "ERROR: KernelSU Next setup integration requires KSU_SETUP_URL_RESOLVED"; exit 1; }
  echo "==> KernelSU Next: downloading setup script"
  echo "    ${KSU_SETUP_URL_RESOLVED}"
  curl -fsSL "${KSU_SETUP_URL_RESOLVED}" -o "${setup_script}"
  chmod 0755 "${setup_script}"
  if [ -n "${KSU_SETUP_ARG_RESOLVED}" ]; then
    echo "==> KernelSU Next: running setup script ${KSU_SETUP_ARG_RESOLVED}"
    sh "${setup_script}" "${KSU_SETUP_ARG_RESOLVED}"
  else
    echo "==> KernelSU Next: running setup script with default/latest behavior"
    sh "${setup_script}"
  fi
}

kernel_apply_root_patches() {
  cd "${KERNEL_WORKDIR}"
  git reset --hard HEAD
  git clean -fdx
  git submodule update --init --recursive

  if [ "${ROOT}" = "ksunext" ] && [ "${KSU_PATCH_KERNEL}" = "1" ]; then
    case "${KSU_INTEGRATION_RESOLVED}" in
      setup)
        run_ksu_setup_script
        ;;
      patch)
        apply_patch_dir_required_in_repo "KernelSU Next kernel patches" "${KSU_KERNEL_PATCH_DIR_RESOLVED}" "${KERNEL_WORKDIR}"
        ;;
      *)
        echo "ERROR: Unsupported KSU_INTEGRATION_RESOLVED=${KSU_INTEGRATION_RESOLVED}"
        exit 1
        ;;
    esac
  else
    echo "==> Skipping KernelSU Next kernel integration"
  fi

  if [ "${ROOT}" = "ksunext" ] && [ "${SUSFS_PATCH_KERNEL}" = "1" ]; then
    apply_patch_dir_required_in_repo "SUSFS kernel patches" "${SUSFS_KERNEL_PATCH_DIR}" "${KERNEL_WORKDIR}"
  else
    echo "==> Skipping SUSFS kernel patches"
  fi
}

kernel_build_and_copy() {
  if ! kernel_should_build; then
    echo "==> Kernel build disabled (${KERNEL_BUILD})"
    return 0
  fi

  kernel_sync
  kernel_apply_root_patches

  cd "${KERNEL_WORKDIR}"
  [ -x "${KERNEL_BUILD_SCRIPT}" ] || { echo "ERROR: Kernel build script not executable/found: ${KERNEL_WORKDIR}/${KERNEL_BUILD_SCRIPT}"; exit 1; }

  if [ "${KERNEL_CLEAN}" = "1" ]; then
    echo "==> Cleaning kernel output"
    rm -rf "out/${KERNEL_CODENAME}"
  fi

  echo "==> Building GrapheneOS kernel ${KERNEL_CODENAME}"
  read -r -a KERNEL_BUILD_ARGS_ARRAY <<< "${KERNEL_BUILD_ARGS}"
  if [ -f "${KERNEL_REPO_MANIFEST_FILE}" ]; then
    "${KERNEL_BUILD_SCRIPT}" "${KERNEL_BUILD_ARGS_ARRAY[@]}" --repo_manifest="$(realpath .):$(realpath "${KERNEL_REPO_MANIFEST_FILE}")"
  else
    "${KERNEL_BUILD_SCRIPT}" "${KERNEL_BUILD_ARGS_ARRAY[@]}"
  fi

  DIST_DIR="${KERNEL_WORKDIR}/${KERNEL_DIST_DIR}"
  DEST_DIR="${WORKDIR}/${KERNEL_OS_PREBUILT_DIR}"
  [ -d "${DIST_DIR}" ] || { echo "ERROR: Kernel dist directory not found: ${DIST_DIR}"; exit 1; }
  [ -d "${WORKDIR}" ] || { echo "ERROR: OS workdir not found: ${WORKDIR}. Run ACTION=sync first."; exit 1; }

  echo "==> Copying kernel prebuilts"
  echo "    From: ${DIST_DIR}/"
  echo "    To  : ${DEST_DIR}/"
  mkdir -p "${DEST_DIR}"
  rsync -a --delete "${DIST_DIR}/" "${DEST_DIR}/"
}

patch_updater_url() {
  cd "$WORKDIR"; UPDATER_CONFIG="packages/apps/Updater/res/values/config.xml"
  [ -f "${UPDATER_CONFIG}" ] || { echo "WARNING: Missing ${UPDATER_CONFIG}"; return 0; }
  python3 - "${UPDATER_CONFIG}" "${UPDATE_SERVER}" <<'PY'
from pathlib import Path
import re, sys
from xml.sax.saxutils import escape
path=Path(sys.argv[1]); url=escape(sys.argv[2], {'"':'&quot;',"'":'&apos;'}); text=path.read_text()
def repl(text,name,value,add=False):
    pat=re.compile(rf'([ \t]*)<string\s+name="{re.escape(name)}"([^>]*)>.*?</string>', re.S); m=pat.search(text)
    if m: return pat.sub(f'{m.group(1)}<string name="{name}"{m.group(2)}>{value}</string>', text, count=1)
    if add: return text.replace('</resources>', f'    <string name="{name}" translatable="false">{value}</string>\n</resources>', 1)
    return text
text=repl(text,'url',url,True); text=repl(text,'update_base_url',url,False); path.write_text(text)
PY
  grep -n 'wizesoft\|releases.grapheneos\|update_base_url' "${UPDATER_CONFIG}" || true
}

android_build() {
  cd "$WORKDIR"
  [ "${LSPOSED_COMPAT}" != "1" ] || apply_lsposed_patch_dir "${LSPOSED_PATCHES_DIR}"
  kernel_build_and_copy
  patch_updater_url
  source build/envsetup.sh
  yarn --cwd vendor/adevtool/ install
  export PATH="$PWD/vendor/adevtool/bin:$PWD/vendor/adevtool/node_modules/.bin:$PATH"
  if [ -f vendor/adevtool/bin/run ]; then node vendor/adevtool/bin/run generate-all --devices "$DEVICE"; else adevtool generate-all --devices "$DEVICE"; fi
  lunch "${DEVICE}-cur-user"
  unset BUILD_DATETIME; export BUILD_NUMBER="${BUILD_NUMBER:-${TAG}}" OFFICIAL_BUILD="${OFFICIAL_BUILD:-true}"
  [ "${CLEAN_OUT}" != "1" ] || rm -rf out
  m target-files-package -j"$JOBS"; m otatools-package -j"$JOBS"; script/finalize.sh
}

ensure_builder_release_ssh_keys() {
  cd "$WORKDIR"
  local release_keys_dir="releases/${BUILD_NUMBER}/keys"
  local release_output_keys_dir="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/keys"
  mkdir -p "keys/${DEVICE}" "${release_keys_dir}" "${release_output_keys_dir}"

  [ -f keys/id_ed25519 ] || [ ! -f "keys/${DEVICE}/id_ed25519" ] || cp -a "keys/${DEVICE}/id_ed25519" keys/id_ed25519
  if [ ! -f keys/id_ed25519 ]; then ssh-keygen -t ed25519 -N "" -C "wizeos-${DEVICE}-release-metadata" -f keys/id_ed25519; fi

  chmod 0600 keys/id_ed25519
  ssh-keygen -y -f keys/id_ed25519 > keys/id_ed25519.pub

  cp -a keys/id_ed25519 "keys/${DEVICE}/id_ed25519"
  cp -a keys/id_ed25519.pub "keys/${DEVICE}/id_ed25519.pub"
  cp -a keys/id_ed25519 "${release_keys_dir}/id_ed25519"
  cp -a keys/id_ed25519.pub "${release_keys_dir}/id_ed25519.pub"
  cp -a keys/id_ed25519 "${release_output_keys_dir}/id_ed25519"
  cp -a keys/id_ed25519.pub "${release_output_keys_dir}/id_ed25519.pub"

  chmod 0600 keys/id_ed25519 "keys/${DEVICE}/id_ed25519" "${release_keys_dir}/id_ed25519" "${release_output_keys_dir}/id_ed25519"
  chmod 0644 keys/id_ed25519.pub "keys/${DEVICE}/id_ed25519.pub" "${release_keys_dir}/id_ed25519.pub" "${release_output_keys_dir}/id_ed25519.pub"
  ssh-keygen -y -f keys/id_ed25519 >/dev/null
  echo "==> Release SSH key ready: keys/id_ed25519"
}

patch_magisk_ota() {
  cd "$WORKDIR"; RELEASE_DIR="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
  OTA_ZIP="$(find "${RELEASE_DIR}" -maxdepth 1 -type f -name '*ota_update*.zip' ! -name '*-magisk.zip' ! -name '*-ksunext*.zip' | sort | head -n 1)"
  [ -n "${OTA_ZIP}" ] || { echo "ERROR: Could not find OTA zip in ${RELEASE_DIR}"; exit 1; }
  ROOTED_OTA="${OTA_ZIP%.zip}-magisk.zip"
  AVBROOT_ARGS=(ota patch --input "${OTA_ZIP}" --output "${ROOTED_OTA}" --key-avb "${AVBROOT_AVB_KEY}" --key-ota "${AVBROOT_OTA_KEY}" --cert-ota "${AVBROOT_OTA_CERT}" --magisk "${MAGISK_APK_WORKDIR}" --magisk-preinit-device "${MAGISK_PREINIT_DEVICE}")
  [ -z "${AVBROOT_PASS_AVB_FILE}" ] || AVBROOT_ARGS+=(--pass-avb-file "${AVBROOT_PASS_AVB_FILE}")
  [ -z "${AVBROOT_PASS_OTA_FILE}" ] || AVBROOT_ARGS+=(--pass-ota-file "${AVBROOT_PASS_OTA_FILE}")
  "${AVBROOT}" "${AVBROOT_ARGS[@]}"; echo "Rooted OTA: ${ROOTED_OTA}"
}

copy_ksu_release_artifacts() {
  cd "$WORKDIR"; RELEASE_DIR="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
  [ -d "${RELEASE_DIR}" ] || { echo "ERROR: Missing release directory: ${RELEASE_DIR}"; exit 1; }
  OTA_ZIP="$(find "${RELEASE_DIR}" -maxdepth 1 -type f -name '*ota_update*.zip' ! -name '*-magisk.zip' ! -name '*-ksunext*.zip' | sort | head -n 1)"
  [ -n "${OTA_ZIP}" ] || { echo "ERROR: Could not find OTA zip in ${RELEASE_DIR}"; exit 1; }
  local suffix="ksunext"
  if [ "${KSUNEXT_SUSFS}" = "1" ]; then suffix="${suffix}-susfs"; fi
  KSU_OTA="${OTA_ZIP%.zip}-${suffix}.zip"
  cp -a "${OTA_ZIP}" "${KSU_OTA}"
  [ -z "${KSU_MANAGER_APK_WORKDIR}" ] || cp -a "${KSU_MANAGER_APK_WORKDIR}" "${RELEASE_DIR}/${KSU_MANAGER_RELEASE_NAME}"
  [ -z "${KSU_ZYGISK_ZIP_WORKDIR}" ] || cp -a "${KSU_ZYGISK_ZIP_WORKDIR}" "${RELEASE_DIR}/${KSU_ZYGISK_RELEASE_NAME}"
  [ -z "${SUSFS_MODULE_ZIP_WORKDIR}" ] || cp -a "${SUSFS_MODULE_ZIP_WORKDIR}" "${RELEASE_DIR}/susfs4ksu.zip"
  echo "KernelSU Next OTA: ${KSU_OTA}"
}

# Backward-compatible function name.
copy_ksunext_release_artifacts() { copy_ksu_release_artifacts; }

signed_release() {
  cd "$WORKDIR"; [ "${SIGNED}" = "1" ] || return 0
  ensure_builder_release_ssh_keys; mkdir -p "releases/${BUILD_NUMBER}"
  LOG="releases/${BUILD_NUMBER}/generate-release-${DEVICE}-${BUILD_NUMBER}.log"
  if [ -n "${SIGNING_KEY_PASSPHRASE_FILE:-}" ] && [ -f "${SIGNING_KEY_PASSPHRASE_FILE}" ]; then (umask 077; script/generate-release.sh "$DEVICE" "$BUILD_NUMBER") < "${SIGNING_KEY_PASSPHRASE_FILE}" 2>&1 | tee "$LOG"; else (umask 077; script/generate-release.sh "$DEVICE" "$BUILD_NUMBER") 2>&1 | tee "$LOG"; fi
  case "${ROOT}" in
    magisk) patch_magisk_ota ;;
    ksunext) copy_ksu_release_artifacts ;;
  esac
}

echo "==> Configuring Git identity for repo"; git_identity_check
case "${BUILDER_ACTION:-all}" in sync) repo_init_sync ;; kernel) kernel_build_and_copy ;; build) android_build ;; release) signed_release ;; magisk) patch_magisk_ota ;; ksunext) copy_ksu_release_artifacts ;; all) repo_init_sync; android_build; signed_release ;; *) echo "ERROR: Unknown BUILDER_ACTION=${BUILDER_ACTION}"; exit 1 ;; esac
