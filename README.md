# WizeOS modular build scripts

WizeOS is a modular build wrapper for building a GrapheneOS-based ROM for Pixel 10 Pro XL / `mustang`.

The scripts split the old single `wizeos.sh` workflow into smaller components for source sync, kernel integration, signing keys, release generation, root integration, and upload.

## Layout

```text
wizeos.sh                       main entrypoint
config/defaults.env             shared defaults
config/mustang.env              device defaults
lib/common.sh                   logging, validation, profile/manifest defaults
lib/host_setup.sh               apt packages, Node.js, Yarn, builder user, git config
lib/workspace.sh                START_OVER, workspace handling, builder-readable patches
lib/keys.sh                     signing keys and release SSH metadata key
lib/avbroot.sh                  avbroot auto-install
lib/magisk.sh                   Magisk/avbroot input preparation
lib/ksunext.sh                  KernelSU Next input preparation
lib/builder.sh                  root-to-builder handoff
scripts/run-as-builder.sh       repo sync, kernel build, OS build, release, OTA generation, root patching
scripts/upload.sh               FTP upload with old release archive
patches/profiles/               optional profile-specific local patches
patches/lsposed-compat/         optional local LSPosed compatibility patches
patches/kernel/ksunext/         optional KernelSU Next patch-mode patches
patches/kernel/susfs/           SUSFS kernel patches
```

## Build profiles

Use `WIZEOS_PROFILE` to choose how close the build should stay to GrapheneOS defaults.

```bash
WIZEOS_PROFILE=secure
WIZEOS_PROFILE=balanced
WIZEOS_PROFILE=flexible
```

Profile behavior:

```text
secure    GrapheneOS base + WizeOS Updater server override
balanced  secure + WizeOS frameworks/base compatibility defaults
flexible  balanced + dedicated 17-flexible branches for compatibility-first work
```

When `USE_WIZEOS_MANIFEST=1` and `MANIFEST_FILE` is not set, the script selects the profile manifest automatically:

```text
secure    -> wizeos-secure.xml
balanced  -> wizeos-balanced.xml
flexible  -> wizeos-flexible.xml
```

Do not pass `MANIFEST_FILE=wizeos.xml` when you want automatic profile selection. `wizeos.xml` is the legacy/manual override manifest.

## Flexible profile

`WIZEOS_PROFILE=flexible` points selected projects to `17-flexible` branches:

```text
platform_frameworks_base
platform_system_sepolicy
platform_art
platform_bionic
platform_system_core
```

Flexible is intended for AOSP/LineageOS-like compatibility behavior while keeping the GrapheneOS device/build base. SELinux should remain enforcing. Avoid global permissive policy and avoid broad `untrusted_app` property-service access.

## Pixel 10 Pro XL / mustang kernel phase

For `mustang`, GrapheneOS uses the `kernel_pixel_muzel` tree and kernel codename `muzel`. The script can clone/build that kernel separately and copy the resulting prebuilts into the OS tree before building the OTA.

```bash
KERNEL_REPO_URL=https://gitlab.com/grapheneos/kernel_pixel_muzel.git
KERNEL_REPO_BRANCH=17
KERNEL_CODENAME=muzel
KERNEL_WORKDIR=/home/builder/android/kernel/kernel_pixel_muzel
KERNEL_OS_PREBUILT_DIR=device/google/laguna-kernels/6.6/grapheneos/muzel
```

## Supported root modes

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

## Full Magisk Flexible build

```bash
TAG=2026062800 \
ACTION=all \
USE_WIZEOS_MANIFEST=1 \
WIZEOS_PROFILE=flexible \
MANIFEST_BRANCH=17 \
START_OVER=1 \
CLEAN_OUT=1 \
SIGNED=1 \
ROOT=magisk \
MAGISK_APK=/root/Magisk.apk \
MAGISK_PREINIT_DEVICE=metadata \
LSPOSED_COMPAT=1 \
bash /root/wizeos/wizeos.sh
```

Expected rooted release file:

```text
releases/2026062800/release-mustang-2026062800/mustang-ota_update-2026062800-magisk.zip
```

The script now generates a full OTA from `mustang-target_files.zip` and `mustang-otatools.zip` when `mustang-ota_update-*.zip` is missing, then patches that OTA with Magisk.

## Full KernelSU Next build

```bash
TAG=2026062800 \
ACTION=all \
USE_WIZEOS_MANIFEST=1 \
WIZEOS_PROFILE=balanced \
MANIFEST_BRANCH=17 \
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
WIZEOS_PROFILE=flexible \
MANIFEST_BRANCH=17 \
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

## Build actions

```text
ACTION=sync      repo init/sync only
ACTION=kernel    kernel build/copy only
ACTION=build     OS build/finalize only
ACTION=release   release finalization only
ACTION=magisk    patch existing or generated OTA with Magisk
ACTION=ksunext   copy KernelSU release artifacts only
ACTION=all       full flow
```

## Signing keys

Local builds expect signing keys under the workdir, usually:

```text
/home/builder/android/grapheneos-<TAG>/keys/mustang
```

or copied in through `KEYS_SOURCE` / `/root/keys` depending on your environment.

Typical key files:

```text
avb.pem
avb_pkmd.bin
platform.pk8
platform.x509.pem
releasekey.pk8
releasekey.x509.pem
media.pk8
media.x509.pem
shared.pk8
shared.x509.pem
networkstack.pk8
networkstack.x509.pem
sdk_sandbox.pk8
sdk_sandbox.x509.pem
bluetooth.pk8
bluetooth.x509.pem
nfc.pk8
nfc.x509.pem
gmscompat_lib.pk8
gmscompat_lib.x509.pem
id_ed25519
id_ed25519.pub
```

### GitHub Actions signing secrets

GitHub Secrets are always encrypted by GitHub at rest. For Actions builds, store the actual secret values as decrypted signing material:

```text
KEY_AVB_PEM                         decrypted avb.pem text
KEY_AVB_PKMD_BIN_B64                base64 avb_pkmd.bin
KEY_PLATFORM_PK8_B64                base64 decrypted DER PKCS#8
KEY_PLATFORM_X509_PEM               certificate text
KEY_RELEASEKEY_PK8_B64              base64 decrypted DER PKCS#8
KEY_RELEASEKEY_X509_PEM             certificate text
KEY_MEDIA_PK8_B64                   base64 decrypted DER PKCS#8
KEY_MEDIA_X509_PEM                  certificate text
KEY_SHARED_PK8_B64                  base64 decrypted DER PKCS#8
KEY_SHARED_X509_PEM                 certificate text
KEY_NETWORKSTACK_PK8_B64            base64 decrypted DER PKCS#8
KEY_NETWORKSTACK_X509_PEM           certificate text
KEY_SDK_SANDBOX_PK8_B64             base64 decrypted DER PKCS#8
KEY_SDK_SANDBOX_X509_PEM            certificate text
KEY_BLUETOOTH_PK8_B64               base64 decrypted DER PKCS#8
KEY_BLUETOOTH_X509_PEM              certificate text
KEY_NFC_PK8_B64                     base64 decrypted DER PKCS#8
KEY_NFC_X509_PEM                    certificate text
KEY_GMSCOMPAT_LIB_PK8_B64           base64 decrypted DER PKCS#8
KEY_GMSCOMPAT_LIB_X509_PEM          certificate text
KEY_ID_ED25519                      release metadata SSH private key
KEY_ID_ED25519_PUB                  release metadata SSH public key
```

Restore them in a workflow before running `wizeos.sh`:

```yaml
- name: Restore signing keys from secrets
  shell: bash
  run: |
    mkdir -p keys/mustang
    chmod 700 keys keys/mustang

    printf '%s' "${{ secrets.KEY_AVB_PEM }}" > keys/mustang/avb.pem
    printf '%s' "${{ secrets.KEY_AVB_PKMD_BIN_B64 }}" | base64 -d > keys/mustang/avb_pkmd.bin

    printf '%s' "${{ secrets.KEY_PLATFORM_PK8_B64 }}" | base64 -d > keys/mustang/platform.pk8
    printf '%s' "${{ secrets.KEY_PLATFORM_X509_PEM }}" > keys/mustang/platform.x509.pem

    printf '%s' "${{ secrets.KEY_RELEASEKEY_PK8_B64 }}" | base64 -d > keys/mustang/releasekey.pk8
    printf '%s' "${{ secrets.KEY_RELEASEKEY_X509_PEM }}" > keys/mustang/releasekey.x509.pem

    printf '%s' "${{ secrets.KEY_MEDIA_PK8_B64 }}" | base64 -d > keys/mustang/media.pk8
    printf '%s' "${{ secrets.KEY_MEDIA_X509_PEM }}" > keys/mustang/media.x509.pem

    printf '%s' "${{ secrets.KEY_SHARED_PK8_B64 }}" | base64 -d > keys/mustang/shared.pk8
    printf '%s' "${{ secrets.KEY_SHARED_X509_PEM }}" > keys/mustang/shared.x509.pem

    printf '%s' "${{ secrets.KEY_NETWORKSTACK_PK8_B64 }}" | base64 -d > keys/mustang/networkstack.pk8
    printf '%s' "${{ secrets.KEY_NETWORKSTACK_X509_PEM }}" > keys/mustang/networkstack.x509.pem

    printf '%s' "${{ secrets.KEY_SDK_SANDBOX_PK8_B64 }}" | base64 -d > keys/mustang/sdk_sandbox.pk8
    printf '%s' "${{ secrets.KEY_SDK_SANDBOX_X509_PEM }}" > keys/mustang/sdk_sandbox.x509.pem

    printf '%s' "${{ secrets.KEY_BLUETOOTH_PK8_B64 }}" | base64 -d > keys/mustang/bluetooth.pk8
    printf '%s' "${{ secrets.KEY_BLUETOOTH_X509_PEM }}" > keys/mustang/bluetooth.x509.pem

    printf '%s' "${{ secrets.KEY_NFC_PK8_B64 }}" | base64 -d > keys/mustang/nfc.pk8
    printf '%s' "${{ secrets.KEY_NFC_X509_PEM }}" > keys/mustang/nfc.x509.pem

    printf '%s' "${{ secrets.KEY_GMSCOMPAT_LIB_PK8_B64 }}" | base64 -d > keys/mustang/gmscompat_lib.pk8
    printf '%s' "${{ secrets.KEY_GMSCOMPAT_LIB_X509_PEM }}" > keys/mustang/gmscompat_lib.x509.pem

    printf '%s' "${{ secrets.KEY_ID_ED25519 }}" > keys/mustang/id_ed25519
    printf '%s' "${{ secrets.KEY_ID_ED25519_PUB }}" > keys/mustang/id_ed25519.pub

    chmod 600 keys/mustang/*.pk8 keys/mustang/avb.pem keys/mustang/id_ed25519
    chmod 644 keys/mustang/*.x509.pem keys/mustang/id_ed25519.pub
```

## Upload rooted OTA through System Updater

```bash
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=magisk bash /root/wizeos/scripts/upload.sh
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=ksunext bash /root/wizeos/scripts/upload.sh
FTP_PASSWORD='your-password' TAG=2026062800 CHANNEL=stable PUBLISH_ROOT_AS_NORMAL=ksunext-susfs bash /root/wizeos/scripts/upload.sh
```

The old `PUBLISH_MAGISK_AS_NORMAL=1` flag still works and maps to `PUBLISH_ROOT_AS_NORMAL=magisk`.

## tmux helper

Create session:

```bash
tmux new -s work
```

Attach session:

```bash
tmux attach -t work
```
