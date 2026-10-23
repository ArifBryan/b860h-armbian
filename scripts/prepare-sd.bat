@echo off
rem Prepare a freshly flashed Armbian SD card for the ZTE B860H (see prepare-sd.ps1 for details).
rem   prepare-sd.bat E:            BOOT drive letter of the SD card
rem   prepare-sd.bat E: -SmallUboot   use the 646 KB u-boot.ext instead of the HG680P image
rem Double-click it to be asked for the drive letter.
rem (extlinux.conf is edited by PowerShell on purpose: plain batch would rewrite it with CRLF line
rem  endings, which U-Boot's extlinux parser may not accept.)
setlocal
set "DRIVE=%~1"
if "%DRIVE%"=="" set /p "DRIVE=BOOT drive letter of the SD card (for example E): "
if "%DRIVE:~-1%"=="\" set "DRIVE=%DRIVE:~0,-1%"
if "%DRIVE:~1%"=="" set "DRIVE=%DRIVE%:"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-sd.ps1" -Drive "%DRIVE%" %2
if errorlevel 1 echo. & echo FAILED, see the message above.
echo.
pause
