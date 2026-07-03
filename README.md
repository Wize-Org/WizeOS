# WizeOS modular build scripts

This package splits the old single `wizeos.sh` into smaller files.

## Layout

```text
wizeos.sh                 main entrypoint
config/defaults.env       shared defaults
config/mustang.env        device defaults
lib/common.sh             logging, validation, config
lib/host_setup.sh         apt packages, Node.js, Yarn, builder user, git config
lib/workspace.sh          START_OVER, workspace handling, builder-readable patches
lib/keys.sh               keys and release SSH metadata key
lib/avbroot.sh            avbroot auto-install
lib/magisk.sh             Magisk/avbroot input preparation
lib/ksunext.sh            KernelSU Next input preparation
lib/builder.sh            root-to-builder handoff
scripts/run-as-builder.sh repo sync, kernel build, OS build, release, rooted OTA marking
scripts/upload.sh         FTP upload with old release archive
patches/lsposed-compat/   optional local LSPosed compatibility patches
patches/kernel/ksunext/   optional KernelSU Next patch-mode patches
patches/kernel/susfs/     SUSFS kernel patches
```

## Kernel phase for Pixel 10 / mustang

For `mustang`, GrapheneOS uses the `kernel_pixel_muzel` tree and kernel codename `muzel`. The script can clone/build that kernel separately and copy the resulting prebuilts into the OS tree before building the OTA.

```bash
KERNEL_REPO_URL=https://gitlab.com/grapheneos/kernel_pixel_muzel.git
KERNEL_REPO_BRANCH=17
KERNEL_CODENAME=muzel
KERNEL_WORKDIR=/home/builder/android/kernel/kernel_pixel_muzel
KERNEL_OS_PREBUILT_DIR=device/google/laguna-kernels/6.6/grapheneos/muzel
```

## Supported root modes

WizeOS supports only these root modes:

```bash
ROOT=none
ROOT=magisk
ROOT=ksunext
```

`ROOT=ksunext` means KernelSU Next only. `KSU_FLAVOR` is kept only as a deprecated compatibility variable and must remain `ksunext` if provided. WildKSU support was removed because the project is discontinued and its setup script is no longer reliable.

KernelSU Next has a default setup URL:

```bash
ROOT=ksunext
KSU_INTEGRATION=setup
KSU_SETUP_URL=
```

For fully offline/reproducible KernelSU Next builds, use patch mode and add `.patch` or `.diff` files under `wizeos/patches/kernel/ksunext/`:

```bash
KSU_INTEGRATION=patch
```

## Full KernelSU Next build

```bash
TAG=2026062800 \
ACTION=all \
USE_WIZEOS_MANIFEST=1 \
MANIFEST_BRANCH=17 \
MANIFEST_FILE=wizeos.xml \
START_OVER=1 \
CLEAN_OUT=1 \
SIGNED=1 \
ROOT=ksunext \
KSUNEXT_SUSFS=0 \
LSPOSED_COMPAT=1 \
bash /root/wizeos/wizeos.sh
```

Expected extra release files:

```text
mustang-ota_update-2026062800-ksunext.zip
KernelSU_Next.apk
Zygisk-Next.zip
```

## Full KernelSU Next + SUSFS build

SUSFS still needs matching kernel-side patches under `wizeos/patches/kernel/susfs/` unless `SUSFS_PATCH_KERNEL=0` is used.

```bash
TAG=2026062800 \
ACTION=all \
USE_WIZEOS_MANIFEST=1 \
MANIFEST_BRANCH=17 \
MANIFEST_FILE=wizeos.xml \
START_OVER=1 \
CLEAN_OUT=1 \
SIGNED=1 \
ROOT=ksunext \
KSUNEXT_SUSFS=1 \
SUSFS_MODULE_ZIP=/root/susfs4ksu.zip \
LSPOSED_COMPAT=1 \
bash /root/wizeos/wizeos.sh
```

Expected extra release files:

```text
mustang-ota_update-2026062800-ksunext-susfs.zip
KernelSU_Next.apk
Zygisk-Next.zip
susfs4ksu.zip
```

## Full Magisk build

```bash
TAG=2026062800 \
ACTION=all \
USE_WIZEOS_MANIFEST=1 \
MANIFEST_BRANCH=17 \
MANIFEST_FILE=wizeos.xml \
START_OVER=1 \
CLEAN_OUT=1 \
SIGNED=1 \
ROOT=magisk \
MAGISK_APK=/root/Magisk.apk \
MAGISK_PREINIT_DEVICE=metadata \
LSPOSED_COMPAT=1 \
bash /root/wizeos/wizeos.sh
```

## Upload rooted OTA through System Updater

```bash
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=magisk bash /root/wizeos/scripts/upload.sh
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=ksunext bash /root/wizeos/scripts/upload.sh
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=ksunext-susfs bash /root/wizeos/scripts/upload.sh
```

The old `PUBLISH_MAGISK_AS_NORMAL=1` flag still works and maps to `PUBLISH_ROOT_AS_NORMAL=magisk`.

## Create session
```text
tmux new -s work
```

## Attach session
```text
tmux attach -t work
```
