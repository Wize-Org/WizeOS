@echo off
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Error: Missing server parameter.
    echo Usage: start.cmd [server]
    exit /b 1
)

set "SERVER=%~1"

echo.
echo === [1/2] Copying files to root@%SERVER%:/root... ===
echo.

scp -r wizeos.sh "root@%SERVER%:/root/"
if errorlevel 1 exit /b %ERRORLEVEL%

scp -r upload.sh "root@%SERVER%:/root/"
if errorlevel 1 exit /b %ERRORLEVEL%

scp -r decrypt-keys.sh "root@%SERVER%:/root/"
if errorlevel 1 exit /b %ERRORLEVEL%

scp -r Magisk.apk "root@%SERVER%:/root/"
if errorlevel 1 exit /b %ERRORLEVEL%

scp -r keys "root@%SERVER%:/root/"
if errorlevel 1 exit /b %ERRORLEVEL%

if exist patches\ (
    scp -r patches "root@%SERVER%:/root/"
    if errorlevel 1 exit /b %ERRORLEVEL%
)

echo.
echo === [2/2] Copy successful. Connecting to server... ===
echo.

ssh -t "root@%SERVER%" "apt-get update >/dev/null 2>&1; apt-get install -y dos2unix >/dev/null 2>&1; dos2unix /root/wizeos.sh /root/decrypt-keys.sh; chmod 0700 /root/wizeos.sh /root/decrypt-keys.sh; cd /root; exec bash -l"

endlocal
