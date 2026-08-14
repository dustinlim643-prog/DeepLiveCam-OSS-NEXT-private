@echo off
set "ROOT=%~dp0"
cd /d "%ROOT%"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"
set "REPORT=%ROOT%logs\production_check.txt"

echo DeepLiveCam production check > "%REPORT%"
echo Time: %date% %time% >> "%REPORT%"
echo Root: %ROOT% >> "%REPORT%"
echo. >> "%REPORT%"

if exist "%ROOT%python\python.exe" (
    echo OK python runtime >> "%REPORT%"
) else (
    echo ERROR missing python runtime: %ROOT%python\python.exe >> "%REPORT%"
)

if exist "%ROOT%obs-studio\bin\64bit\obs64.exe" (
    echo OK bundled OBS >> "%REPORT%"
) else (
    echo ERROR missing bundled OBS: %ROOT%obs-studio\bin\64bit\obs64.exe >> "%REPORT%"
)

if exist "%ROOT%obs-studio\portable_mode.txt" (
    echo OK OBS portable mode marker >> "%REPORT%"
) else (
    echo ERROR missing OBS portable_mode.txt >> "%REPORT%"
)

if exist "%ROOT%source_faces\current_source.jpg" (
    echo OK source face >> "%REPORT%"
) else (
    echo ERROR missing source face: %ROOT%source_faces\current_source.jpg >> "%REPORT%"
)

if exist "%ROOT%models\inswapper_128.onnx" (
    echo OK inswapper model >> "%REPORT%"
) else (
    echo ERROR missing model: %ROOT%models\inswapper_128.onnx >> "%REPORT%"
)

where nvidia-smi >nul 2>nul
if errorlevel 1 (
    echo WARN nvidia-smi not found. NVIDIA driver may be missing. >> "%REPORT%"
) else (
    echo OK nvidia-smi found >> "%REPORT%"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader >> "%REPORT%" 2>&1
)

if exist "%ROOT%ffmpeg\bin\ffmpeg.exe" (
    "%ROOT%ffmpeg\bin\ffmpeg.exe" -list_devices true -f dshow -i dummy > "%ROOT%logs\dshow_devices.txt" 2>&1
    findstr /I /C:"OBS Virtual Camera" "%ROOT%logs\dshow_devices.txt" >nul
    if errorlevel 1 (
        echo WARN OBS Virtual Camera not found in DirectShow devices. Install/register OBS Virtual Camera on this computer if video apps cannot see it. >> "%REPORT%"
    ) else (
        echo OK OBS Virtual Camera found in DirectShow devices >> "%REPORT%"
    )
) else (
    echo WARN ffmpeg not found, cannot check DirectShow devices >> "%REPORT%"
)

"%ROOT%python\python.exe" -c "import cv2; cap=cv2.VideoCapture(0, cv2.CAP_DSHOW); print('OK camera 0 opened' if cap.isOpened() else 'WARN camera 0 not opened'); cap.release()" >> "%REPORT%" 2>&1

type "%REPORT%"
pause
