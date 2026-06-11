#!/usr/bin/env bash
# WizeOS / LineageOS build + signed-release script for Pixel 10 Pro XL (mustang)
# Ubuntu Server 24.04 LTS
# Run as root: bash wizeos.sh

set -eo pipefail

# Absolute directory containing this script. Used to auto-detect ./keys next to wizeos.sh.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

DEVICE="${DEVICE:-mustang}"
LINEAGE_BRANCH="${LINEAGE_BRANCH:-lineage-23.2}"
BUILD_ID="${BUILD_ID:-wisso}"
JOBS="${JOBS:-24}"
BUILD_USER="${BUILD_USER:-builder}"
BASE_DIR="${BASE_DIR:-/home/${BUILD_USER}/android}"
WORKDIR="${BASE_DIR}/lineageos-${BUILD_ID}"
SYNC_JOBS="${SYNC_JOBS:-8}"
# Extra repo sync repair flags. Override with REPO_SYNC_EXTRA_FLAGS="" only by editing the script.
REPO_SYNC_EXTRA_FLAGS="${REPO_SYNC_EXTRA_FLAGS:---force-sync --force-checkout}"
# Keep START_OVER=0 because you said you already have a keys folder.
# If you set START_OVER=1, the script will back up keys before deleting the tree.
START_OVER="${START_OVER:-0}"
# Optional override. By default, the script first looks for a keys/ folder next to this script.
KEYS_SOURCE="${KEYS_SOURCE:-}"

# WizeOS / GmsCompat integration.
# Set PATCH=0 to build vanilla LineageOS without GrapheneOS GmsCompat projects or WizeOS patches.
PATCH="${PATCH:-1}"
WIZE_PATCH_REPO="${WIZE_PATCH_REPO:-https://github.com/wizdom13/WizeOS.git}"
WIZE_PATCH_REF="${WIZE_PATCH_REF:-main}"
WIZE_PATCH_DIR="${WIZE_PATCH_DIR:-${BASE_DIR}/WizeOS-patches}"
GMSCOMPAT_REVISION="${GMSCOMPAT_REVISION:-16-qpr2}"
# Useful for first validation: STOP_AFTER_PATCHES=1 bash wizeos.sh
STOP_AFTER_PATCHES="${STOP_AFTER_PATCHES:-0}"
# Keep clean rebuild as default, but allow CLEAN_OUT=0 for incremental rebuilds.
CLEAN_OUT="${CLEAN_OUT:-1}"

if [ "${PATCH}" != "0" ] && [ "${PATCH}" != "1" ]; then
  echo "ERROR: PATCH must be 0 or 1. Current value: ${PATCH}"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this setup script as root. It will run LineageOS build steps as ${BUILD_USER}."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log() {
  echo "==> $*"
}

log "LineageOS build setup"
echo "    Device: ${DEVICE}"
echo "    Build ID: ${BUILD_ID}"
echo "    Lineage branch: ${LINEAGE_BRANCH}"
echo "    Sync jobs: ${SYNC_JOBS}"
echo "    Repo sync extra flags: ${REPO_SYNC_EXTRA_FLAGS}"
echo "    Jobs: ${JOBS}"
echo "    Build user: ${BUILD_USER}"
echo "    Workdir: ${WORKDIR}"
echo "    Script dir: ${SCRIPT_DIR}"
echo "    Start over: ${START_OVER}"
echo "    Keys source: ${KEYS_SOURCE:-auto-detect}"
echo "    Patch WizeOS/GmsCompat: ${PATCH}"
echo "    Wize patch repo: ${WIZE_PATCH_REPO}"
echo "    Wize patch ref: ${WIZE_PATCH_REF}"
echo "    Wize patch dir: ${WIZE_PATCH_DIR}"
echo "    GmsCompat revision: ${GMSCOMPAT_REVISION}"
echo "    Stop after patches: ${STOP_AFTER_PATCHES}"
echo "    Clean out: ${CLEAN_OUT}"

log "Allowing nsjail to use unprivileged user namespaces on Ubuntu 24.04"
# Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor.
# Android/Soong nsjail needs this for sandboxed build steps used by adevtool.
# This is intended for a dedicated build host.
if sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
  sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
  cat >/etc/sysctl.d/99-lineageos-build.conf <<'SYSCTL_EOF'
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
  git-lfs \
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

log "Initializing Git LFS"
git lfs install --system

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

  log "Removing old LineageOS tree for a clean source/build output"
  rm -rf "${WORKDIR}"
  rm -rf "/root/android/lineageos-${BUILD_ID}"
fi

# If an old root-owned tree exists and the builder tree does not, move it instead of copying.
# This saves disk space on 450 GB servers.
if [ -d "/root/android/lineageos-${BUILD_ID}" ] && [ ! -d "${WORKDIR}" ]; then
  log "Moving existing /root/android/lineageos-${BUILD_ID} to ${WORKDIR}"
  mkdir -p "${BASE_DIR}"
  mv "/root/android/lineageos-${BUILD_ID}" "${WORKDIR}"
  chown -R "${BUILD_USER}:${BUILD_USER}" "${WORKDIR}"
fi

# Auto-detect an existing keys folder and place it in the source tree.
# LineageOS generate-release.sh expects keys under the source tree, normally keys/${DEVICE}/.
log "Preparing existing keys folder"
mkdir -p "${WORKDIR}"

copy_keys_into_workdir() {
  local src="$1"
  local label="$2"

  if [ ! -d "$src" ]; then
    echo "ERROR: ${label} does not exist: ${src}"
    exit 1
  fi

  echo "    Copying keys from ${src} to ${WORKDIR}/keys"
  mkdir -p "${WORKDIR}/keys"
  rsync -a --delete "${src%/}/" "${WORKDIR}/keys/"
}

if [ -n "${KEYS_SOURCE}" ]; then
  copy_keys_into_workdir "${KEYS_SOURCE}" "KEYS_SOURCE"
elif [ -d "${SCRIPT_DIR}/keys/${DEVICE}" ] || [ -d "${SCRIPT_DIR}/keys" ]; then
  copy_keys_into_workdir "${SCRIPT_DIR}/keys" "script-local keys folder"
elif [ -d "${WORKDIR}/keys/${DEVICE}" ] || [ -d "${WORKDIR}/keys" ]; then
  echo "    Using existing keys in ${WORKDIR}/keys"
elif [ -d "${KEYS_BACKUP}" ]; then
  copy_keys_into_workdir "${KEYS_BACKUP}" "keys backup"
elif [ -d "/root/keys/${DEVICE}" ] || [ -d "/root/keys" ]; then
  copy_keys_into_workdir "/root/keys" "/root/keys"
elif [ -d "/home/${BUILD_USER}/keys/${DEVICE}" ] || [ -d "/home/${BUILD_USER}/keys" ]; then
  copy_keys_into_workdir "/home/${BUILD_USER}/keys" "/home/${BUILD_USER}/keys"
else
  echo "WARNING: No keys folder auto-detected yet."
  echo "         Put your keys folder next to this script: ${SCRIPT_DIR}/keys"
  echo "         The script will continue, but signed release generation will stop if ${WORKDIR}/keys is missing."
  echo "         Or specify keys manually: KEYS_SOURCE=/path/to/keys bash ${BASH_SOURCE[0]}"
fi
chown -R "${BUILD_USER}:${BUILD_USER}" "${WORKDIR}" "/home/${BUILD_USER}"

cat >/home/${BUILD_USER}/.bashrc.lineageos <<'EOS'
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
EOS
chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc.lineageos"
if ! grep -q '.bashrc.lineageos' "/home/${BUILD_USER}/.bashrc" 2>/dev/null; then
  echo 'source ~/.bashrc.lineageos' >> "/home/${BUILD_USER}/.bashrc"
  chown "${BUILD_USER}:${BUILD_USER}" "/home/${BUILD_USER}/.bashrc"
fi

log "Running source sync, WizeOS/GmsCompat patching, build, and signed release as ${BUILD_USER}, not root"
sudo -H -u "${BUILD_USER}" env \
  HOME="/home/${BUILD_USER}" \
  USER="${BUILD_USER}" \
  LOGNAME="${BUILD_USER}" \
  XDG_CONFIG_HOME="/home/${BUILD_USER}/.config" \
  XDG_CACHE_HOME="/home/${BUILD_USER}/.cache" \
  GIT_CONFIG_NOSYSTEM=1 \
  DEVICE="${DEVICE}" \
  BUILD_ID="${BUILD_ID}" \
  LINEAGE_BRANCH="${LINEAGE_BRANCH}" \
  JOBS="${JOBS}" \
  BASE_DIR="${BASE_DIR}" \
  WORKDIR="${WORKDIR}" \
  SYNC_JOBS="${SYNC_JOBS}" \
  REPO_SYNC_EXTRA_FLAGS="${REPO_SYNC_EXTRA_FLAGS}" \
  PATCH="${PATCH}" \
  WIZE_PATCH_REPO="${WIZE_PATCH_REPO}" \
  WIZE_PATCH_REF="${WIZE_PATCH_REF}" \
  WIZE_PATCH_DIR="${WIZE_PATCH_DIR}" \
  GMSCOMPAT_REVISION="${GMSCOMPAT_REVISION}" \
  STOP_AFTER_PATCHES="${STOP_AFTER_PATCHES}" \
  CLEAN_OUT="${CLEAN_OUT}" \
  bash <<'BUILDER_SCRIPT'
set -eo pipefail
export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
export HOME="${HOME:-/home/builder}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export GIT_CONFIG_NOSYSTEM=1

if [ "${PATCH}" != "0" ] && [ "${PATCH}" != "1" ]; then
  echo "ERROR: PATCH must be 0 or 1. Current value: ${PATCH}"
  exit 1
fi

# sudo may preserve the caller's current directory (/root).
# Yarn walks upward from PWD looking for .yarnrc, so start in the builder home.
cd "$HOME"
mkdir -p "$BASE_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$HOME/.ssh"

whoami
printf 'HOME=%s\n' "$HOME"
printf 'PWD=%s\n' "$(pwd)"
printf 'LINEAGE_BRANCH=%s\n' "${LINEAGE_BRANCH}"
printf 'BUILD_ID=%s\n' "${BUILD_ID}"
printf 'SYNC_JOBS=%s\n' "${SYNC_JOBS}"
printf 'REPO_SYNC_EXTRA_FLAGS=%s\n' "${REPO_SYNC_EXTRA_FLAGS}"
node -v
yarn --version
git lfs version
git lfs install --skip-smudge

cd "$BASE_DIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ -d .repo ]; then
  echo "==> Existing .repo found. Re-initializing manifest for branch ${LINEAGE_BRANCH}."
else
  echo "==> Initializing new LineageOS source tree for branch ${LINEAGE_BRANCH}."
fi
repo init -u https://github.com/LineageOS/android.git -b "${LINEAGE_BRANCH}" --no-clone-bundle

if [ "${PATCH}" = "1" ]; then
  echo "==> Adding GrapheneOS GmsCompat local manifest (${GMSCOMPAT_REVISION})"
  mkdir -p .repo/local_manifests
  cat > .repo/local_manifests/wizeos-gmscompat.xml <<MANIFEST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="grapheneos" fetch="https://github.com/GrapheneOS/" />
  <project path="packages/apps/GmsCompat" name="platform_packages_apps_GmsCompat" remote="grapheneos" revision="${GMSCOMPAT_REVISION}" />
  <project path="external/GmsCompatConfig" name="platform_external_GmsCompatConfig" remote="grapheneos" revision="${GMSCOMPAT_REVISION}" />
</manifest>
MANIFEST_EOF
else
  echo "==> PATCH=0; skipping GrapheneOS GmsCompat local manifest"
  rm -f .repo/local_manifests/wizeos-gmscompat.xml
fi

echo "==> Verifying LineageOS manifest ref"
cd .repo/manifests

# repo may create a local branch named "default" even when initialized with
# -b lineage-23.2. Validate the fetched upstream ref instead of the local
# branch name.
if git rev-parse --verify --quiet "refs/remotes/origin/${LINEAGE_BRANCH}" >/dev/null; then
  MANIFEST_COMMIT="$(git rev-parse HEAD)"
  EXPECTED_COMMIT="$(git rev-parse "refs/remotes/origin/${LINEAGE_BRANCH}")"
  printf 'Manifest upstream ref=origin/%s\n' "$LINEAGE_BRANCH"
  printf 'Manifest HEAD=%s\n' "$MANIFEST_COMMIT"
  printf 'Manifest expected=%s\n' "$EXPECTED_COMMIT"
elif git rev-parse --verify --quiet "${LINEAGE_BRANCH}^{commit}" >/dev/null; then
  MANIFEST_COMMIT="$(git rev-parse HEAD)"
  EXPECTED_COMMIT="$(git rev-parse "${LINEAGE_BRANCH}^{commit}")"
  printf 'Manifest ref=%s\n' "$LINEAGE_BRANCH"
  printf 'Manifest HEAD=%s\n' "$MANIFEST_COMMIT"
  printf 'Manifest expected=%s\n' "$EXPECTED_COMMIT"
else
  echo "ERROR: Could not verify manifest ref: ${LINEAGE_BRANCH}"
  echo "Available manifest refs:"
  git for-each-ref --format='  %(refname:short)' refs/remotes/origin refs/tags | sort | head -80
  exit 1
fi

if [ "$MANIFEST_COMMIT" != "$EXPECTED_COMMIT" ]; then
  echo "ERROR: Manifest HEAD mismatch for ${LINEAGE_BRANCH}"
  exit 1
fi

cd ../..

echo "==> Syncing source tree"
repo sync -j"$SYNC_JOBS" --no-clone-bundle --current-branch ${REPO_SYNC_EXTRA_FLAGS}

apply_patch_dir() {
  local project_dir="$1"
  local patch_dir="$2"
  local label="$3"

  if [ ! -d "$project_dir/.git" ]; then
    echo "ERROR: Missing git project for ${label}: ${project_dir}"
    exit 1
  fi
  if [ ! -d "$patch_dir" ]; then
    echo "ERROR: Missing patch directory for ${label}: ${patch_dir}"
    exit 1
  fi

  shopt -s nullglob
  local patches=("$patch_dir"/*.patch)
  shopt -u nullglob

  if [ "${#patches[@]}" -eq 0 ]; then
    echo "ERROR: No patch files found for ${label}: ${patch_dir}"
    exit 1
  fi

  echo "==> Applying ${label} patches"
  local patch_file
  for patch_file in "${patches[@]}"; do
    echo "    $(basename "$patch_file")"
    if git -C "$project_dir" apply --check "$patch_file"; then
      git -C "$project_dir" apply --whitespace=fix "$patch_file"
    elif git -C "$project_dir" apply -R --check "$patch_file"; then
      echo "    already applied; skipping"
    else
      echo "ERROR: Patch does not apply cleanly: ${patch_file}"
      echo "Project: ${project_dir}"
      git -C "$project_dir" status --short || true
      exit 1
    fi
  done
}

if [ "${PATCH}" = "1" ]; then
  echo "==> Fetching WizeOS GmsCompat patch queue"
  if [ -d "${WIZE_PATCH_DIR}/.git" ]; then
    git -C "${WIZE_PATCH_DIR}" fetch origin "${WIZE_PATCH_REF}" --prune
  else
    rm -rf "${WIZE_PATCH_DIR}"
    git clone "${WIZE_PATCH_REPO}" "${WIZE_PATCH_DIR}"
    git -C "${WIZE_PATCH_DIR}" fetch origin "${WIZE_PATCH_REF}" --prune
  fi
  git -C "${WIZE_PATCH_DIR}" checkout -f FETCH_HEAD

  PATCH_ROOT="${WIZE_PATCH_DIR}/patches/gmscompat-lineage-23.2"
  if [ ! -d "${PATCH_ROOT}" ]; then
    echo "ERROR: Missing WizeOS GmsCompat patch root: ${PATCH_ROOT}"
    exit 1
  fi

  echo "==> Active WizeOS GmsCompat patches"
  find "${PATCH_ROOT}" -type f -name "*.patch" ! -path "*/disabled/*" -print | sort

  apply_patch_dir "bionic" "${PATCH_ROOT}/bionic" "bionic"
  apply_patch_dir "libcore" "${PATCH_ROOT}/libcore" "libcore"
  apply_patch_dir "frameworks/base" "${PATCH_ROOT}/frameworks-base" "frameworks/base"

  if [ "${STOP_AFTER_PATCHES}" = "1" ]; then
    echo "==> STOP_AFTER_PATCHES=1 requested; stopping before build."
    exit 0
  fi
else
  echo "==> PATCH=0; skipping WizeOS GmsCompat patch queue"
fi

echo "==> Loading Android build environment"
source build/envsetup.sh

echo "==> Checking Ubuntu AppArmor user namespace setting"
if command -v sysctl >/dev/null 2>&1 && sysctl -n kernel.apparmor_restrict_unprivileged_userns >/dev/null 2>&1; then
  printf 'kernel.apparmor_restrict_unprivileged_userns=%s\n' "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns)"
fi

echo "==> Installing adevtool JavaScript dependencies"
yarn --cwd vendor/adevtool/ install

echo "==> Generating Pixel vendor files for ${DEVICE}"
# LineageOS adevtool is provided by the source tree after vendor/adevtool deps are installed.
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
unset BUILD_NUMBER
unset OFFICIAL_BUILD

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

if [ "${CLEAN_OUT}" = "1" ]; then
  echo "==> Cleaning old build output"
  rm -rf out
else
  echo "==> CLEAN_OUT=0; keeping existing out directory for incremental build"
fi

echo "==> Starting target-files build with -j${JOBS}"
m target-files-package -j"$JOBS"

echo "==> Building OTA tools"
m otatools-package -j"$JOBS"

echo "==> Finalizing build artifacts"
script/finalize.sh

echo "==> Reading build number"
export BUILD_NUMBER="$(cat out/build_number.txt)"
printf 'BUILD_NUMBER=%s\n' "$BUILD_NUMBER"

echo "==> Generating signed release for ${DEVICE}"
script/generate-release.sh "$DEVICE" "$BUILD_NUMBER"

echo "==> Signed release finished"
echo "Release output directory: releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}"
BUILDER_SCRIPT

log "Build and signed release finished"
echo "Build directory: ${WORKDIR}"
echo "Signed release directory will be under: ${WORKDIR}/releases/"
