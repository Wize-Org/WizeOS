#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-$HOME/gmscompat-port}"
LOS="$PORT/lineageos"
GOS="$PORT/grapheneos"
WIZE="$PORT/WizeOS"

clone_or_update() {
  local url="$1"
  local dir="$2"
  local branch="${3:-}"

  if [ -d "$dir/.git" ]; then
    echo "==> Updating $dir"
    git -C "$dir" fetch --all --prune
    if [ -n "$branch" ]; then
      git -C "$dir" switch "$branch" 2>/dev/null || git -C "$dir" switch -c "$branch" --track "origin/$branch"
      git -C "$dir" pull --ff-only || true
    fi
  else
    echo "==> Cloning $url -> $dir"
    mkdir -p "$(dirname "$dir")"
    if [ -n "$branch" ]; then
      git clone -b "$branch" "$url" "$dir"
    else
      git clone "$url" "$dir"
    fi
  fi
}

mkdir -p "$LOS" "$GOS"

# LineageOS target repos
clone_or_update https://github.com/LineageOS/android_frameworks_base.git "$LOS/frameworks_base" lineage-23.2
clone_or_update https://github.com/LineageOS/android_bionic.git "$LOS/bionic" lineage-23.2
clone_or_update https://github.com/LineageOS/android_libcore.git "$LOS/libcore"

# Try LineageOS libcore lineage-23.2 if it exists; otherwise keep the default branch.
if git -C "$LOS/libcore" ls-remote --exit-code --heads origin lineage-23.2 >/dev/null 2>&1; then
  git -C "$LOS/libcore" switch lineage-23.2 2>/dev/null || git -C "$LOS/libcore" switch -c lineage-23.2 --track origin/lineage-23.2
fi

# GrapheneOS reference repos
clone_or_update https://github.com/GrapheneOS/platform_packages_apps_GmsCompat.git "$GOS/packages_apps_GmsCompat" 16-qpr2
clone_or_update https://github.com/GrapheneOS/platform_external_GmsCompatConfig.git "$GOS/external_GmsCompatConfig" 16-qpr2
clone_or_update https://github.com/GrapheneOS/platform_bionic.git "$GOS/bionic" 16-qpr2
clone_or_update https://github.com/GrapheneOS/platform_libcore.git "$GOS/libcore" 16-qpr2
clone_or_update https://github.com/GrapheneOS/platform_frameworks_base.git "$GOS/frameworks_base" 16-qpr2
clone_or_update https://github.com/GrapheneOS/platform_packages_apps_Settings.git "$GOS/packages_apps_Settings" 16-qpr2

# WizeOS patch queue repo. Clone directly into the workspace root, not inside grapheneos/.
clone_or_update https://github.com/wizdom13/WizeOS.git "$WIZE" main

# The repo currently has a typo in the directory name: pacthes/ instead of patches/.
# Fix it locally so commands and README paths work. Commit/push this separately if desired.
if [ -d "$WIZE/pacthes" ] && [ ! -d "$WIZE/patches" ]; then
  echo "==> Fixing local typo: pacthes -> patches"
  git -C "$WIZE" mv pacthes patches || mv "$WIZE/pacthes" "$WIZE/patches"
fi

PATCH_DIR="$WIZE/patches/gmscompat-lineage-23.2"
if [ ! -d "$PATCH_DIR" ]; then
  echo "ERROR: Patch directory not found: $PATCH_DIR" >&2
  echo "Check whether the patch queue exists under $WIZE/patches or $WIZE/pacthes." >&2
  exit 1
fi

# The checked-in helper expects a full Android tree with frameworks/base.
# These standalone clones use frameworks_base, so run direct checks against each clone.
echo "==> Dry-run patch checks"
git -C "$LOS/bionic" apply --check --verbose "$PATCH_DIR/bionic/"*.patch
git -C "$LOS/libcore" apply --check --verbose "$PATCH_DIR/libcore/"*.patch || true
git -C "$LOS/frameworks_base" apply --check --verbose "$PATCH_DIR/frameworks-base/"*.patch || true

echo
echo "Patch check finished. bionic should pass; libcore/frameworks-base may need manual WIP fixes."
echo "Patch directory: $PATCH_DIR"
echo "LineageOS repos: $LOS"
echo "GrapheneOS refs: $GOS"
