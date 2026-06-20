@echo off
setlocal enabledelayedexpansion

:: Check if the server parameter was provided
if "%~1"=="" (
    echo Error: Missing server parameter.
    echo Usage: start.cmd [myserver]
    exit /b 1
)

set "SERVER=%~1"

echo.
echo === [1/2] Copying required files to root@%SERVER%:/root... ===
echo.

:: Copy the build entrypoint and its split builder runner.
scp -r wizeos*.sh "root@%SERVER%:/root"
scp -r Magisk.apk "root@%SERVER%:/root"
scp -r keys "root@%SERVER%:/root"
scp -r patches "root@%SERVER%:/root"

:: Check if the scp command succeeded
if %ERRORLEVEL% equ 0 (
    echo.
    echo === [2/2] Copy successful. Connecting via SSH... ===
    echo.
    ssh "root@%SERVER%"
) else (
    echo.
    echo Error: File transfer failed. SSH connection aborted.
    exit /b %ERRORLEVEL%
)

endlocal
