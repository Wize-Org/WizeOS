# SUSFS kernel patches

This directory supports two modes:

1. `apply.sh` for the default Pixel 10 / muzel `android15-6.6` SUSFS flow.
2. Static `.patch` / `.diff` files for manual patch sets.

The default `apply.sh` clones:

```text
https://gitlab.com/simonpunk/susfs4ksu.git
branch: gki-android15-6.6
```

It then applies the matching SUSFS kernel payload to the selected GrapheneOS kernel source directory, usually one of:

```text
/home/builder/android/kernel/kernel_pixel_muzel/common/ack
/home/builder/android/kernel/kernel_pixel_muzel/common
```

The build script runs this directory when:

```bash
ROOT=ksunext KSUNEXT_SUSFS=1 SUSFS_PATCH_KERNEL=1
```

You can override the upstream SUSFS source if needed:

```bash
SUSFS_REPO_URL=https://gitlab.com/simonpunk/susfs4ksu.git \
SUSFS_BRANCH=gki-android15-6.6 \
ROOT=ksunext \
KSUNEXT_SUSFS=1 \
bash /root/wizeos/wizeos.sh
```

SUSFS also needs the matching KernelSU userspace/module zip after boot. WizeOS bundles `SUSFS_MODULE_ZIP` into the release folder when `SUSFS_BUNDLE_MODULE=1`; it does not auto-install the module into `/data/adb/modules`.
