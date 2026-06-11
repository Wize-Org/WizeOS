#!/usr/bin/env bash
set -euo pipefail

PATCH_ROOT="${1:-$(pwd)/patches/gmscompat-lineage-23.2}"
ANDROID_ROOT="${2:-$(pwd)}"

check_dir() {
  local project_path="$1"
  local patch_dir="$2"

  if [ ! -d "$ANDROID_ROOT/$project_path/.git" ]; then
    echo "SKIP $project_path: not a git project at $ANDROID_ROOT/$project_path"
    return 0
  fi

  if [ ! -d "$PATCH_ROOT/$patch_dir" ]; then
    echo "SKIP $patch_dir: no patch directory"
    return 0
  fi

  echo "==> Checking $project_path <= $patch_dir"
  (
    cd "$ANDROID_ROOT/$project_path"
    for patch in "$PATCH_ROOT/$patch_dir"/*.patch; do
      [ -e "$patch" ] || continue
      echo "  git apply --check ${patch#$PATCH_ROOT/}"
      git apply --check "$patch"
    done
  )
}

check_dir bionic bionic
check_dir libcore libcore
check_dir frameworks/base frameworks-base

echo "Patch check complete."
