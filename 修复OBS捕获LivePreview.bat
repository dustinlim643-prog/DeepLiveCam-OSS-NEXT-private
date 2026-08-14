@echo off
set "ROOT=%~dp0"
set "SCENE=%ROOT%obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json"
set "OBS_EXE=%ROOT%obs-studio\bin\64bit\obs64.exe"
set "OBS_DIR=%ROOT%obs-studio\bin\64bit"

cd /d "%ROOT%"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\reset_obs_scene.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($env:ROOT + '*') } | Stop-Process -Force -ErrorAction SilentlyContinue"
timeout /t 2 /nobreak >nul
start "" /D "%OBS_DIR%" "%OBS_EXE%" --portable --collection "DeepLiveCam" --scene "DeepLiveCam" --startvirtualcam

echo OBS capture reset to Live Preview.
echo If OBS is still blank, make sure DeepLiveCam has already opened the Live Preview window.
pause
