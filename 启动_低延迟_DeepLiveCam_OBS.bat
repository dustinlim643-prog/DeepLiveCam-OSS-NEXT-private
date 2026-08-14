@echo off
set "ROOT=%~dp0"
set "OBS_EXE=%ROOT%obs-studio\bin\64bit\obs64.exe"
set "OBS_DIR=%ROOT%obs-studio\bin\64bit"

cd /d "%ROOT%"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"

set "PATH=%ROOT%ffmpeg\bin;%ROOT%python;%ROOT%python\Scripts;%PATH%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -LiteralPath ($env:ROOT + 'logs\operation_log.txt') -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' start LOW LATENCY UI + OBS requested')"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process python,pythonw -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($env:ROOT + '*') } | Stop-Process -Force -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath ($env:ROOT + 'obs-studio\config\obs-studio\.sentinel') -Recurse -Force -ErrorAction SilentlyContinue"

if not exist "%ROOT%python\python.exe" (
    echo Python runtime not found: %ROOT%python\python.exe
    pause
    exit /b 1
)

if not exist "%ROOT%ffmpeg\bin\ffmpeg.exe" (
    echo ffmpeg not found: %ROOT%ffmpeg\bin\ffmpeg.exe
    pause
    exit /b 1
)

start "DeepLiveCam UI Low Latency" "%ROOT%python\python.exe" "%ROOT%run.py" --execution-provider cuda --execution-threads 2 --frame-processor face_swapper --live-resizable --live-fps-debug --similar-face-distance 1.5 --quality-preset low_latency -l zh
timeout /t 5 /nobreak >nul

if exist "%OBS_EXE%" (
    start "" /D "%OBS_DIR%" "%OBS_EXE%" --portable --collection "DeepLiveCam" --scene "DeepLiveCam" --startvirtualcam
) else (
    echo OBS not found: %OBS_EXE%
    pause
    exit /b 1
)
