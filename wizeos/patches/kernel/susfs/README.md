# SUSFS kernel patches

Place SUSFS kernel patches here.

Patch files must be `.patch` or `.diff` and should apply from the Android source tree root:

```bash
cd /home/builder/android/grapheneos-<TAG>
git apply --check /root/wizeos/patches/kernel/susfs/0001-example.patch
```

The build script applies these when:

```bash
ROOT=ksunext KSUNEXT_SUSFS=1 SUSFS_PATCH_KERNEL=1
```

SUSFS also needs the matching KernelSU module (`susfs4ksu.zip`) after boot. The script only bundles the module in the release folder; it does not auto-install it into `/data/adb/modules`.
