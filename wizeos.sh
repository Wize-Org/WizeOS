#!/usr/bin/env bash
# GrapheneOS build + signed-release script for Pixel 10 Pro XL (mustang)
# Ubuntu Server 24.04 LTS
# Run as root: bash wizeos.sh

set -eo pipefail

DEVICE="${DEVICE:-mustang}"
TAG="${TAG:-2026060600}"
# GrapheneOS finalize.sh expects BUILD_NUMBER in the environment.
# Default to TAG so release directories and OTA metadata stay aligned with the manifest tag.
BUILD_NUMBER="${BUILD_NUMBER:-${TAG}}"
# CLEAN_OUT=1 removes out/ for a fresh build. Use CLEAN_OUT=0 to resume an already-built tree.
CLEAN_OUT="${CLEAN_OUT:-1}"
JOBS="${JOBS:-24}"
BUILD_USER="${BUILD_USER:-builder}"
BASE_DIR="${BASE_DIR:-/home/${BUILD_USER}/android}"
WORKDIR="${BASE_DIR}/grapheneos-${TAG}"
SYNC_JOBS="${SYNC_JOBS:-8}"
# SIGNED=1 builds and signs the release. SIGNED=0 builds/finalizes only and skips signing.
SIGNED="${SIGNED:-1}"
# ROOT=none creates a normal GrapheneOS release. ROOT=magisk patches the signed OTA with Magisk using avbroot.
ROOT="${ROOT:-none}"
# Required only when ROOT=magisk. This can point anywhere readable by root; the script copies it into WORKDIR.
MAGISK_APK="${MAGISK_APK:-}"
# Pixel 10 Pro XL / mustang is commonly sda10. Override this if Magisk reports a different pre-init device.
MAGISK_PREINIT_DEVICE="${MAGISK_PREINIT_DEVICE:-sda10}"
# Required only when ROOT=magisk. avbroot can be an absolute path or a command in PATH.
AVBROOT="${AVBROOT:-avbroot}"
# Optional overrides for avbroot keys. Defaults are derived from keys/${DEVICE}/.
AVBROOT_AVB_KEY="${AVBROOT_AVB_KEY:-}"
AVBROOT_OTA_KEY="${AVBROOT_OTA_KEY:-}"
AVBROOT_OTA_CERT="${AVBROOT_OTA_CERT:-}"
# Optional avbroot passphrase files for non-interactive runs. Leave blank to let avbroot prompt.
AVBROOT_PASS_AVB_FILE="${AVBROOT_PASS_AVB_FILE:-}"
AVBROOT_PASS_OTA_FILE="${AVBROOT_PASS_OTA_FILE:-}"
# Keep START_OVER=0 because you said you already have a keys folder.
# If you set START_OVER=1, the script will back up keys before deleting the tree.
START_OVER="${START_OVER:-0}"
# Optional: set KEYS_SOURCE=/path/to/keys if your keys folder is not already in the source tree.
KEYS_SOURCE="${KEYS_SOURCE:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this setup script as root. It will run GrapheneOS build steps as ${BUILD_USER}."
  exit 1
fi

case "${SIGNED}" in
  0|1) ;;
  *)
    echo "ERROR: SIGNED must be 1 to sign the release or 0 to skip signing. Current value: ${SIGNED}"
    exit 1
    ;;
esac

case "${CLEAN_OUT}" in
  0|1) ;;
  *)
    echo "ERROR: CLEAN_OUT must be 1 to clean out/ or 0 to resume. Current value: ${CLEAN_OUT}"
    exit 1
    ;;
esac

case "${ROOT}" in
  none|magisk) ;;
  *)
    echo "ERROR: ROOT must be none or magisk. Current value: ${ROOT}"
    exit 1
    ;;
esac

if [ "${ROOT}" = "magisk" ] && [ "${SIGNED}" != "1" ]; then
  echo "ERROR: ROOT=magisk requires SIGNED=1 because avbroot must patch a signed OTA."
  exit 1
fi

if [ "${ROOT}" = "magisk" ] && [ -z "${MAGISK_APK}" ]; then
  echo "ERROR: ROOT=magisk requires MAGISK_APK=/path/to/Magisk.apk"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log() {
  echo "==> $*"
}

log "GrapheneOS build setup"
echo "    Device: ${DEVICE}"
echo "    Tag: ${TAG}"
echo "    Jobs: ${JOBS}"
echo "    Build user: ${BUILD_USER}"
echo "    Workdir: ${WORKDIR}"
echo "    Build number: ${BUILD_NUMBER}"
echo "    Clean out: ${CLEAN_OUT}"
echo "    Start over: ${START_OVER}"
echo "    Signed release: ${SIGNED}"
echo "    Root mode: ${ROOT}"
if [ "${ROOT}" = "magisk" ]; then
  echo "    Magisk APK: ${MAGISK_APK}"
  echo "    Magisk pre-init device: ${MAGISK_PREINIT_DEVICE}"
  echo "    avbroot: ${AVBROOT}"
fi
echo "    Keys source: ${KEYS_SOURCE:-auto-detect}"

log "Allowing nsjail to use unprivileged user namespaces on Ubuntu 24.04"
# Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor.
# Android/Soong nsjail needs this for sandboxed build steps used by adevtool.
# This is intended for a dedicated build host.
if sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
  sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
  cat >/etc/sysctl.d/99-grapheneos-build.conf <<'SYSCTL_EOF'
kernel.apparmor_restrict_unprivileged_userns=0
SYSCTL_EOF
fi

log "Installing base packages"
apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  sudo \
  repo \
  git \
  openssh-client \
  python3 \
  zip \
  unzip \
  rsync \
  diffutils \
  fontconfig \
  fonts-dejavu-core \
  hostname \
  openssl \
  gperf \
  gcc-multilib \
  libc6-dev-i386 \
  build-essential

log "Removing Ubuntu Node/Yarn packages that conflict with Node.js 24"
apt-get remove -y yarnpkg nodejs npm libnode-dev || true
apt-get autoremove -y || true
apt-get clean

log "Installing Node.js 24 from NodeSource"
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "${NODE_MAJOR}" -lt 24 ]; then
  echo "ERROR: Node.js 24+ is required, but installed version is $(node -v)"
  exit 1
fi

log "Installing Yarn Classic through npm, not apt yarnpkg"
npm install -g yarn@1.22.22
hash -r
node -v
yarn --version

if ! id -u "${BUILD_USER}" >/dev/null 2>&1; then
  log "Creating build user: ${BUILD_USER}"
  useradd -m -s /bin/bash "${BUILD_USER}"
fi
usermod -aG sudo "${BUILD_USER}"

log "Fixing repo system-cache permission issue"
# Some repo versions try to cache system git config as /etc/.repo_gitconfig.json.
# Create it once and allow the builder user to update only this cache file.
touch /etc/.repo_gitconfig.json
chown "${BUILD_USER}:${BUILD_USER}" /etc/.repo_gitconfig.json
chmod 0644 /etc/.repo_gitconfig.json

mkdir -p "${BASE_DIR}"
chown -R "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}"

# Preserve existing keys if a user explicitly asks for START_OVER=1.
KEYS_BACKUP="/home/${BUILD_USER}/keys-backup-${DEVICE}-$(date +%Y%m%d%H%M%S)"
if [ "${START_OVER}" = "1" ]; then
  log "START_OVER=1 requested. Backing up any existing keys before deleting the tree."
  if [ -d "${WORKDIR}/keys" ]; then
    mkdir -p "${KEYS_BACKUP}"
    cp -a "${WORKDIR}/keys/." "${KEYS_BACKUP}/"
    chown -R "${BUILD_USER}:${BUILD_USER}" "${KEYS_BACKUP}"
    echo "    Backed up keys to ${KEYS_BACKUP}"
  fi

  log "Removing old GrapheneOS tree for a clean source/build output"
  rm -rf "${WORKDIR}"
  rm -rf "/root/android/grapheneos-${TAG}"
fi

# If an old root-owned tree exists and the builder tree does not, move it instead of copying.
# This saves disk space on 450 GB servers.
if [ -d "/root/android/grapheneos-${TAG}" ] && [ ! -d "${WORKDIR}" ]; then
  log "Moving existing /root/android/grapheneos-${TAG} to ${WORKDIR}"
  mkdir -p "${BASE_DIR}"
  mv "/root/android/grapheneos-${TAG}" "${WORKDIR}"
  chown -R "${BUILD_USER}:${BUILD_USER}" "${WORKDIR}"
fi

# Auto-detect an existing keys folder and place it in the source tree.
# GrapheneOS generate-release.sh expects keys under the source tree, normally keys/${DEVICE}/.
log "Preparing existing keys folder"
mkdir -p "${WORKDIR}"
if [ "${SIGNED}" = "1" ]; then
  if [ -n "${KEYS_SOURCE}" ]; then
    if [ ! -d "${KEYS_SOURCE}" ]; then
      echo "ERROR: KEYS_SOURCE is set but does not exist: ${KEYS_SOURCE}"
      exit 1
    fi
    mkdir -p "${WORKDIR}/keys"
    rsync -a "${KEYS_SOURCE%/}/" "${WORKDIR}/keys/"
  elif [ -d "${WORKDIR}/keys/${DEVICE}" ] || [ -d "${WORKDIR}/keys" ]; then
    echo "    Using existing keys in ${WORKDIR}/keys"
  elif [ -d "${KEYS_BACKUP}" ]; then
    mkdir -p "${WORKDIR}/keys"
    rsync -a "${KEYS_BACKUP%/}/" "${WORKDIR}/keys/"
  elif [ -d "/root/keys/${DEVICE}" ]; then
    mkdir -p "${WORKDIR}/keys"
    rsync -a "/root/keys/" "${WORKDIR}/keys/"
  elif [ -d "/root/keys" ]; then
    mkdir -p "${WORKDIR}/keys"
    rsync -a "/root/keys/" "${WORKDIR}/keys/"
  elif [ -d "/home/${BUILD_USER}/keys/${DEVICE}" ]; then
    mkdir -p "${WORKDIR}/keys"
    rsync -a "/home/${BUILD_USER}/keys/" "${WORKDIR}/keys/"
  elif [ -d "/home/${BUILD_USER}/keys" ]; then
    mkdir -p "${WORKDIR}/keys"
    rsync -a "/home/${BUILD_USER}/keys/" "${WORKDIR}/keys/"
  else
    echo "WARNING: No external keys folder auto-detected yet."
    echo "         The script will continue, but signed release generation will stop if ${WORKDIR}/keys is missing."
    echo "         To specify keys manually, run: KEYS_SOURCE=/path/to/keys bash /root/wizeos.sh"
  fi
else
  echo "    SIGNED=0, skipping keys preparation and signed release generation."
fi
chown -R "${BUILD_USER}:${BUILD_USER}" "${WORKDIR}" "/home/${BUILD_USER}"

# Prepare Magisk/avbroot inputs outside the builder heredoc so prompts do not consume script stdin.
MAGISK_APK_WORKDIR=""
if [ "${ROOT}" = "magisk" ]; then
  log "Preparing Magisk/avbroot inputs"

  if ! AVBROOT_RESOLVED="$(command -v "${AVBROOT}" 2>/dev/null)"; then
    if [ -x "${AVBROOT}" ]; then
      AVBROOT_RESOLVED="${AVBROOT}"
    else
      echo "ERROR: avbroot was not found. Install it, or run with AVBROOT=/absolute/path/to/avbroot"
      exit 1
    fi
  fi
  AVBROOT="${AVBROOT_RESOLVED}"

  if [ ! -f "${MAGISK_APK}" ]; then
    echo "ERROR: MAGISK_APK does not exist: ${MAGISK_APK}"
    exit 1
  fi

  MAGISK_DIR="${WORKDIR}/magisk"
  mkdir -p "${MAGISK_DIR}"
  MAGISK_APK_WORKDIR="${MAGISK_DIR}/Magisk.apk"
  rsync -a "${MAGISK_APK}" "${MAGISK_APK_WORKDIR}"

  if [ -z "${AVBROOT_AVB_KEY}" ]; then
    AVBROOT_AVB_KEY="${WORKDIR}/keys/${DEVICE}/avb.pem"
  elif [ "${AVBROOT_AVB_KEY#/}" = "${AVBROOT_AVB_KEY}" ]; then
    AVBROOT_AVB_KEY="${WORKDIR}/${AVBROOT_AVB_KEY}"
  fi

  if [ -z "${AVBROOT_OTA_CERT}" ]; then
    AVBROOT_OTA_CERT="${WORKDIR}/keys/${DEVICE}/releasekey.x509.pem"
  elif [ "${AVBROOT_OTA_CERT#/}" = "${AVBROOT_OTA_CERT}" ]; then
    AVBROOT_OTA_CERT="${WORKDIR}/${AVBROOT_OTA_CERT}"
  fi

  if [ -z "${AVBROOT_OTA_KEY}" ]; then
    AVBROOT_OTA_KEY="${WORKDIR}/keys/${DEVICE}/ota-avbroot.key"
  elif [ "${AVBROOT_OTA_KEY#/}" = "${AVBROOT_OTA_KEY}" ]; then
    AVBROOT_OTA_KEY="${WORKDIR}/${AVBROOT_OTA_KEY}"
  fi

  if [ -n "${AVBROOT_PASS_AVB_FILE}" ] && [ "${AVBROOT_PASS_AVB_FILE#/}" = "${AVBROOT_PASS_AVB_FILE}" ]; then
    AVBROOT_PASS_AVB_FILE="${WORKDIR}/${AVBROOT_PASS_AVB_FILE}"
  fi
  if [ -n "${AVBROOT_PASS_OTA_FILE}" ] && [ "${AVBROOT_PASS_OTA_FILE#/}" = "${AVBROOT_PASS_OTA_FILE}" ]; then
    AVBROOT_PASS_OTA_FILE="${WORKDIR}/${AVBROOT_PASS_OTA_FILE}"
  fi

  RELEASEKEY_PK8="${WORKDIR}/keys/${DEVICE}/releasekey.pk8"

  if [ ! -f "${AVBROOT_AVB_KEY}" ]; then
    echo "ERROR: Missing AVB private key for avbroot: ${AVBROOT_AVB_KEY}"
    echo "       Your keys folder should normally contain keys/${DEVICE}/avb.pem."
    exit 1
  fi

  if [ ! -f "${AVBROOT_OTA_CERT}" ]; then
    echo "ERROR: Missing OTA certificate for avbroot: ${AVBROOT_OTA_CERT}"
    echo "       Your screenshot shows releasekey.x509.pem, so make sure it is under keys/${DEVICE}/."
    exit 1
  fi

  if [ ! -f "${AVBROOT_OTA_KEY}" ]; then
    if [ ! -f "${RELEASEKEY_PK8}" ]; then
      echo "ERROR: Missing releasekey.pk8 needed to create avbroot OTA key: ${RELEASEKEY_PK8}"
      exit 1
    fi

    log "Creating avbroot OTA PEM key from releasekey.pk8"
    echo "    Input : ${RELEASEKEY_PK8}"
    echo "    Output: ${AVBROOT_OTA_KEY}"
    echo "    OpenSSL may ask for the input key password and for a new output PEM password."
    mkdir -p "$(dirname "${AVBROOT_OTA_KEY}")"
    openssl pkcs8 -topk8 -scrypt -in "${RELEASEKEY_PK8}" -out "${AVBROOT_OTA_KEY}" -outform PEM
  fi

  if [ -n "${AVBROOT_PASS_AVB_FILE}" ] && [ ! -f "${AVBROOT_PASS_AVB_FILE}" ]; then
    echo "ERROR: AVBROOT_PASS_AVB_FILE does not exist: ${AVBROOT_PASS_AVB_FILE}"
    exit 1
  fi
  if [ -n "${AVBROOT_PASS_OTA_FILE}" ] && [ ! -f "${AVBROOT_PASS_OTA_FILE}" ]; then
    echo "ERROR: AVBROOT_PASS_OTA_FILE does not exist: ${AVBROOT_PASS_OTA_FILE}"
    exit 1
  fi

  chown -R "${BUILD_USER}:${BUILD_USER}" "${MAGISK_DIR}" "${WORKDIR}/keys"
  chmod 0600 "${AVBROOT_OTA_KEY}" 2>/dev/null || true
fi

cat >/home/${BUILD_USER}/.bashrc.grapheneos <<'EOS'
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
EOS
chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc.grapheneos"
if ! grep -q '.bashrc.grapheneos' "/home/${BUILD_USER}/.bashrc" 2>/dev/null; then
  echo 'source ~/.bashrc.grapheneos' >> "/home/${BUILD_USER}/.bashrc"
  chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc"
fi

log "Running GrapheneOS source sync, build, and signed release as ${BUILD_USER}, not root"
sudo -H -u "${BUILD_USER}" env \
  HOME="/home/${BUILD_USER}" \
  USER="${BUILD_USER}" \
  LOGNAME="${BUILD_USER}" \
  XDG_CONFIG_HOME="/home/${BUILD_USER}/.config" \
  XDG_CACHE_HOME="/home/${BUILD_USER}/.cache" \
  GIT_CONFIG_NOSYSTEM=1 \
  DEVICE="${DEVICE}" \
  TAG="${TAG}" \
  BUILD_NUMBER="${BUILD_NUMBER}" \
  CLEAN_OUT="${CLEAN_OUT}" \
  JOBS="${JOBS}" \
  BASE_DIR="${BASE_DIR}" \
  WORKDIR="${WORKDIR}" \
  SYNC_JOBS="${SYNC_JOBS}" \
  SIGNED="${SIGNED}" \
  ROOT="${ROOT}" \
  MAGISK_APK_WORKDIR="${MAGISK_APK_WORKDIR:-}" \
  MAGISK_PREINIT_DEVICE="${MAGISK_PREINIT_DEVICE}" \
  AVBROOT="${AVBROOT}" \
  AVBROOT_AVB_KEY="${AVBROOT_AVB_KEY:-}" \
  AVBROOT_OTA_KEY="${AVBROOT_OTA_KEY:-}" \
  AVBROOT_OTA_CERT="${AVBROOT_OTA_CERT:-}" \
  AVBROOT_PASS_AVB_FILE="${AVBROOT_PASS_AVB_FILE:-}" \
  AVBROOT_PASS_OTA_FILE="${AVBROOT_PASS_OTA_FILE:-}" \
  bash <<'BUILDER_SCRIPT'
set -eo pipefail
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
export HOME="${HOME:-/home/builder}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export GIT_CONFIG_NOSYSTEM=1

# sudo may preserve the caller's current directory (/root).
# Yarn walks upward from PWD looking for .yarnrc, so start in the builder home.
cd "$HOME"
mkdir -p "$BASE_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$HOME/.ssh"

whoami
printf 'HOME=%s\n' "$HOME"
printf 'PWD=%s\n' "$(pwd)"
node -v
yarn --version

cd "$BASE_DIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ -d .repo ]; then
  echo "==> Existing .repo found. Re-initializing manifest for tag ${TAG}."
else
  echo "==> Initializing new GrapheneOS source tree for tag ${TAG}."
fi
repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/${TAG}" --no-clone-bundle

curl -fsSL https://grapheneos.org/allowed_signers > "$HOME/.ssh/grapheneos_allowed_signers"

echo "==> Verifying GrapheneOS manifest tag"
cd .repo/manifests
git config gpg.ssh.allowedSignersFile "$HOME/.ssh/grapheneos_allowed_signers"
git verify-tag "$(git describe)"
cd ../..

echo "==> Syncing source tree"
repo sync -j"$SYNC_JOBS" --no-clone-bundle --current-branch

echo "==> Loading Android build environment"
source build/envsetup.sh

echo "==> Checking Ubuntu AppArmor user namespace setting"
if command -v sysctl >/dev/null 2>&1 && sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
  printf 'kernel.apparmor_restrict_unprivileged_userns=%s\n' "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns)"
fi

echo "==> Installing adevtool JavaScript dependencies"
yarn --cwd vendor/adevtool/ install

echo "==> Generating Pixel vendor files for ${DEVICE}"
# GrapheneOS adevtool is provided by the source tree after vendor/adevtool deps are installed.
# Do not rely on it being globally available as an `adevtool` command.
export PATH="$PWD/vendor/adevtool/bin:$PWD/vendor/adevtool/node_modules/.bin:$PATH"
if command -v adevtool >/dev/null 2>&1; then
  adevtool generate-all -d "$DEVICE"
elif [ -x "vendor/adevtool/bin/run" ]; then
  vendor/adevtool/bin/run generate-all -d "$DEVICE"
else
  echo "ERROR: adevtool was not found after Yarn install."
  echo "Checked: command adevtool and vendor/adevtool/bin/run"
  exit 1
fi

echo "==> Selecting build target ${DEVICE}-cur-user"
lunch "${DEVICE}-cur-user"

echo "==> Build target check"
echo "TARGET_PRODUCT=${TARGET_PRODUCT:-}"
echo "TARGET_RELEASE=${TARGET_RELEASE:-}"
echo "TARGET_BUILD_VARIANT=${TARGET_BUILD_VARIANT:-}"

unset BUILD_DATETIME
# finalize.sh requires BUILD_NUMBER to already be exported.
# Keep it stable across target-files, finalize, and generate-release.
export BUILD_NUMBER="${BUILD_NUMBER:-${TAG}}"
printf 'BUILD_NUMBER=%s\n' "$BUILD_NUMBER"
unset OFFICIAL_BUILD

if [ "${SIGNED}" = "1" ]; then
  echo "==> Checking existing keys folder"
  if [ ! -d "keys" ]; then
    echo "ERROR: Missing keys folder in $(pwd)/keys"
    echo "Place your existing keys folder at this path, or run root script with KEYS_SOURCE=/path/to/keys."
    exit 1
  fi
  if [ ! -d "keys/${DEVICE}" ]; then
    echo "WARNING: keys/${DEVICE} was not found."
    echo "         If your keys are directly inside keys/, generate-release.sh may fail."
    echo "         Expected common path: $(pwd)/keys/${DEVICE}"
  fi
  find keys -maxdepth 2 -type f | sed 's#^#    #g' | head -40
else
  echo "==> SIGNED=0, skipping keys check and signed release generation"
fi

if [ "${CLEAN_OUT}" = "1" ]; then
  echo "==> Cleaning old build output"
  rm -rf out
else
  echo "==> CLEAN_OUT=0, keeping existing out/ and resuming incremental build"
fi

echo "==> Starting target-files build with -j${JOBS}"
m target-files-package -j"$JOBS"

echo "==> Building OTA tools"
m otatools-package -j"$JOBS"

echo "==> Finalizing build artifacts"
script/finalize.sh

echo "==> Verifying build number"
if [ -f out/build_number.txt ]; then
  OUT_BUILD_NUMBER="$(cat out/build_number.txt)"
  printf 'out/build_number.txt=%s\n' "$OUT_BUILD_NUMBER"
  if [ "$OUT_BUILD_NUMBER" != "$BUILD_NUMBER" ]; then
    echo "WARNING: out/build_number.txt does not match BUILD_NUMBER=${BUILD_NUMBER}."
    echo "         Continuing with BUILD_NUMBER=${BUILD_NUMBER} for generate-release.sh."
  fi
else
  echo "WARNING: out/build_number.txt was not found after finalize.sh."
fi
printf 'BUILD_NUMBER=%s\n' "$BUILD_NUMBER"

if [ "${SIGNED}" = "1" ]; then
  echo "==> Generating signed release for ${DEVICE}"
  script/generate-release.sh "$DEVICE" "$BUILD_NUMBER"

  RELEASE_DIR="releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
  echo "==> Signed release finished"
  echo "Release output directory: ${RELEASE_DIR}"

  if [ "${ROOT}" = "magisk" ]; then
    echo "==> ROOT=magisk requested. Patching signed OTA with Magisk via avbroot."

    if [ ! -x "${AVBROOT}" ]; then
      echo "ERROR: avbroot is not executable: ${AVBROOT}"
      exit 1
    fi
    if [ -z "${MAGISK_APK_WORKDIR}" ] || [ ! -f "${MAGISK_APK_WORKDIR}" ]; then
      echo "ERROR: Missing copied Magisk APK: ${MAGISK_APK_WORKDIR}"
      exit 1
    fi
    if [ ! -f "${AVBROOT_AVB_KEY}" ]; then
      echo "ERROR: Missing avbroot AVB key: ${AVBROOT_AVB_KEY}"
      exit 1
    fi
    if [ ! -f "${AVBROOT_OTA_KEY}" ]; then
      echo "ERROR: Missing avbroot OTA key: ${AVBROOT_OTA_KEY}"
      exit 1
    fi
    if [ ! -f "${AVBROOT_OTA_CERT}" ]; then
      echo "ERROR: Missing avbroot OTA certificate: ${AVBROOT_OTA_CERT}"
      exit 1
    fi

    OTA_ZIP="$(find "${RELEASE_DIR}" -maxdepth 1 -type f -name "*ota_update*.zip" | sort | head -n 1)"
    if [ -z "${OTA_ZIP}" ]; then
      echo "ERROR: Could not find OTA zip in ${RELEASE_DIR}"
      find "${RELEASE_DIR}" -maxdepth 1 -type f | sed 's#^#    #g' || true
      exit 1
    fi

    ROOTED_OTA="${OTA_ZIP%.zip}-magisk.zip"
    AVBROOT_ARGS=(
      ota patch
      --input "${OTA_ZIP}"
      --output "${ROOTED_OTA}"
      --key-avb "${AVBROOT_AVB_KEY}"
      --key-ota "${AVBROOT_OTA_KEY}"
      --cert-ota "${AVBROOT_OTA_CERT}"
      --magisk "${MAGISK_APK_WORKDIR}"
      --magisk-preinit-device "${MAGISK_PREINIT_DEVICE}"
    )

    if [ -n "${AVBROOT_PASS_AVB_FILE}" ]; then
      AVBROOT_ARGS+=(--pass-avb-file "${AVBROOT_PASS_AVB_FILE}")
    fi
    if [ -n "${AVBROOT_PASS_OTA_FILE}" ]; then
      AVBROOT_ARGS+=(--pass-ota-file "${AVBROOT_PASS_OTA_FILE}")
    fi

    "${AVBROOT}" "${AVBROOT_ARGS[@]}"

    echo "==> Magisk-patched OTA finished"
    echo "Rooted OTA: ${ROOTED_OTA}"
  else
    echo "==> ROOT=none, leaving signed release unrooted"
  fi
else
  echo "==> SIGNED=0, signed release generation skipped"
fi
BUILDER_SCRIPT

if [ "${SIGNED}" = "1" ]; then
  if [ "${ROOT}" = "magisk" ]; then
    log "Build, signed release, and Magisk OTA patch finished"
  else
    log "Build and signed release finished"
  fi
  echo "Build directory: ${WORKDIR}"
  echo "Signed release directory will be under: ${WORKDIR}/releases/"
else
  log "Build finished without signed release"
  echo "Build directory: ${WORKDIR}"
  echo "Build output directory is under: ${WORKDIR}/out/"
fi
