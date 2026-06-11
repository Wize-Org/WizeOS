#!/usr/bin/env bash
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

OLD_TAG="${OLD_TAG:-auto}"
ARCHIVE_OLD="${ARCHIVE_OLD:-1}"
FTP_TLS="${FTP_TLS:-0}"
FTP_SSL_VERIFY="${FTP_SSL_VERIFY:-1}"

BUILD_USER="${BUILD_USER:-builder}"
WORKDIR="${WORKDIR:-/home/${BUILD_USER}/android/grapheneos-${TAG}}"
RELEASE_DIR="${RELEASE_DIR:-${WORKDIR}/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}}"

UPLOAD_MAGISK="${UPLOAD_MAGISK:-1}"
UPLOAD_KSU="${UPLOAD_KSU:-1}"
UPLOAD_KSUNEXT="${UPLOAD_KSUNEXT:-${UPLOAD_KSU}}"
PUBLISH_MAGISK_AS_NORMAL="${PUBLISH_MAGISK_AS_NORMAL:-0}"
PUBLISH_ROOT_AS_NORMAL="${PUBLISH_ROOT_AS_NORMAL:-}"

if [ -z "${PUBLISH_ROOT_AS_NORMAL}" ] && [ "${PUBLISH_MAGISK_AS_NORMAL}" = "1" ]; then
  PUBLISH_ROOT_AS_NORMAL="magisk"
fi

[ -d "${RELEASE_DIR}" ] || { echo "ERROR: Release directory not found: ${RELEASE_DIR}"; exit 1; }
[ -n "${FTP_PASSWORD}" ] || { echo "ERROR: FTP_PASSWORD is empty"; exit 1; }
command -v lftp >/dev/null || { echo "ERROR: lftp is not installed"; exit 1; }

case "${FTP_REMOTE_DIR}" in
  "${FTP_BASE_DIR}/${DEVICE}"|"${FTP_BASE_DIR}/${DEVICE}/") ;;
  *) echo "ERROR: Refusing to update unexpected remote directory: ${FTP_REMOTE_DIR}"; exit 1 ;;
esac

case "${PUBLISH_ROOT_AS_NORMAL}" in
  ""|none|magisk|ksunext|ksunext-susfs) ;;
  *) echo "ERROR: PUBLISH_ROOT_AS_NORMAL must be empty, none, magisk, ksunext, or ksunext-susfs"; exit 1 ;;
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

lftp_cmd() { lftp -u "${FTP_USER},${FTP_PASSWORD}" "ftp://${FTP_HOST}"; }

remote_exists() {
  local path="$1"
  lftp_cmd >/dev/null 2>&1 <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 1
set net:timeout 15
set cmd:fail-exit true
cls -1 ${path}
bye
LFTP_CMDS
}

read_old_tag_from_channel() {
  local output old
  output="$(lftp_cmd 2>/dev/null <<LFTP_CMDS || true
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 1
set net:timeout 15
set cmd:fail-exit false
cat ${FTP_REMOTE_DIR}/${DEVICE}-${CHANNEL}
bye
LFTP_CMDS
)"
  old="$(printf '%s\n' "${output}" | awk '/^[0-9]+[[:space:]]/{print $1; exit}')"
  printf '%s' "${old}"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
UPLOAD_DIR="${TMP_DIR}/upload"
mkdir -p "${UPLOAD_DIR}"

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
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-magisk.zip.sig" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-ksunext.zip" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-ksunext.zip.sig" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-ksunext-susfs.zip" -o \
    -name "${DEVICE}-ota_update-${BUILD_NUMBER}-ksunext-susfs.zip.sig" -o \
    -name "KernelSU_Next.apk" -o \
    -name "Zygisk-Next.zip" -o \
    -name "susfs4ksu.zip" \
  \) -exec cp -a {} "${UPLOAD_DIR}/" \;

case "${PUBLISH_ROOT_AS_NORMAL}" in
  magisk)
    ROOT_OTA="${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}-magisk.zip"
    [ -f "${ROOT_OTA}" ] || { echo "ERROR: Magisk OTA not found: ${ROOT_OTA}"; exit 1; }
    cp -a "${ROOT_OTA}" "${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"
    ;;
  ksunext|ksunext-susfs)
    ROOT_OTA="${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}-${PUBLISH_ROOT_AS_NORMAL}.zip"
    [ -f "${ROOT_OTA}" ] || { echo "ERROR: ${PUBLISH_ROOT_AS_NORMAL} OTA not found: ${ROOT_OTA}"; exit 1; }
    cp -a "${ROOT_OTA}" "${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"
    ;;
esac

if [ "${UPLOAD_MAGISK}" = "0" ]; then
  find "${UPLOAD_DIR}" -maxdepth 1 -type f -name '*-magisk.zip*' -delete
fi
if [ "${UPLOAD_KSU}" = "0" ]; then
  find "${UPLOAD_DIR}" -maxdepth 1 -type f \( -name '*-ksunext*.zip*' -o -name 'KernelSU_Next.apk' -o -name 'Zygisk-Next.zip' -o -name 'susfs4ksu.zip' \) -delete
fi

OTA_ZIP="${UPLOAD_DIR}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"
[ -f "${OTA_ZIP}" ] || { echo "ERROR: OTA not found: ${OTA_ZIP}"; exit 1; }
printf '%s %s %s %s\n' "${BUILD_NUMBER}" "$(stat -c '%s' "${OTA_ZIP}")" "${DEVICE}" "${CHANNEL}" > "${UPLOAD_DIR}/${DEVICE}-${CHANNEL}"

echo "==> Upload configuration"
echo "    Device                  : ${DEVICE}"
echo "    Build number            : ${BUILD_NUMBER}"
echo "    Channel                 : ${CHANNEL}"
echo "    Release dir             : ${RELEASE_DIR}"
echo "    Remote dir              : ${FTP_REMOTE_DIR}"
echo "    Archive old             : ${ARCHIVE_OLD}"
echo "    Publish root as normal  : ${PUBLISH_ROOT_AS_NORMAL:-none}"

echo "==> Local upload set"
find "${UPLOAD_DIR}" -maxdepth 1 -type f -printf '    %f\n' | sort

if [ "${ARCHIVE_OLD}" = "1" ]; then
  if [ "${OLD_TAG}" = "auto" ]; then
    OLD_TAG="$(read_old_tag_from_channel)"
    OLD_TAG="${OLD_TAG:-$(date +%Y%m%d%H%M%S)}"
  fi
  ARCHIVE_REMOTE_DIR="${FTP_BASE_DIR}/${DEVICE}-${OLD_TAG}"
  if [ "${OLD_TAG}" = "${BUILD_NUMBER}" ] || remote_exists "${ARCHIVE_REMOTE_DIR}"; then
    ARCHIVE_REMOTE_DIR="${FTP_BASE_DIR}/${DEVICE}-${OLD_TAG}-old-$(date +%Y%m%d%H%M%S)"
  fi
  echo "==> Archiving current remote folder"
  echo "    From: ${FTP_REMOTE_DIR}"
  echo "    To  : ${ARCHIVE_REMOTE_DIR}"
  lftp_cmd <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 3
set net:timeout 30
set cmd:fail-exit false
mv ${FTP_REMOTE_DIR} ${ARCHIVE_REMOTE_DIR}
mkdir -p ${FTP_REMOTE_DIR}
set cmd:fail-exit true
bye
LFTP_CMDS
fi

echo "==> Uploading new release"
lftp_cmd <<LFTP_CMDS
${LFTP_TLS_CMDS}
set ftp:passive-mode true
set net:max-retries 3
set net:timeout 30
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
