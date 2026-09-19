@echo off
setlocal
chcp 65001 >nul

:menu
cls
echo DeepLiveCam New Device Setup
echo.
echo 1. Install OBS Virtual Camera
echo 2. Install and verify Android WhatsApp x86_64 package
echo 0. Exit
echo.
choice /C 120 /N /M "Select: "
set "selection=%errorlevel%"

if "%selection%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_obs_virtual_camera.ps1"
if "%selection%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_android_whatsapp.ps1"
if "%selection%"=="3" exit /b 0

echo.
pause
goto menu
