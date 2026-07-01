#!/usr/bin/env bash
# Upload WizeOS / GrapheneOS release files to FTP.
#
# Behavior:
#   1. Detects the currently published build from /download/mustang/mustang-stable.
#   2. Moves the old remote folder to /download/mustang-OLD_TAG.
#      Example: /download/mustang -> /download/mustang-2026061800
#   3. Uploads the new release to /download/mustang.
#
# Usage:
#   FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable ./upload.sh
#
# Optional:
#   OLD_TAG=2026061800 ./upload.sh
#   ARCHIVE_OLD=0 ./upload.sh
#   UPLOAD_MAGISK=0 ./upload.sh

set -euo pipefail

DEVICE="${DEVICE:-mustang}"
TAG="${TAG:-2026062800}"
BUILD_NUMBER="${BUILD_NUMBER:-${TAG}}"
CHANNEL="${CHANNEL:-stable}"

FTP_HOST="${FTP_HOST:-ftp.wizesoft.me}"
FTP_USER="${FTP_USER:-github@wizesoft.me}"
FTP_PASSWORD="${FTP_PASSWORD:-}"

FTP_BASE_DIR="${FTP_BASE_DIR:-/download}"
FTP_REMOTE_DIR="${FTP_REMOTE_DIR:-${FTP_BASE_DIR}/${DEVICE}}"

# OLD_TAG=auto reads the current remote channel file and uses its first field.
OLD_TAG="${OLD_TAG:-auto}"
ARCHIVE_OLD="${ARCHIVE_OLD:-1}"

# Default to plain FTP because this host may present a TLS certificate
# that does not match ftp.wizesoft.me.
FTP_TLS="${FTP_TLS:-0}"
FTP_SSL_VERIFY="${FTP_SSL_VERIFY:-1}"

WORKDIR="${WORKDIR:-/home/builder/android/grapheneos-${TAG}}"
RELEASE_DIR="${RELEASE_DIR:-${WORKDIR}/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}}"

UPLOAD_MAGISK="${UPLOAD_MAGISK:-1}"

if [ ! -d "${RELEASE_DIR}" ]; then
  echo "ERROR: Release directory not found:"
  echo "  ${RELEASE_DIR}"
  exit 1
fi

if [ -z "${FTP_PASSWORD}" ]; then
  echo "ERROR: FTP_PASSWORD is empty."
  echo "Run:"
  echo "  FTP_PASSWORD='your-password' TAG=${TAG} ./upload.sh"
  exit 1
fi

if ! command -v lftp >/dev/null 2>&1; then
  echo "ERROR: lftp is not installed."
  echo "Install it with:"
  echo "  apt-get update && apt-get install -y lftp"
  exit 1
fi

case "${FTP_REMOTE_DIR}" in
  "${FTP_BASE_DIR}/${DEVICE}"|"${FTP_BASE_DIR}/${DEVICE}/") ;;
  *)
    echo "ERROR: Refusing to update unexpected remote directory:"
    echo "  ${FTP_REMOTE_DIR}"
    echo "Expected:"
    echo "  ${FTP_BASE_DIR}/${DEVICE}"
    exit 1
    ;;
esac

LFTP_TLS_CMDS="set ftp:ssl-allow false"
if [ "${FTP_TLS}" = "1" ]; then
  LFTP_TLS_CMDS="set ftp:ssl-allow true
set ftp:ssl-force true"
  if [ "${FTP_SSL_VERIFY}" = "0" ]; then
    LFTP_TLS_CMDS="${LFTP_TLS_CMDS}
set ssl:verify-certificate no"
  fi
fi

lftp_cmd() {
  lftp -u "${FTP_USER},${FTP_PASSWORD}" "ftp://${FTP_HOST}"
}

remote_exists() {
  local path="$1"
  lftp_cmd >/dev/null 2>&1 <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 1
set net:timeout 15
cls -1 ${path}
bye
LFTP_CMDS
}

echo "==> Upload configuration"
echo "    Device      : ${DEVICE}"
echo "    Build number: ${BUILD_NUMBER}"
echo "    Channel     : ${CHANNEL}"
echo "    Release dir : ${RELEASE_DIR}"
echo "    FTP host    : ${FTP_HOST}"
echo "    FTP user    : ${FTP_USER}"
echo "    Remote dir  : ${FTP_REMOTE_DIR}"
echo "    FTP TLS     : ${FTP_TLS}"
echo "    Archive old : ${ARCHIVE_OLD}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

UPLOAD_DIR="${TMP_DIR}/upload"
mkdir -p "${UPLOAD_DIR}"

echo "==> Collecting release files"

# Upload public release ZIPs and signature files only.
# Do not copy old channel files from RELEASE_DIR; this script generates the selected channel file.
find "${RELEASE_DIR}" -maxdepth 1 -type f \( \
    -name "${DEVICE}-factory-${BUILD_NUMBER}.zip" -o \
    -name "${DEVICE}-factory-${BUILD_NUMBER}.zip.sig" -o \
    -name "${DEVICE}-img-${BUILD_NUMBER}.zip" -o \
    -name "${DEVICE}-img-${BUILD_NUMBER}.zip.sig" -o \
    -name "${DEVICE}-install-${BUILD_NUMBER}.zip" -o \
    -name "${DEVICE}-install-${BUILD_NUMBER}.zip.sig" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}.zip" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}.zip.sig" -o \
    -name "${DEVICE}-target_files.zip" -o \
    -name "${DEVICE}-target_files.zip.sig" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-magisk.zip" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-magisk.zip.sig" \
  \) -exec cp -a {} "${UPLOAD_DIR}/" \;

if [ "${UPLOAD_MAGISK}" = "0" ]; then
  find "${UPLOAD_DIR}" -maxdepth 1 -type f -name '*-magisk.zip*' -delete
fi

OTA_ZIP="${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"
if [ ! -f "${OTA_ZIP}" ]; then
  echo "ERROR: Expected OTA zip not found:"
  echo "  ${OTA_ZIP}"
  echo "Files copied:"
  find "${UPLOAD_DIR}" -maxdepth 1 -type f -printf '  %f\n' | sort
  exit 1
fi

OTA_SIZE="$(stat -c '%s' "${OTA_ZIP}")"
CHANNEL_FILE="${UPLOAD_DIR}/${DEVICE}-${CHANNEL}"

# GrapheneOS-style channel line:
#   <build_number> <ota_size_bytes> <device> <channel>
printf '%s %s %s %s\n' "${BUILD_NUMBER}" "${OTA_SIZE}" "${DEVICE}" "${CHANNEL}" > "${CHANNEL_FILE}"

echo "==> Local upload set"
find "${UPLOAD_DIR}" -maxdepth 1 -type f -printf '    %f\n' | sort

if [ "${ARCHIVE_OLD}" = "1" ]; then
  DETECTED_OLD_TAG=""

  if [ "${OLD_TAG}" = "auto" ]; then
    echo "==> Detecting current remote build from ${FTP_REMOTE_DIR}/${DEVICE}-${CHANNEL}"
    CHANNEL_TEXT="$(lftp_cmd 2>/dev/null <<LFTP_CMDS || true
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 1
set net:timeout 15
set cmd:fail-exit false
cat ${FTP_REMOTE_DIR}/${DEVICE}-${CHANNEL}
bye
LFTP_CMDS
)"
    DETECTED_OLD_TAG="$(printf '%s\n' "${CHANNEL_TEXT}" | awk '/^[0-9]+[[:space:]]/{print $1; exit}')"

    if [ -n "${DETECTED_OLD_TAG}" ]; then
      OLD_TAG="${DETECTED_OLD_TAG}"
      echo "    Detected old tag: ${OLD_TAG}"
    else
      OLD_TAG="$(date +%Y%m%d%H%M%S)"
      echo "    Could not detect old tag. Using timestamp: ${OLD_TAG}"
    fi
  fi

  ARCHIVE_REMOTE_DIR="${FTP_BASE_DIR}/${DEVICE}-${OLD_TAG}"

  if [ "${OLD_TAG}" = "${BUILD_NUMBER}" ]; then
    ARCHIVE_REMOTE_DIR="${FTP_BASE_DIR}/${DEVICE}-${OLD_TAG}-old-$(date +%Y%m%d%H%M%S)"
    echo "    Old tag equals new build number, using archive dir: ${ARCHIVE_REMOTE_DIR}"
  fi

  if remote_exists "${ARCHIVE_REMOTE_DIR}"; then
    ARCHIVE_REMOTE_DIR="${FTP_BASE_DIR}/${DEVICE}-${OLD_TAG}-old-$(date +%Y%m%d%H%M%S)"
    echo "    Archive folder already exists. Using: ${ARCHIVE_REMOTE_DIR}"
  fi

  echo "==> Archiving current remote folder"
  echo "    From: ${FTP_REMOTE_DIR}"
  echo "    To  : ${ARCHIVE_REMOTE_DIR}"

  # If the current folder does not exist yet, mv is non-fatal.
  lftp_cmd <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 3
set net:timeout 30
set cmd:fail-exit false
mv ${FTP_REMOTE_DIR} ${ARCHIVE_REMOTE_DIR}
set cmd:fail-exit true
mkdir -p ${FTP_REMOTE_DIR}
bye
LFTP_CMDS
else
  echo "==> ARCHIVE_OLD=0, not moving existing remote folder"
fi

echo "==> Uploading new release to ftp://${FTP_HOST}${FTP_REMOTE_DIR}"

lftp_cmd <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 3
set net:timeout 30

# Some FTP servers return 550 "File exists" for mkdir -p, so keep it non-fatal.
set cmd:fail-exit false
mkdir -p ${FTP_REMOTE_DIR}
set cmd:fail-exit true

mirror --reverse --delete --verbose --parallel=2 ${UPLOAD_DIR} ${FTP_REMOTE_DIR}
bye
LFTP_CMDS

echo "==> Upload finished"
echo "    Current release: ftp://${FTP_HOST}${FTP_REMOTE_DIR}/"
if [ "${ARCHIVE_OLD}" = "1" ]; then
  echo "    Old release    : ftp://${FTP_HOST}${ARCHIVE_REMOTE_DIR}/"
fi
echo "    Channel file   : ${DEVICE}-${CHANNEL}"
