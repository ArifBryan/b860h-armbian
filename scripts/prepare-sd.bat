@echo off
rem Prepare a freshly flashed Armbian SD card for the ZTE B860H (see prepare-sd.ps1 for details).
rem   prepare-sd.bat                  finds the card's BOOT drive by itself (just double-click)
rem   prepare-sd.bat E:               use this drive
rem   prepare-sd.bat E: -SmallUboot   use the 646 KB u-boot.ext instead of the HG680P image
rem   prepare-sd.bat -SmallUboot      same, with the drive found automatically
rem (extlinux.conf is edited by PowerShell on purpose: plain batch would rewrite it with CRLF line
rem  endings, which U-Boot's extlinux parser may not accept.)
setlocal
set "A1=%~1"
set "ARGS=%~2"
if not defined A1 goto run
if "%A1:~0,1%"=="-" goto sw
if "%A1:~-1%"=="\" set "A1=%A1:~0,-1%"
set ARGS=-Drive "%A1%" %~2
goto run
:sw
set ARGS=%A1% %~2
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-sd.ps1" %ARGS%
if errorlevel 1 echo. & echo FAILED, see the message above.
echo.
pause
