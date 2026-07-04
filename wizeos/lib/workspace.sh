#!/usr/bin/env bash
prepare_builder_patches() {
  local source_patches="${PATCHES_DIR}"
  local dest_patches="${BUILDER_PATCHES_DIR}"

  mkdir -p "${dest_patches}"
  if [ -d "${source_patches}" ]; then
    log "Copying patch folders to builder-readable location"
    rsync -a --delete "${source_patches%/}/" "${dest_patches}/"
  else
    warn "Patch source directory does not exist yet: ${source_patches}"
  fi

  mkdir -p \
    "${dest_patches}/profiles/secure" \
    "${dest_patches}/profiles/balanced" \
    "${dest_patches}/profiles/flexible" \
    "${dest_patches}/lsposed-compat" \
    "${dest_patches}/kernel/ksunext" \
    "${dest_patches}/kernel/susfs"

  chown -R "${BUILD_USER}:${BUILD_USER}" "${dest_patches}"

  PATCHES_DIR="${dest_patches}"
  WIZEOS_PROFILE_PATCHES_DIR="${dest_patches}/profiles/${WIZEOS_PROFILE}"
  LSPOSED_PATCHES_DIR="${dest_patches}/lsposed-compat"
  KSUNEXT_KERNEL_PATCH_DIR="${dest_patches}/kernel/ksunext"
  SUSFS_KERNEL_PATCH_DIR="${dest_patches}/kernel/susfs"

  export PATCHES_DIR WIZEOS_PROFILE_PATCHES_DIR LSPOSED_PATCHES_DIR KSUNEXT_KERNEL_PATCH_DIR SUSFS_KERNEL_PATCH_DIR
}

prepare_workspace() {
  mkdir -p "${BASE_DIR}"
  KEYS_BACKUP="/home/${BUILD_USER}/keys-backup-${DEVICE}-$(date +%Y%m%d%H%M%S)"; export KEYS_BACKUP
  if [ "${START_OVER}" = "1" ]; then
    log "START_OVER=1 requested. Backing up keys and deleting old tree."
    if [ -d "${WORKDIR}/keys" ]; then mkdir -p "${KEYS_BACKUP}"; cp -a "${WORKDIR}/keys/." "${KEYS_BACKUP}/"; chown -R "${BUILD_USER}:${BUILD_USER}" "${KEYS_BACKUP}"; fi
    rm -rf "${WORKDIR}" "/root/android/grapheneos-${TAG}"
  fi
  if [ -d "/root/android/grapheneos-${TAG}" ] && [ ! -d "${WORKDIR}" ]; then mv "/root/android/grapheneos-${TAG}" "${WORKDIR}"; fi
  mkdir -p "${WORKDIR}"; chown -R "${BUILD_USER}:${BUILD_USER}" "${BASE_DIR}" "/home/${BUILD_USER}"
  prepare_builder_patches
}
