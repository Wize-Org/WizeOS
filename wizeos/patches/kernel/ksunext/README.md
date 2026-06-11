# KernelSU Next kernel patches

Place KernelSU Next kernel integration patches here.

Patch files must be `.patch` or `.diff` and should apply from the Android source tree root:

```bash
cd /home/builder/android/grapheneos-<TAG>
git apply --check /root/wizeos/patches/kernel/ksunext/0001-example.patch
```

The build script applies these when:

```bash
ROOT=ksunext KSUNEXT_PATCH_KERNEL=1
```

This folder is only the hook location. The correct Pixel/GrapheneOS kernel patch set still needs to be added for the target kernel tree.
