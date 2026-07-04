#!/usr/bin/env bash
log() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }
require_root() { [ "$(id -u)" -eq 0 ] || die "Run as root. Builder steps run as ${BUILD_USER}."; }
validate_bool() { case "$2" in 0|1) ;; *) die "$1 must be 0 or 1. Current value: $2" ;; esac; }
wizeos_profile_manifest_file() {
  case "${WIZEOS_PROFILE}" in
    secure) echo "wizeos-secure.xml" ;;
    balanced) echo "wizeos-balanced.xml" ;;
    flexible) echo "wizeos-flexible.xml" ;;
    *) die "WIZEOS_PROFILE must be secure, balanced, or flexible. Current value: ${WIZEOS_PROFILE}" ;;
  esac
}
normalize_manifest_defaults() {
  case "${WIZEOS_PROFILE}" in secure|balanced|flexible) ;; *) die "WIZEOS_PROFILE must be secure, balanced, or flexible. Current value: ${WIZEOS_PROFILE}" ;; esac
  case "${USE_WIZEOS_MANIFEST}" in 0|1) ;; *) die "USE_WIZEOS_MANIFEST must be 0 or 1" ;; esac
  if [ "${USE_WIZEOS_MANIFEST}" = "1" ]; then
    MANIFEST_URL="${MANIFEST_URL:-https://github.com/wizdom13/platform_manifest.git}"
    MANIFEST_BRANCH="${MANIFEST_BRANCH:-17}"
    MANIFEST_FILE="${MANIFEST_FILE:-$(wizeos_profile_manifest_file)}"
    VERIFY_MANIFEST_TAG="${VERIFY_MANIFEST_TAG:-0}"
  else
    MANIFEST_URL="${MANIFEST_URL:-https://github.com/GrapheneOS/platform_manifest.git}"
    MANIFEST_BRANCH="${MANIFEST_BRANCH:-refs/tags/${TAG}}"
    MANIFEST_FILE="${MANIFEST_FILE:-}"
    VERIFY_MANIFEST_TAG="${VERIFY_MANIFEST_TAG:-1}"
  fi
  export WIZEOS_PROFILE MANIFEST_URL MANIFEST_BRANCH MANIFEST_FILE VERIFY_MANIFEST_TAG
}
validate_config() {
  validate_bool SIGNED "${SIGNED}"
  validate_bool CLEAN_OUT "${CLEAN_OUT}"
  validate_bool START_OVER "${START_OVER}"
  validate_bool AVBROOT_AUTO_INSTALL "${AVBROOT_AUTO_INSTALL}"
  validate_bool LSPOSED_COMPAT "${LSPOSED_COMPAT}"
  validate_bool VERIFY_MANIFEST_TAG "${VERIFY_MANIFEST_TAG}"
  validate_bool KSU_BUNDLE_MANAGER "${KSU_BUNDLE_MANAGER}"
  validate_bool KSU_BUNDLE_ZYGISK "${KSU_BUNDLE_ZYGISK}"
  validate_bool KSU_PATCH_KERNEL "${KSU_PATCH_KERNEL}"
  validate_bool KSUNEXT_SUSFS "${KSUNEXT_SUSFS}"
  validate_bool SUSFS_PATCH_KERNEL "${SUSFS_PATCH_KERNEL}"
  validate_bool SUSFS_BUNDLE_MODULE "${SUSFS_BUNDLE_MODULE}"
  validate_bool KERNEL_CLEAN "${KERNEL_CLEAN}"

  case "${WIZEOS_PROFILE}" in secure|balanced|flexible) ;; *) die "WIZEOS_PROFILE must be secure, balanced, or flexible. Current value: ${WIZEOS_PROFILE}" ;; esac
  case "${ROOT}" in none|magisk|ksunext) ;; *) die "ROOT must be none, magisk, or ksunext. Current value: ${ROOT}" ;; esac
  case "${KSU_FLAVOR}" in ksunext) ;; *) die "KSU_FLAVOR=${KSU_FLAVOR} is no longer supported. Use ROOT=ksunext with KSU_FLAVOR=ksunext." ;; esac
  case "${KSU_INTEGRATION}" in setup|patch) ;; *) die "KSU_INTEGRATION must be setup or patch. Current value: ${KSU_INTEGRATION}" ;; esac
  case "${KERNEL_BUILD}" in auto|0|1) ;; *) die "KERNEL_BUILD must be auto, 0, or 1. Current value: ${KERNEL_BUILD}" ;; esac

  [ "${ROOT}" != "magisk" ] || [ "${SIGNED}" = "1" ] || die "ROOT=magisk requires SIGNED=1"
  [ "${ROOT}" != "magisk" ] || [ -n "${MAGISK_APK}" ] || die "ROOT=magisk requires MAGISK_APK=/path/to/Magisk.apk"
  [ "${ROOT}" != "ksunext" ] || [ "${SIGNED}" = "1" ] || die "ROOT=ksunext requires SIGNED=1"
  [ "${ROOT}" != "ksunext" ] || [ "${KSUNEXT_SUSFS}" != "1" ] || [ "${SUSFS_PATCH_KERNEL}" = "1" ] || warn "KSUNEXT_SUSFS=1 but SUSFS_PATCH_KERNEL=0. This will only bundle module files."
  [ "${KSUNEXT_SUSFS}" != "1" ] || [ "${ROOT}" = "ksunext" ] || die "KSUNEXT_SUSFS=1 requires ROOT=ksunext"
  [ "${LSPOSED_COMPAT}" != "1" ] || [ "${USE_WIZEOS_MANIFEST}" = "1" ] || die "LSPOSED_COMPAT=1 requires USE_WIZEOS_MANIFEST=1"
}
print_config() {
  log "WizeOS build configuration"
  echo "    Action              : ${ACTION:-all}"
  echo "    Device              : ${DEVICE}"
  echo "    Tag                 : ${TAG}"
  echo "    Build number        : ${BUILD_NUMBER}"
  echo "    Build user          : ${BUILD_USER}"
  echo "    Workdir             : ${WORKDIR}"
  echo "    Profile             : ${WIZEOS_PROFILE}"
  echo "    Start over          : ${START_OVER}"
  echo "    Clean out           : ${CLEAN_OUT}"
  echo "    Signed release      : ${SIGNED}"
  echo "    Root mode           : ${ROOT}"
  if [ "${ROOT}" = "ksunext" ]; then
    echo "    Kernel root         : KernelSU Next"
    echo "    KSU manager APK     : ${KSU_MANAGER_APK:-KernelSU Next default}"
    echo "    KSU Zygisk zip      : ${KSU_ZYGISK_ZIP:-Zygisk Next default}"
    echo "    KSU integration     : ${KSU_INTEGRATION}"
    echo "    KSU setup URL       : ${KSU_SETUP_URL:-KernelSU Next default}"
    echo "    KSU setup arg       : ${KSU_SETUP_ARG:-latest/default}"
    echo "    KSU patch dir       : ${KSU_KERNEL_PATCH_DIR}"
    echo "    SUSFS enabled       : ${KSUNEXT_SUSFS}"
    echo "    SUSFS patches       : ${SUSFS_PATCH_KERNEL} (${SUSFS_KERNEL_PATCH_DIR})"
    echo "    SUSFS module        : ${SUSFS_MODULE_ZIP}"
    echo "    Kernel build        : ${KERNEL_BUILD}"
    echo "    Kernel repo         : ${KERNEL_REPO_URL} (${KERNEL_REPO_BRANCH})"
    echo "    Kernel workdir      : ${KERNEL_WORKDIR}"
    echo "    Kernel codename     : ${KERNEL_CODENAME}"
    echo "    Kernel prebuilts    : ${KERNEL_OS_PREBUILT_DIR}"
  fi
  echo "    Patch dir           : ${PATCHES_DIR}"
  echo "    Profile patch dir   : ${WIZEOS_PROFILE_PATCHES_DIR}"
  echo "    Update server       : ${UPDATE_SERVER}"
  echo "    Manifest URL        : ${MANIFEST_URL}"
  echo "    Manifest branch/ref : ${MANIFEST_BRANCH}"
  echo "    Manifest file       : ${MANIFEST_FILE:-default.xml}"
}
