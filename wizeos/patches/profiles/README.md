# WizeOS profile patches

Profile-specific source patches can be placed in these folders:

```text
secure/
balanced/
flexible/
```

Only files ending in `.patch` or `.diff` are applied.

The build script chooses a manifest from `WIZEOS_PROFILE` when `USE_WIZEOS_MANIFEST=1` and `MANIFEST_FILE` is not set:

```text
secure    -> wizeos-secure.xml
balanced  -> wizeos-balanced.xml
flexible  -> wizeos-flexible.xml
```

The default profile is `balanced`.
