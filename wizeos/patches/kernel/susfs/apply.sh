#!/usr/bin/env bash
set -euo pipefail

# Applies the matching SUSFS patches for Pixel 10 / muzel GKI 6.6 kernels.
# Default source matches kernels such as 6.6.x-android15-8-*:
#   https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android15-6.6
#
# Expected working directory: the kernel source directory selected by WizeOS
# run-as-builder.sh, usually .../kernel_pixel_muzel/common/ack or .../common.

SUSFS_REPO_URL="${SUSFS_REPO_URL:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
KERNEL_SOURCE_DIR="${1:-$(pwd)}"

log() { printf '==> SUSFS: %s\n' "$*"; }
die() { printf 'ERROR: SUSFS: %s\n' "$*" >&2; exit 1; }

[ -d "${KERNEL_SOURCE_DIR}" ] || die "kernel source dir not found: ${KERNEL_SOURCE_DIR}"
cd "${KERNEL_SOURCE_DIR}"
[ -d fs ] || die "${KERNEL_SOURCE_DIR} does not look like a kernel source tree: missing fs/"
[ -d include/linux ] || die "${KERNEL_SOURCE_DIR} does not look like a kernel source tree: missing include/linux/"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

log "fetching ${SUSFS_REPO_URL} branch ${SUSFS_BRANCH}"
git clone --depth 1 --branch "${SUSFS_BRANCH}" "${SUSFS_REPO_URL}" "${tmp}/susfs4ksu"
SUSFS_DIR="${tmp}/susfs4ksu"

main_patch="$(find "${SUSFS_DIR}/kernel_patches" -maxdepth 1 -type f -name '50_add_susfs_in_kernel*.patch' | sort | head -n 1)"
[ -n "${main_patch}" ] || die "missing 50_add_susfs_in_kernel*.patch in upstream branch"
[ -f "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" ] || die "missing KernelSU SUSFS patch in upstream branch"
[ -d "${SUSFS_DIR}/kernel_patches/fs" ] || die "missing upstream fs/ payload"
[ -d "${SUSFS_DIR}/kernel_patches/include/linux" ] || die "missing upstream include/linux payload"

find_ksu_dir() {
  local d
  for d in \
    "${KERNELSU_DIR:-}" \
    "${KERNEL_SOURCE_DIR}/KernelSU" \
    "${KERNEL_SOURCE_DIR}/KernelSU-Next" \
    "${KERNEL_SOURCE_DIR}/drivers/kernelsu" \
    "${KERNEL_SOURCE_DIR}/../KernelSU" \
    "${KERNEL_SOURCE_DIR}/../KernelSU-Next" \
    "${KERNEL_SOURCE_DIR}/../drivers/kernelsu" \
    "${KERNEL_SOURCE_DIR}/../../KernelSU" \
    "${KERNEL_SOURCE_DIR}/../../KernelSU-Next" \
    "${KERNEL_SOURCE_DIR}/../../drivers/kernelsu"; do
    [ -n "${d}" ] || continue
    if [ -f "${d}/kernel/Kconfig" ] && [ -f "${d}/kernel/Kbuild" ]; then
      printf '%s\n' "$(cd "${d}" && pwd)"
      return 0
    fi
  done

  d="$(find "${KERNEL_SOURCE_DIR}" "${KERNEL_SOURCE_DIR}/.." "${KERNEL_SOURCE_DIR}/../.." \
    -maxdepth 4 -type f -path '*/kernel/Kconfig' 2>/dev/null \
    | grep -E '/(KernelSU|KernelSU-Next|kernelsu)/kernel/Kconfig$' \
    | head -n 1 \
    | sed 's#/kernel/Kconfig$##')"
  [ -n "${d}" ] || return 1
  printf '%s\n' "$(cd "${d}" && pwd)"
}

ksu_dir="$(find_ksu_dir || true)"
[ -n "${ksu_dir}" ] || die "could not find KernelSU/KernelSU-Next source dir. Set KERNELSU_DIR=/path/to/KernelSU if needed."
log "KernelSU source: ${ksu_dir}"

apply_or_skip() {
  local repo_dir="$1" patch_file="$2" label="$3"
  if git -C "${repo_dir}" apply --check "${patch_file}" >/dev/null 2>&1; then
    log "applying ${label}"
    git -C "${repo_dir}" apply "${patch_file}"
    return 0
  fi
  if git -C "${repo_dir}" apply --reverse --check "${patch_file}" >/dev/null 2>&1; then
    log "${label} already applied; skipping"
    return 0
  fi
  log "${label} failed git apply --check"
  git -C "${repo_dir}" apply --check "${patch_file}"
}

apply_or_skip "${ksu_dir}" "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" "KernelSU SUSFS patch"

log "copying upstream SUSFS fs/ and include/linux/ payload"
rsync -a "${SUSFS_DIR}/kernel_patches/fs/" "${KERNEL_SOURCE_DIR}/fs/"
rsync -a "${SUSFS_DIR}/kernel_patches/include/linux/" "${KERNEL_SOURCE_DIR}/include/linux/"

apply_or_skip "${KERNEL_SOURCE_DIR}" "${main_patch}" "kernel SUSFS patch"

# The upstream SUSFS notes recommend removing these for Android 14+ GKI builds
# when present, otherwise some modules can fail against protected ABI exports.
rm -f \
  "${KERNEL_SOURCE_DIR}/android/abi_gki_protected_exports_aarch64" \
  "${KERNEL_SOURCE_DIR}/android/abi_gki_protected_exports_x86_64"

log "done. Verify CONFIG_KSU=y and CONFIG_KSU_SUSFS=y before building."
