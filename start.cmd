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
echo === [1/2] Copying current folder to root@%SERVER%:/root... ===
echo.

:: Run scp -r on the current directory (.)
scp -r . "root@%SERVER%:/root"

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