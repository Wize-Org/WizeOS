bash /root/wizeos.sh


scp C:\Users\wisso\Documents\MegaCloud\Android\wizeos.sh root@94.237.100.107:/root

printf '%s' 'YOUR_RELEASEKEY_PASSWORD_HERE' > /root/wizeos-secrets/ota.pass
chmod 600 /root/wizeos-secrets/ota.pass

CLEAN_OUT=0 SIGNED=1 ROOT=none bash wizeos.sh
CLEAN_OUT=0 SIGNED=1 ROOT=magisk MAGISK_APK=/root/Magisk.apk bash wizeos.sh


TAG=2026060600 \
USE_WIZEOS_MANIFEST=0 \
START_OVER=1 \
CLEAN_OUT=1 \
SIGNED=1 \
ROOT=magisk \
MAGISK_APK=/root/Magisk.apk \
MAGISK_PREINIT_DEVICE=metadata \
DECRYPT_KEYS=1 \
bash /root/wizeos.sh

dos2unix /root/wizeos.sh

ssh root@123.123.123.123
tmux new -s work

ssh root@123.123.123.123
tmux attach -t work

db sideload mustang-ota_update-2026060600-magisk.zip

Update server:
mustang-ota_update-2026061800.zip
mustang-testing
mustang-beta
mustang-stable
mustang-install-2026061800.zip
mustang-install-2026061800.zip.sig
mustang-factory-2026061800.zip
mustang-img-2026061800.zip   # optional, not needed for OTA
