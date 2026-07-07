#!/usr/bin/env bash
set -euo pipefail

# Applies the matching SUSFS patches for Pixel 10 / muzel GKI 6.6 kernels.
# Linux kernel SUSFS payload defaults to:
#   https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android15-6.6
#
# KernelSU-Next moves quickly. Prefer WizeOS-local KernelSU-Next SUSFS ports
# when present, then the complete upstream KernelSU-side SUSFS patch when it
# matches the checked-out KernelSU tree. The WildKernels small fix patches are
# disabled by default because they can partially patch newer KernelSU-Next trees
# and then fail later at compile time.

SUSFS_REPO_URL="${SUSFS_REPO_URL:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android15-6.6}"
SUSFS_KSUNEXT_PATCH_REPO_URL="${SUSFS_KSUNEXT_PATCH_REPO_URL:-https://github.com/WildKernels/kernel_patches.git}"
SUSFS_KSUNEXT_PATCH_DIR="${SUSFS_KSUNEXT_PATCH_DIR:-next/susfs_fix_patches/v2.2.0}"
SUSFS_USE_WILDKERNELS_KSUNEXT_PATCHES="${SUSFS_USE_WILDKERNELS_KSUNEXT_PATCHES:-0}"
SUSFS_KSUNEXT_PATCH_STRICT="${SUSFS_KSUNEXT_PATCH_STRICT:-0}"
SUSFS_REMOVE_PROTECTED_EXPORTS="${SUSFS_REMOVE_PROTECTED_EXPORTS:-0}"
KERNEL_SOURCE_DIR="${1:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '==> SUSFS: %s\n' "$*"; }
warn() { printf 'WARNING: SUSFS: %s\n' "$*" >&2; }
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

main_patch="$(find "${SUSFS_DIR}/kernel_patches" -maxdepth 1 -type f \
  \( -name '50_add_susfs_in_gki-*.patch' -o -name '50_add_susfs_in_kernel*.patch' \) \
  | sort \
  | head -n 1)"
[ -n "${main_patch}" ] || die "missing 50_add_susfs_in_gki-*.patch or 50_add_susfs_in_kernel*.patch in upstream branch"
[ -d "${SUSFS_DIR}/kernel_patches/fs" ] || die "missing upstream fs/ payload"
[ -d "${SUSFS_DIR}/kernel_patches/include/linux" ] || die "missing upstream include/linux payload"

# Prefer the WizeOS-local GrapheneOS port when present. This patch is a full
# Git patch for GrapheneOS common 6.6 and already contains the SUSFS payload
# files, so the upstream fs/ and include/linux/ payload must not be copied first.
LOCAL_GRAPHENEOS_PATCH="${SUSFS_LOCAL_KERNEL_PATCH:-${SCRIPT_DIR}/50_add_susfs_in_grapheneos_common-6.6.patch}"
SUSFS_LOCAL_FULL_PATCH=0
if [ -f "${LOCAL_GRAPHENEOS_PATCH}" ]; then
  main_patch="${LOCAL_GRAPHENEOS_PATCH}"
  SUSFS_LOCAL_FULL_PATCH=1
  log "using local GrapheneOS common 6.6 kernel patch: ${main_patch}"
else
  log "using upstream GKI kernel patch: ${main_patch}"
fi

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
log "main kernel patch: ${main_patch}"

ksu_has_susfs_support() {
  grep -Rqs 'CONFIG_KSU_SUSFS\|susfs_init\|<linux/susfs.h>' "${ksu_dir}/kernel"
}

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

try_apply_or_warn() {
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
  if [ "${SUSFS_KSUNEXT_PATCH_STRICT}" = "1" ]; then
    log "${label} failed git apply --check"
    git -C "${repo_dir}" apply --check "${patch_file}"
  fi
  warn "${label} does not match this KernelSU-Next tree; skipping best-effort patch"
  return 1
}

apply_local_ksunext_susfs_patch() {
  local s="${SUSFS_LOCAL_KSUNEXT_SCRIPT:-${SCRIPT_DIR}/apply_ksunext_susfs_3b18216f.sh}"
  if [ -f "${s}" ]; then
    log "applying scripted local KernelSU-Next SUSFS port $(basename "${s}")"
    bash "${s}" "${ksu_dir}"
    return 0
  fi

  local p="${SUSFS_LOCAL_KSUNEXT_PATCH:-${SCRIPT_DIR}/10_enable_susfs_for_ksunext_3b18216f.patch}"
  [ -f "${p}" ] || return 1

  if git -C "${ksu_dir}" apply --check "${p}" >/dev/null 2>&1; then
    log "applying local KernelSU-Next SUSFS port $(basename "${p}")"
    git -C "${ksu_dir}" apply "${p}"
    return 0
  fi

  if git -C "${ksu_dir}" apply --reverse --check "${p}" >/dev/null 2>&1; then
    log "local KernelSU-Next SUSFS port already applied; skipping"
    return 0
  fi

  warn "local KernelSU-Next SUSFS port does not match this KernelSU tree"
  return 1
}

apply_upstream_ksu_susfs_patch() {
  local p="${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  [ -f "${p}" ] || return 1

  if git -C "${ksu_dir}" apply --check "${p}" >/dev/null 2>&1; then
    log "applying upstream KernelSU-side SUSFS patch $(basename "${p}")"
    git -C "${ksu_dir}" apply "${p}"
    return 0
  fi

  if git -C "${ksu_dir}" apply --reverse --check "${p}" >/dev/null 2>&1; then
    log "upstream KernelSU-side SUSFS patch already applied; skipping"
    return 0
  fi

  warn "upstream KernelSU-side SUSFS patch does not match this KernelSU tree"
  return 1
}

apply_wildkernels_ksunext_susfs_patches() {
  [ "${SUSFS_USE_WILDKERNELS_KSUNEXT_PATCHES}" = "1" ] || return 1

  log "fetching KernelSU-Next SUSFS fallback patches from ${SUSFS_KSUNEXT_PATCH_REPO_URL}"
  git clone --depth 1 "${SUSFS_KSUNEXT_PATCH_REPO_URL}" "${tmp}/wildkernel_patches"
  local patch_root="${tmp}/wildkernel_patches/${SUSFS_KSUNEXT_PATCH_DIR}"
  [ -d "${patch_root}" ] || die "missing KernelSU-Next SUSFS patch dir: ${SUSFS_KSUNEXT_PATCH_DIR}"

  mapfile -t ksu_patches < <(find "${patch_root}" -type f \( -name '*.patch' -o -name '*.diff' \) | sort)
  [ "${#ksu_patches[@]}" -gt 0 ] || die "no .patch or .diff files found in ${SUSFS_KSUNEXT_PATCH_DIR}"

  local p applied=0
  for p in "${ksu_patches[@]}"; do
    if try_apply_or_warn "${ksu_dir}" "${p}" "KernelSU-Next SUSFS fallback patch $(basename "${p}")"; then
      applied=1
    fi
  done

  [ "${applied}" = "1" ] || return 1
  return 0
}

fix_susfs_kernel_headers() {
  local def="${KERNEL_SOURCE_DIR}/include/linux/susfs_def.h"
  [ -f "${def}" ] || return 0
  python3 - "${def}" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if 'current_uid().val' in s and '#include <linux/cred.h>' not in s:
    marker = '#define __SUSFS_DEF_H__\n'
    if marker in s:
        s = s.replace(marker, marker + '\n#include <linux/cred.h>\n', 1)
    else:
        s = '#include <linux/cred.h>\n' + s
    p.write_text(s)
PY
}

apply_ksunext_susfs_patches() {
  if ksu_has_susfs_support; then
    log "KernelSU source already has SUSFS support; skipping KernelSU-side SUSFS patches"
    return 0
  fi

  if apply_local_ksunext_susfs_patch; then
    return 0
  fi

  if apply_upstream_ksu_susfs_patch; then
    return 0
  fi

  if apply_wildkernels_ksunext_susfs_patches; then
    return 0
  fi

  die "could not apply any KernelSU-side SUSFS patch. The fallback WildKernels patches are disabled by default because they caused sucompat.c compile failures on this KernelSU-Next tree. Set SUSFS_USE_WILDKERNELS_KSUNEXT_PATCHES=1 only if you intentionally want to test them."
}

apply_ksunext_susfs_patches

if [ "${SUSFS_LOCAL_FULL_PATCH}" = "1" ]; then
  log "local GrapheneOS patch includes SUSFS payload; skipping upstream payload copy"
else
  log "copying upstream SUSFS fs/ and include/linux/ payload"
  rsync -a "${SUSFS_DIR}/kernel_patches/fs/" "${KERNEL_SOURCE_DIR}/fs/"
  rsync -a "${SUSFS_DIR}/kernel_patches/include/linux/" "${KERNEL_SOURCE_DIR}/include/linux/"
fi

apply_or_skip "${KERNEL_SOURCE_DIR}" "${main_patch}" "kernel SUSFS patch"
fix_susfs_kernel_headers

# GrapheneOS / Kleaf BUILD.bazel references these ABI export files, so keep
# them by default. Set SUSFS_REMOVE_PROTECTED_EXPORTS=1 only for kernels whose
# build rules do not require android/abi_gki_protected_exports_* as inputs.
if [ "${SUSFS_REMOVE_PROTECTED_EXPORTS}" = "1" ]; then
  log "removing protected ABI export lists because SUSFS_REMOVE_PROTECTED_EXPORTS=1"
  rm -f \
    "${KERNEL_SOURCE_DIR}/android/abi_gki_protected_exports_aarch64" \
    "${KERNEL_SOURCE_DIR}/android/abi_gki_protected_exports_x86_64"
else
  log "keeping protected ABI export lists required by GrapheneOS/Kleaf"
fi

log "done. Verify CONFIG_KSU=y and CONFIG_KSU_SUSFS=y before building."
