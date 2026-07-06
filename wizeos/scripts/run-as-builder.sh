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

apply_single_patch_in_repo() {
  local label="$1" repo_dir="$2" patch_file="$3"
  cd "${repo_dir}"
  if git apply --check "${patch_file}" >/dev/null 2>&1; then
    echo "==> ${label}: applying ${patch_file}"
    git apply "${patch_file}"
  elif git apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    echo "==> ${label}: already applied ${patch_file}; skipping"
  else
    echo "ERROR: ${label}: patch does not apply cleanly and is not already applied: ${patch_file}" >&2
    git apply --check "${patch_file}"
  fi
}

apply_patch_dir() {
  local label="$1" patch_dir="$2"
  [ -d "${patch_dir}" ] || { echo "==> ${label}: no patch dir at ${patch_dir}, skipping"; return 0; }
  mapfile -t patches < <(collect_patch_files "${patch_dir}")
  [ "${#patches[@]}" -gt 0 ] || { echo "==> ${label}: no .patch or .diff files found"; return 0; }
  for p in "${patches[@]}"; do
    apply_single_patch_in_repo "${label}" "${WORKDIR}" "${p}"
  done
}

apply_patch_dir_required_in_repo() {
  local label="$1" patch_dir="$2" repo_dir="$3"
  [ -d "${patch_dir}" ] || { echo "ERROR: ${label}: patch dir missing: ${patch_dir}"; exit 1; }
  mapfile -t patches < <(collect_patch_files "${patch_dir}")
  [ "${#patches[@]}" -gt 0 ] || { echo "ERROR: ${label}: no .patch or .diff files found in ${patch_dir}"; exit 1; }
  for p in "${patches[@]}"; do
    apply_single_patch_in_repo "${label}" "${repo_dir}" "${p}"
  done
}

apply_wizeos_profile_patch_dir() {
  local profile="${WIZEOS_PROFILE:-balanced}"
  case "${profile}" in
    secure)
      echo "==> WIZEOS_PROFILE=secure: skipping compatibility profile patches"
      ;;
    balanced|flexible)
      apply_patch_dir "WIZEOS_PROFILE=${profile}" "${WIZEOS_PROFILE_PATCHES_DIR}"
      ;;
    *)
      echo "ERROR: Unsupported WIZEOS_PROFILE=${profile}"
      exit 1
      ;;
  esac
}

apply_lsposed_patch_dir() { apply_patch_dir "LSPOSED_COMPAT" "$1"; }

kernel_should_build() {
  case "${KERNEL_BUILD}" in
    1|prebuilt) return 0 ;;
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

resolve_kernel_source_dir() {
  local candidates=()
  [ -z "${KERNEL_SOURCE_SUBDIR:-}" ] || candidates+=("${KERNEL_WORKDIR}/${KERNEL_SOURCE_SUBDIR}")
  [ -z "${KSU_KERNEL_SOURCE_SUBDIR:-}" ] || candidates+=("${KERNEL_WORKDIR}/${KSU_KERNEL_SOURCE_SUBDIR}")
  candidates+=(
    "${KERNEL_WORKDIR}/common/ack"
    "${KERNEL_WORKDIR}/common"
    "${KERNEL_WORKDIR}"
  )

  local d
  for d in "${candidates[@]}"; do
    [ -n "${d}" ] || continue
    if [ -d "${d}/drivers" ] || [ -d "${d}/common/drivers" ]; then
      echo "${d}"
      return 0
    fi
  done

  echo "ERROR: Could not find kernel source dir with drivers/ or common/drivers under ${KERNEL_WORKDIR}" >&2
  echo "Set KERNEL_SOURCE_SUBDIR=common/ack if this kernel uses the GrapheneOS Pixel wrapper layout." >&2
  exit 1
}

run_ksu_setup_script() {
  local kernel_source_dir
  kernel_source_dir="$(resolve_kernel_source_dir)"
  cd "${kernel_source_dir}"
  local setup_script="${HOME}/wizeos-ksunext-setup.sh"
  [ -n "${KSU_SETUP_URL_RESOLVED}" ] || { echo "ERROR: KernelSU Next setup integration requires KSU_SETUP_URL_RESOLVED"; exit 1; }
  echo "==> KernelSU Next: using kernel source ${kernel_source_dir}"
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

apply_susfs_kernel_patches() {
  local kernel_source_dir="$1"
  local susfs_apply_script="${SUSFS_KERNEL_PATCH_DIR}/apply.sh"

  if [ -x "${susfs_apply_script}" ]; then
    echo "==> SUSFS kernel patches: running ${susfs_apply_script}"
    "${susfs_apply_script}" "${kernel_source_dir}"
  elif [ -f "${susfs_apply_script}" ]; then
    echo "==> SUSFS kernel patches: running ${susfs_apply_script} with bash"
    bash "${susfs_apply_script}" "${kernel_source_dir}"
  else
    apply_patch_dir_required_in_repo "SUSFS kernel patches" "${SUSFS_KERNEL_PATCH_DIR}" "${kernel_source_dir}"
  fi
}

kernel_apply_root_patches() {
  cd "${KERNEL_WORKDIR}"
  git reset --hard HEAD
  git clean -fdx
  git submodule update --init --recursive

  local kernel_source_dir
  kernel_source_dir="$(resolve_kernel_source_dir)"
  if git -C "${kernel_source_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${kernel_source_dir}" reset --hard HEAD
    git -C "${kernel_source_dir}" clean -fdx
  fi

  if [ "${ROOT}" = "ksunext" ] && [ "${KSU_PATCH_KERNEL}" = "1" ]; then
    case "${KSU_INTEGRATION_RESOLVED}" in
      setup)
        run_ksu_setup_script
        ;;
      patch)
        apply_patch_dir_required_in_repo "KernelSU Next kernel patches" "${KSU_KERNEL_PATCH_DIR_RESOLVED}" "${kernel_source_dir}"
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
    apply_susfs_kernel_patches "${kernel_source_dir}"
  else
    echo "==> Skipping SUSFS kernel patches"
  fi
}

install_prebuilt_kernel_image() {
  local src="${KERNEL_PREBUILT_IMAGE:-/root/Image}"
  local image_name="${KERNEL_PREBUILT_IMAGE_NAME:-Image}"
  local dest_dir="${WORKDIR}/${KERNEL_OS_PREBUILT_DIR}"
  local dest="${dest_dir}/${image_name}"

  [ -f "${src}" ] || { echo "ERROR: Prebuilt kernel Image not found: ${src}"; exit 1; }
  [ -d "${WORKDIR}" ] || { echo "ERROR: OS workdir not found: ${WORKDIR}. Run ACTION=sync first."; exit 1; }

  echo "==> Installing prebuilt kernel Image"
  echo "    From: ${src}"
  echo "    To  : ${dest}"
  mkdir -p "${dest_dir}"
  cp -a "${src}" "${dest}"
  chmod 0644 "${dest}"

  if command -v strings >/dev/null 2>&1; then
    strings "${dest}" | grep -m1 '^Linux version ' || true
  fi
}

kernel_build_and_copy() {
  if ! kernel_should_build; then
    echo "==> Kernel build disabled (${KERNEL_BUILD})"
    return 0
  fi

  if [ "${KERNEL_BUILD}" = "prebuilt" ]; then
    install_prebuilt_kernel_image
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

setup_android_build_env() {
  cd "$WORKDIR"
  source build/envsetup.sh
  lunch "${DEVICE}-cur-user"
  unset BUILD_DATETIME
  export BUILD_NUMBER="${BUILD_NUMBER:-${TAG}}" OFFICIAL_BUILD="${OFFICIAL_BUILD:-true}"
}

android_build() {
  cd "$WORKDIR"
  apply_wizeos_profile_patch_dir
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
  m target-files-package -j"$JOBS"
  m otatools-package -j"$JOBS"
  script/finalize.sh
  generate_grapheneos_release
}

ensure_builder_release_ssh_keys() {
  cd "$WORKDIR"
  local release_keys_dir="releases/${BUILD_NUMBER}/keys"
  local release_output_keys_dir="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/keys"
  mkdir -p "keys/${DEVICE}" "${release_keys_dir}" "${release_output_keys_dir}"

  [ -f keys/id_ed25519 ] || [ ! -f "keys/${DEVICE}/id_ed25519" ] || cp -a "keys/${DEVICE}/id_ed25519" keys/id_ed25519
  if [ ! -f keys/id_ed25519 ]; then
    ssh-keygen -t ed25519 -N "" -C "wizeos-${DEVICE}-release-metadata" -f keys/id_ed25519
  fi

  chmod 0600 keys/id_ed25519
  if ssh-keygen -y -P "" -f keys/id_ed25519 > keys/id_ed25519.pub 2>/dev/null; then
    :
  elif [ -n "${RELEASE_SSH_KEY_PASSPHRASE:-}" ]; then
    echo "==> Removing release SSH key passphrase for unattended build"
    ssh-keygen -p -P "${RELEASE_SSH_KEY_PASSPHRASE}" -N "" -f keys/id_ed25519 >/dev/null
    ssh-keygen -y -P "" -f keys/id_ed25519 > keys/id_ed25519.pub
  elif [ "${RELEASE_SSH_KEY_AUTOREGENERATE:-0}" = "1" ]; then
    echo "==> Existing release SSH key is encrypted; regenerating no-passphrase key"
    rm -f keys/id_ed25519 keys/id_ed25519.pub "keys/${DEVICE}/id_ed25519" "keys/${DEVICE}/id_ed25519.pub"
    ssh-keygen -t ed25519 -N "" -C "wizeos-${DEVICE}-release-metadata" -f keys/id_ed25519
    ssh-keygen -y -P "" -f keys/id_ed25519 > keys/id_ed25519.pub
  else
    echo "ERROR: release SSH key is encrypted and would prompt for a passphrase."
    echo "Set RELEASE_SSH_KEY_PASSPHRASE to remove the passphrase, set RELEASE_SSH_KEY_AUTOREGENERATE=1, or provide a no-passphrase key."
    exit 1
  fi

  cp -a keys/id_ed25519 "keys/${DEVICE}/id_ed25519"
  cp -a keys/id_ed25519.pub "keys/${DEVICE}/id_ed25519.pub"
  cp -a keys/id_ed25519 "${release_keys_dir}/id_ed25519"
  cp -a keys/id_ed25519.pub "${release_keys_dir}/id_ed25519.pub"
  cp -a keys/id_ed25519 "${release_output_keys_dir}/id_ed25519"
  cp -a keys/id_ed25519.pub "${release_output_keys_dir}/id_ed25519.pub"

  chmod 0600 keys/id_ed25519 "keys/${DEVICE}/id_ed25519" "${release_keys_dir}/id_ed25519" "${release_output_keys_dir}/id_ed25519"
  chmod 0644 keys/id_ed25519.pub "keys/${DEVICE}/id_ed25519.pub" "${release_keys_dir}/id_ed25519.pub" "${release_output_keys_dir}/id_ed25519.pub"
  ssh-keygen -y -P "" -f keys/id_ed25519 >/dev/null
  echo "==> Release SSH key ready: keys/id_ed25519"
}

generate_grapheneos_release() {
  cd "$WORKDIR"
  [ "${GENERATE_RELEASE:-1}" = "1" ] || { echo "==> GENERATE_RELEASE=0, skipping script/generate-release.sh"; return 0; }
  [ -x script/generate-release.sh ] || { echo "ERROR: Missing or non-executable script/generate-release.sh"; exit 1; }
  if [ -z "${TARGET_PRODUCT:-}" ]; then
    echo "==> Preparing Android build environment for release generation"
    setup_android_build_env
  fi
  ensure_builder_release_ssh_keys
  echo "==> Generating full GrapheneOS release artifacts"
  echo "    Device      : ${DEVICE}"
  echo "    Build number: ${BUILD_NUMBER}"
  script/generate-release.sh "${DEVICE}" "${BUILD_NUMBER}"
}

find_release_ota_zip() {
  local release_dir="$1"
  find "${release_dir}" -maxdepth 1 -type f \
    \( -name '*ota*.zip' -o -name '*update*.zip' \) \
    ! -name '*otatools*.zip' \
    ! -name '*target_files*.zip' \
    ! -name '*-magisk.zip' \
    ! -name '*-ksunext*.zip' \
    | sort | head -n 1
}

generate_release_ota_zip() {
  cd "$WORKDIR"
  local release_base="releases/${BUILD_NUMBER}"
  local release_dir="${release_base}/release-${DEVICE}-${BUILD_NUMBER}"
  local target_files="${release_base}/${DEVICE}-target_files.zip"
  local otatools_zip="${release_base}/${DEVICE}-otatools.zip"
  local out_ota="${release_dir}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"
  local tmp_dir="/tmp/wizeos-otatools-${DEVICE}-${BUILD_NUMBER}-$$"
  local ota_tool cert_prefix
  local key_args=()

  [ -f "${target_files}" ] || { echo "ERROR: Missing target files zip: ${target_files}"; exit 1; }
  [ -f "${otatools_zip}" ] || { echo "ERROR: Missing otatools zip: ${otatools_zip}"; exit 1; }
  mkdir -p "${release_dir}"

  echo "==> Generating OTA from target files"
  echo "    Target files: ${target_files}"
  echo "    OTA tools   : ${otatools_zip}"
  echo "    Output OTA  : ${out_ota}"

  rm -rf "${tmp_dir}"
  mkdir -p "${tmp_dir}"
  unzip -q "${otatools_zip}" -d "${tmp_dir}"
  ota_tool="$(find "${tmp_dir}" -type f -name ota_from_target_files | sort | head -n 1)"
  [ -n "${ota_tool}" ] || { echo "ERROR: ota_from_target_files not found in ${otatools_zip}"; exit 1; }

  cert_prefix="$(unzip -p "${target_files}" META/misc_info.txt 2>/dev/null | sed -n 's/^default_system_dev_certificate=//p' | head -n 1)"
  if [ -n "${cert_prefix}" ] && [ -f "${cert_prefix}.pk8" ] && [ -f "${cert_prefix}.x509.pem" ]; then
    key_args=(-k "${cert_prefix}")
    echo "    OTA key     : ${cert_prefix}"
  else
    echo "    OTA key     : default from target files"
  fi

  "${ota_tool}" "${key_args[@]}" "${target_files}" "${out_ota}"
  rm -rf "${tmp_dir}"
  echo "==> Generated OTA: ${out_ota}"
}

patch_magisk_ota() {
  cd "$WORKDIR"; RELEASE_DIR="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
  mkdir -p "${RELEASE_DIR}"
  OTA_ZIP="$(find_release_ota_zip "${RELEASE_DIR}")"
  if [ -z "${OTA_ZIP}" ]; then
    generate_release_ota_zip
    OTA_ZIP="$(find_release_ota_zip "${RELEASE_DIR}")"
  fi
  [ -n "${OTA_ZIP}" ] || { echo "ERROR: Could not find or generate OTA zip in ${RELEASE_DIR}"; exit 1; }
  ROOTED_OTA="${OTA_ZIP%.zip}-magisk.zip"
  AVBROOT_ARGS=(ota patch --input "${OTA_ZIP}" --output "${ROOTED_OTA}" --key-avb "${AVBROOT_AVB_KEY}" --key-ota "${AVBROOT_OTA_KEY}" --cert-ota "${AVBROOT_OTA_CERT}" --magisk "${MAGISK_APK_WORKDIR}" --magisk-preinit-device "${MAGISK_PREINIT_DEVICE}")
  [ -z "${AVBROOT_PASS_AVB_FILE}" ] || AVBROOT_ARGS+=(--pass-avb-file "${AVBROOT_PASS_AVB_FILE}")
  [ -z "${AVBROOT_PASS_OTA_FILE}" ] || AVBROOT_ARGS+=(--pass-ota-file "${AVBROOT_PASS_OTA_FILE}")
  "${AVBROOT}" "${AVBROOT_ARGS[@]}"; echo "Rooted OTA: ${ROOTED_OTA}"
}

copy_ksu_release_artifacts() {
  cd "$WORKDIR"; RELEASE_DIR="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
  [ -d "${RELEASE_DIR}" ] || { echo "ERROR: Missing release dir: ${RELEASE_DIR}"; exit 1; }
  [ -z "${KSU_MANAGER_APK_WORKDIR:-}" ] || cp -f "${KSU_MANAGER_APK_WORKDIR}" "${RELEASE_DIR}/${KSU_MANAGER_RELEASE_NAME:-KernelSU_Next.apk}"
  [ -z "${KSU_ZYGISK_ZIP_WORKDIR:-}" ] || cp -f "${KSU_ZYGISK_ZIP_WORKDIR}" "${RELEASE_DIR}/${KSU_ZYGISK_RELEASE_NAME:-Zygisk-Next.zip}"
  [ "${KSUNEXT_SUSFS}" != "1" ] || [ -z "${SUSFS_MODULE_ZIP_WORKDIR:-}" ] || cp -f "${SUSFS_MODULE_ZIP_WORKDIR}" "${RELEASE_DIR}/susfs4ksu.zip"
}

case "${BUILDER_ACTION:-all}" in
  sync)
    git_identity_check; repo_init_sync ;;
  kernel)
    kernel_build_and_copy ;;
  build)
    android_build ;;
  release)
    cd "$WORKDIR"; setup_android_build_env; script/finalize.sh; generate_grapheneos_release; copy_ksu_release_artifacts ;;
  magisk)
    patch_magisk_ota ;;
  ksunext)
    copy_ksu_release_artifacts ;;
  all)
    git_identity_check; repo_init_sync; android_build; copy_ksu_release_artifacts; [ "${ROOT}" != "magisk" ] || patch_magisk_ota ;;
  *) echo "ERROR: Unknown BUILDER_ACTION=${BUILDER_ACTION}"; exit 1 ;;
esac
