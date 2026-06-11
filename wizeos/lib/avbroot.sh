#!/usr/bin/env bash
install_avbroot() {
  local target tmpdir asset_url asset_name asset_path extract_dir found_avbroot
  case "$(uname -m)" in x86_64|amd64) target="x86_64-unknown-linux-gnu" ;; aarch64|arm64) target="aarch64-unknown-linux-gnu" ;; *) die "Unsupported host architecture for avbroot auto-install" ;; esac
  log "avbroot not found. Auto-installing avbroot ${AVBROOT_VERSION} for ${target}"
  tmpdir="$(mktemp -d)"; extract_dir="${tmpdir}/extract"; mkdir -p "${extract_dir}"
  asset_url="$(python3 - "${AVBROOT_VERSION}" "${target}" <<'PY'
import json, sys, urllib.request
version, target = sys.argv[1], sys.argv[2]
base = 'https://api.github.com/repos/chenxiaolong/avbroot/releases'
url = base + '/latest' if version == 'latest' else base + '/tags/' + (version if version.startswith('v') else 'v' + version)
req = urllib.request.Request(url, headers={'Accept':'application/vnd.github+json','User-Agent':'wizeos-build-script'})
with urllib.request.urlopen(req, timeout=60) as response: release = json.load(response)
candidates=[]
for asset in release.get('assets', []):
    name=asset.get('name',''); dl=asset.get('browser_download_url','')
    if target in name and dl: candidates.append((name,dl))
for suf in ('.zip','.tar.xz','.tar.gz','.tgz'):
    for name,dl in candidates:
        if name.endswith(suf): print(dl); sys.exit(0)
if candidates: print(candidates[0][1]); sys.exit(0)
raise SystemExit('No avbroot release asset found')
PY
)"
  asset_name="$(basename "${asset_url%%\?*}")"; asset_path="${tmpdir}/${asset_name}"; curl -fL -o "${asset_path}" "${asset_url}"
  case "${asset_name}" in *.zip) unzip -q "${asset_path}" -d "${extract_dir}" ;; *.tar.xz) tar -xJf "${asset_path}" -C "${extract_dir}" ;; *.tar.gz|*.tgz) tar -xzf "${asset_path}" -C "${extract_dir}" ;; *) mkdir -p "${extract_dir}/single"; cp "${asset_path}" "${extract_dir}/single/avbroot"; chmod +x "${extract_dir}/single/avbroot" ;; esac
  found_avbroot="$(find "${extract_dir}" -type f -name avbroot -perm /111 | head -n 1)"; [ -n "${found_avbroot}" ] || found_avbroot="$(find "${extract_dir}" -type f -name avbroot | head -n 1)"
  [ -n "${found_avbroot}" ] || die "Downloaded avbroot archive did not contain avbroot"
  mkdir -p "$(dirname "${AVBROOT_INSTALL_PATH}")"; install -m 0755 "${found_avbroot}" "${AVBROOT_INSTALL_PATH}"; rm -rf "${tmpdir}"; hash -r
  AVBROOT="${AVBROOT_INSTALL_PATH}"; export AVBROOT; "${AVBROOT}" --version
}
