#!/usr/bin/env bash

resolve_ksu_flavor_inputs() {
  case "${KSU_FLAVOR}" in
    ksunext)
      ;;
    *)
      die "KSU_FLAVOR=${KSU_FLAVOR} is no longer supported. Use ROOT=ksunext with KSU_FLAVOR=ksunext."
      ;;
  esac

  KSU_MANAGER_APK_RESOLVED="${KSU_MANAGER_APK:-${KSUNEXT_APK}}"
  KSU_ZYGISK_ZIP_RESOLVED="${KSU_ZYGISK_ZIP:-${ZYGISK_NEXT_ZIP}}"
  KSU_INTEGRATION_RESOLVED="${KSU_INTEGRATION:-${KSUNEXT_INTEGRATION}}"
  KSU_SETUP_URL_RESOLVED="${KSU_SETUP_URL:-${KSUNEXT_SETUP_URL}}"
  KSU_SETUP_ARG_RESOLVED="${KSU_SETUP_ARG:-${KSUNEXT_SETUP_ARG}}"

  # The normal KernelSU-Next latest tag is not guaranteed to match SUSFS.
  # When KSUNEXT_SUSFS=1, default to pershoot's dev-susfs integration used by
  # WildKernels' android15-6.6 SUSFS workflow. Explicit KSU_SETUP_URL or
  # KSUNEXT_SETUP_URL overrides still win.
  if [ "${KSUNEXT_SUSFS}" = "1" ] && [ -z "${KSU_SETUP_URL:-}" ] && [ "${KSUNEXT_SETUP_URL}" = "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" ]; then
    KSU_SETUP_URL_RESOLVED="https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh"
    if [ -z "${KSU_SETUP_ARG_RESOLVED}" ]; then
      KSU_SETUP_ARG_RESOLVED="dev-susfs"
    fi
  fi

  KSU_KERNEL_PATCH_DIR_RESOLVED="${KSUNEXT_KERNEL_PATCH_DIR}"
  KSU_MANAGER_RELEASE_NAME="KernelSU_Next.apk"
  KSU_ZYGISK_RELEASE_NAME="Zygisk-Next.zip"

  if [ "${KSU_INTEGRATION_RESOLVED}" = "setup" ] && [ -z "${KSU_SETUP_URL_RESOLVED}" ]; then
    die "ROOT=ksunext with setup integration requires KSU_SETUP_URL or KSUNEXT_SETUP_URL"
  fi

  export KSU_MANAGER_APK_RESOLVED KSU_ZYGISK_ZIP_RESOLVED KSU_INTEGRATION_RESOLVED KSU_SETUP_URL_RESOLVED KSU_SETUP_ARG_RESOLVED KSU_KERNEL_PATCH_DIR_RESOLVED KSU_MANAGER_RELEASE_NAME KSU_ZYGISK_RELEASE_NAME
}

prepare_ksunext_inputs() {
  [ "${ROOT}" = "ksunext" ] || return 0

  resolve_ksu_flavor_inputs
  log "Preparing KernelSU Next inputs"

  KSUNEXT_DIR="${WORKDIR}/ksunext"
  mkdir -p "${KSUNEXT_DIR}"

  KSU_MANAGER_APK_WORKDIR=""
  KSU_ZYGISK_ZIP_WORKDIR=""
  SUSFS_MODULE_ZIP_WORKDIR=""

  if [ "${KSU_BUNDLE_MANAGER}" = "1" ]; then
    [ -f "${KSU_MANAGER_APK_RESOLVED}" ] || die "Missing KernelSU Next manager APK: ${KSU_MANAGER_APK_RESOLVED}"
    KSU_MANAGER_APK_WORKDIR="${KSUNEXT_DIR}/${KSU_MANAGER_RELEASE_NAME}"
    rsync -a "${KSU_MANAGER_APK_RESOLVED}" "${KSU_MANAGER_APK_WORKDIR}"
  elif [ -n "${KSU_MANAGER_APK_RESOLVED}" ] && [ -f "${KSU_MANAGER_APK_RESOLVED}" ]; then
    KSU_MANAGER_APK_WORKDIR="${KSUNEXT_DIR}/${KSU_MANAGER_RELEASE_NAME}"
    rsync -a "${KSU_MANAGER_APK_RESOLVED}" "${KSU_MANAGER_APK_WORKDIR}"
  fi

  if [ "${KSU_BUNDLE_ZYGISK}" = "1" ]; then
    [ -f "${KSU_ZYGISK_ZIP_RESOLVED}" ] || die "Missing Zygisk Next module zip: ${KSU_ZYGISK_ZIP_RESOLVED}"
    KSU_ZYGISK_ZIP_WORKDIR="${KSUNEXT_DIR}/${KSU_ZYGISK_RELEASE_NAME}"
    rsync -a "${KSU_ZYGISK_ZIP_RESOLVED}" "${KSU_ZYGISK_ZIP_WORKDIR}"
  elif [ -n "${KSU_ZYGISK_ZIP_RESOLVED}" ] && [ -f "${KSU_ZYGISK_ZIP_RESOLVED}" ]; then
    KSU_ZYGISK_ZIP_WORKDIR="${KSUNEXT_DIR}/${KSU_ZYGISK_RELEASE_NAME}"
    rsync -a "${KSU_ZYGISK_ZIP_RESOLVED}" "${KSU_ZYGISK_ZIP_WORKDIR}"
  fi

  if [ "${SUSFS_BUNDLE_MODULE}" = "1" ]; then
    [ -f "${SUSFS_MODULE_ZIP}" ] || die "Missing SUSFS KernelSU module zip: ${SUSFS_MODULE_ZIP}"
    SUSFS_MODULE_ZIP_WORKDIR="${KSUNEXT_DIR}/susfs4ksu.zip"
    rsync -a "${SUSFS_MODULE_ZIP}" "${SUSFS_MODULE_ZIP_WORKDIR}"
  elif [ -f "${SUSFS_MODULE_ZIP}" ]; then
    SUSFS_MODULE_ZIP_WORKDIR="${KSUNEXT_DIR}/susfs4ksu.zip"
    rsync -a "${SUSFS_MODULE_ZIP}" "${SUSFS_MODULE_ZIP_WORKDIR}"
  fi

  # Backward-compatible aliases used by older builder code paths.
  KSUNEXT_APK_WORKDIR="${KSU_MANAGER_APK_WORKDIR}"
  ZYGISK_NEXT_ZIP_WORKDIR="${KSU_ZYGISK_ZIP_WORKDIR}"

  chown -R "${BUILD_USER}:${BUILD_USER}" "${KSUNEXT_DIR}"

  export KSUNEXT_DIR KSU_MANAGER_APK_WORKDIR KSU_ZYGISK_ZIP_WORKDIR SUSFS_MODULE_ZIP_WORKDIR KSUNEXT_APK_WORKDIR ZYGISK_NEXT_ZIP_WORKDIR
}
