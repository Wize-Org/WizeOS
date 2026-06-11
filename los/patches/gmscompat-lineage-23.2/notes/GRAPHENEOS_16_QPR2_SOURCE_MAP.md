# GrapheneOS 16-qpr2 source map for the fresh GmsCompat port

Use these repositories as the source of truth for the modern implementation:

- `GrapheneOS/platform_packages_apps_GmsCompat` branch `16-qpr2`
- `GrapheneOS/platform_external_GmsCompatConfig` branch `16-qpr2`
- `GrapheneOS/platform_libcore` branch `16-qpr2`
- `GrapheneOS/platform_bionic` branch `16-qpr2`
- `GrapheneOS/platform_packages_apps_Settings` branch `16-qpr2`
- module repos where framework APIs moved out of `frameworks/base`, especially:
  - `platform_packages_modules_ConfigInfrastructure`
  - `platform_packages_modules_Permission`
  - `platform_packages_modules_Wifi`
  - `platform_frameworks_opt_telephony`

## Current high-value files to inspect

### GmsCompat app/lib/config

- `packages/apps/GmsCompat/gmscompat_config`
- `packages/apps/GmsCompat/AndroidManifest.xml`
- `packages/apps/GmsCompat/etc/sysconfig/app.grapheneos.gmscompat.xml`
- `packages/apps/GmsCompat/etc/default-permissions/app.grapheneos.gmscompat.xml`
- `packages/apps/GmsCompat/lib/src/app/grapheneos/gmscompat/lib/GmsCompatLibImpl.java`
- `packages/apps/GmsCompat/lib/src/app/grapheneos/gmscompat/lib/sysservice/client/GclPackageManager.java`
- `packages/apps/GmsCompat/src/app/grapheneos/gmscompat/PersistentFgService.java`
- `packages/apps/GmsCompat/src/app/grapheneos/gmscompat/Notifications.kt`

### Platform-side hooks to compare

- `platform_libcore/dalvik/src/main/java/dalvik/system/DelegateLastClassLoader.java`
- `platform_libcore/dalvik/src/main/java/dalvik/system/DexPathList.java`
- `platform_libcore/ojluni/src/main/native/UnixFileSystem_md.c`
- `platform_libcore/ojluni/src/main/native/UnixNativeDispatcher.c`
- `platform_bionic/linker/linker.cpp`
- `platform_art/runtime/hidden_api.cc`
- `platform_packages_modules_ConfigInfrastructure/framework/java/android/provider/DeviceConfig.java`
- `platform_frameworks_opt_telephony/src/java/com/android/internal/telephony/InboundSmsHandlerExt.java`

## Porting rule

Prefer copying the modern GrapheneOS behavior into the corresponding LineageOS 23.2 project over refreshing old Android 11 hunks. Many APIs moved from `frameworks/base` into module repositories after Android 11.
