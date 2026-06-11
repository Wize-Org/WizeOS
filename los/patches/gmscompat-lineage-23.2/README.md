# GmsCompat patch queue for LineageOS 23.2

This directory is the start of a fresh GmsCompat forward-port for WizeOS based on:

- LineageOS 23.2 platform sources
- GrapheneOS `platform_packages_apps_GmsCompat` branch `16-qpr2`

The old `sn-00-x/lineage-gmscompat` patches are Android 11 / LineageOS 18.1 era. Use them as a checklist only, not as the implementation base.

## Status

This queue is intentionally WIP. The low-level `bionic` and `libcore` patches are the safest first pieces because the same code paths still exist in modern platform sources. The `frameworks/base` patches are scaffolding for the new port and are not a complete compatibility layer.

## Recommended apply order

1. Import GrapheneOS GmsCompat app/lib/config with the local manifest patch.
2. Apply `bionic` fd-zip support.
3. Apply `libcore` ZipFile fd-path support.
4. Apply `libcore` classloader hook placeholders and complete them against the exact synced branch.
5. Apply the `frameworks/base` scaffold.
6. Wire compat-change enablement.
7. Port the rest of the framework hooks in small, testable groups.

## Validation commands

From a synced LineageOS/WizeOS tree:

```bash
patches/gmscompat-lineage-23.2/scripts/check-patches.sh \
  "$(pwd)/patches/gmscompat-lineage-23.2" \
  "$(pwd)"
```

Manual checks:

```bash
cd bionic && git apply --check /path/to/patches/gmscompat-lineage-23.2/bionic/*.patch
cd ../libcore && git apply --check /path/to/patches/gmscompat-lineage-23.2/libcore/*.patch
cd ../frameworks/base && git apply --check /path/to/patches/gmscompat-lineage-23.2/frameworks-base/*.patch
```

After applying:

```bash
source build/envsetup.sh
lunch lineage_<device>-userdebug
mka bacon
```

## Current limitations

- This is not yet a complete, build-proven GmsCompat port.
- Modern GrapheneOS platform-side changes still need to be compared and selectively reimplemented for LineageOS 23.2.
- `libcore` must be checked against the exact branch synced by the manifest.
- The current framework patches intentionally use package-name detection only; proper signature validation is required before production use.
