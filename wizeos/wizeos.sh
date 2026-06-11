#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
DEVICE="${DEVICE:-mustang}"
export DEVICE

source "${SCRIPT_DIR}/config/defaults.env"
[ ! -f "${SCRIPT_DIR}/config/${DEVICE}.env" ] || source "${SCRIPT_DIR}/config/${DEVICE}.env"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/host_setup.sh"
source "${SCRIPT_DIR}/lib/workspace.sh"
source "${SCRIPT_DIR}/lib/keys.sh"
source "${SCRIPT_DIR}/lib/avbroot.sh"
source "${SCRIPT_DIR}/lib/magisk.sh"
source "${SCRIPT_DIR}/lib/ksunext.sh"
source "${SCRIPT_DIR}/lib/builder.sh"

require_root
normalize_manifest_defaults
validate_config
print_config

case "${ACTION:-all}" in
  host)
    setup_host
    prepare_workspace
    ;;
  keys)
    prepare_workspace
    prepare_keys
    ;;
  sync)
    prepare_workspace
    run_builder_phase sync
    ;;
  kernel)
    prepare_workspace
    run_builder_phase kernel
    ;;
  build)
    prepare_workspace
    prepare_ksunext_inputs
    run_builder_phase build
    ;;
  release)
    prepare_workspace
    prepare_keys
    prepare_magisk_inputs
    prepare_ksunext_inputs
    run_builder_phase release
    ;;
  magisk)
    prepare_workspace
    prepare_magisk_inputs
    run_builder_phase magisk
    ;;
  ksunext)
    prepare_workspace
    prepare_ksunext_inputs
    run_builder_phase ksunext
    ;;
  upload)
    exec "${SCRIPT_DIR}/scripts/upload.sh"
    ;;
  all)
    setup_host
    prepare_workspace
    prepare_keys
    prepare_magisk_inputs
    prepare_ksunext_inputs
    run_builder_phase all
    ;;
  *)
    die "Unknown ACTION=${ACTION}. Use host, keys, sync, kernel, build, release, magisk, ksunext, upload, or all."
    ;;
esac

log "Done: ACTION=${ACTION:-all}"
