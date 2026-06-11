# Porting status

## Keep from the old lineage-gmscompat patch queue as checklist only

- `bionic/0001`: keep and refresh first.
- `libcore/0001`: keep and refresh first.
- `libcore/0002`: split into smaller classloader hook patches.
- `frameworks/base/0001`: replace with a fresh framework scaffold.
- `frameworks/base/0002`: rewrite for current `CompatChange` APIs.
- `frameworks/base/0008`: split into per-service hook patches.
- `frameworks/base/0019`: rewrite Dynamite around current GrapheneOS 16-qpr2 design.
- `frameworks/base/0029`: rewrite AppOps proxy behavior around current AppOpsManager APIs.

## Do not port blindly

- Foreground service notification behavior changed significantly after Android 11.
- Package visibility and install session behavior changed significantly after Android 11.
- Play Integrity handling should follow modern GrapheneOS GmsCompat app/lib code, not the old dummy implementation.
- DeviceConfig, DropBox, IMEI, and telephony stubs need privacy and compatibility review before enabling.

## Next concrete work items

1. Add a local manifest/project integration for GrapheneOS GmsCompat.
2. Run `git apply --check` for the bionic and libcore patches against the exact synced tree.
3. Compare GrapheneOS 16-qpr2 platform framework changes against LineageOS 23.2.
4. Replace the framework scaffold with a real package/signature/CompatChange implementation.
5. Add tests/logcat checklist for Play Store login, FCM, Maps/Dynamite, Play Integrity behavior, and app ops proxy behavior.
