bash /root/wizeos.sh


scp C:\Users\wisso\Documents\MegaCloud\Android\wizeos.sh root@94.237.100.107:/root

printf '%s' 'YOUR_RELEASEKEY_PASSWORD_HERE' > /root/wizeos-secrets/ota.pass
chmod 600 /root/wizeos-secrets/ota.pass

CLEAN_OUT=0 SIGNED=1 ROOT=none bash wizeos.sh
CLEAN_OUT=0 SIGNED=1 ROOT=magisk MAGISK_APK=/root/Magisk.apk bash wizeos.sh