@echo off
setlocal
chcp 65001 >nul

:menu
cls
echo DeepLiveCam New Device Setup
echo.
echo 1. Install OBS Virtual Camera
echo 0. Exit
echo.
choice /C 10 /N /M "Select: "
set "selection=%errorlevel%"

if "%selection%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\install_obs_virtual_camera.ps1"
if "%selection%"=="2" exit /b 0

echo.
pause
goto menu
