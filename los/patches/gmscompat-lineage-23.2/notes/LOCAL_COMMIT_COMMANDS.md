# Local commit commands

The GitHub integration returned 403 for repository writes, so commit locally:

```bash
git clone https://github.com/Wize-Org/WizeOS.git
cd WizeOS
mkdir -p patches
unzip /path/to/gmscompat-lineage-23.2-patch-queue-v2.zip -d patches
git add patches/gmscompat-lineage-23.2
git commit -m "Add GmsCompat LineageOS 23.2 patch queue"
git push origin main
```

For a feature branch instead:

```bash
git checkout -b gmscompat-lineage-23.2
mkdir -p patches
unzip /path/to/gmscompat-lineage-23.2-patch-queue-v2.zip -d patches
git add patches/gmscompat-lineage-23.2
git commit -m "Add GmsCompat LineageOS 23.2 patch queue"
git push -u origin gmscompat-lineage-23.2
```
