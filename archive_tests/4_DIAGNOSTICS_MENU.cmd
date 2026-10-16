@echo off
setlocal
chcp 65001 >nul

:menu
cls
echo DeepLiveCam Diagnostics
echo.
echo 1. Diagnose Desktop WhatsApp route
echo 2. Capture stability snapshot
echo 3. Capture 30-second performance report
echo 4. Show recent health log
echo 0. Exit
echo.
choice /C 12340 /N /M "Select: "
set "selection=%errorlevel%"

if "%selection%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\diagnose_whatsapp_video.ps1"
if "%selection%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\capture_stability_snapshot.ps1"
if "%selection%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\capture_route_result.ps1" -Seconds 30
if "%selection%"=="4" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\show_recent_health.ps1"
if "%selection%"=="5" exit /b 0

echo.
pause
goto menu
