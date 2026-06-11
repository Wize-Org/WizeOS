#!/usr/bin/env bash
prepare_magisk_inputs() {
  [ "${ROOT}" = "magisk" ] || return 0
  log "Preparing Magisk/avbroot inputs"
  if ! AVBROOT_RESOLVED="$(command -v "${AVBROOT}" 2>/dev/null)"; then
    if [ -x "${AVBROOT}" ]; then AVBROOT_RESOLVED="${AVBROOT}"; elif [ "${AVBROOT_AUTO_INSTALL}" = "1" ]; then install_avbroot; AVBROOT_RESOLVED="$(command -v "${AVBROOT}" 2>/dev/null || true)"; [ -n "${AVBROOT_RESOLVED}" ] || [ ! -x "${AVBROOT}" ] || AVBROOT_RESOLVED="${AVBROOT}"; fi
  fi
  [ -n "${AVBROOT_RESOLVED:-}" ] || die "avbroot was not found"
  AVBROOT="${AVBROOT_RESOLVED}"; export AVBROOT
  [ -f "${MAGISK_APK}" ] || die "MAGISK_APK does not exist: ${MAGISK_APK}"
  MAGISK_DIR="${WORKDIR}/magisk"; mkdir -p "${MAGISK_DIR}"; MAGISK_APK_WORKDIR="${MAGISK_DIR}/Magisk.apk"; rsync -a "${MAGISK_APK}" "${MAGISK_APK_WORKDIR}"; export MAGISK_APK_WORKDIR
  [ -n "${AVBROOT_AVB_KEY}" ] || AVBROOT_AVB_KEY="${WORKDIR}/keys/${DEVICE}/avb.pem"
  [ -n "${AVBROOT_OTA_CERT}" ] || AVBROOT_OTA_CERT="${WORKDIR}/keys/${DEVICE}/releasekey.x509.pem"
  [ -n "${AVBROOT_OTA_KEY}" ] || AVBROOT_OTA_KEY="${WORKDIR}/keys/${DEVICE}/ota-avbroot.key"
  [ -f "${AVBROOT_AVB_KEY}" ] || die "Missing AVB key: ${AVBROOT_AVB_KEY}"
  [ -f "${AVBROOT_OTA_CERT}" ] || die "Missing OTA cert: ${AVBROOT_OTA_CERT}"
  if [ ! -f "${AVBROOT_OTA_KEY}" ]; then
    RELEASEKEY_PK8="${WORKDIR}/keys/${DEVICE}/releasekey.pk8"; [ -f "${RELEASEKEY_PK8}" ] || die "Missing releasekey.pk8: ${RELEASEKEY_PK8}"
    openssl pkcs8 -topk8 -nocrypt -inform DER -in "${RELEASEKEY_PK8}" -out "${AVBROOT_OTA_KEY}" -outform PEM
  fi
  chown -R "${BUILD_USER}:${BUILD_USER}" "${MAGISK_DIR}" "${WORKDIR}/keys"; chmod 0600 "${AVBROOT_OTA_KEY}" 2>/dev/null || true
  export AVBROOT_AVB_KEY AVBROOT_OTA_KEY AVBROOT_OTA_CERT AVBROOT_PASS_AVB_FILE AVBROOT_PASS_OTA_FILE MAGISK_APK_WORKDIR
}
