@echo off
REM B test: raw 4k Camera -> OBS Output window -> OBS -> DroidCam Video -> WhatsApp.
REM This does not change DeepLiveCam model/settings. Stop with 2_STOP.cmd or close this window.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0obs-studio\bin\64bit\obs64.exe' -ArgumentList @('--portable','--collection','DeepLiveCam','--scene','DeepLiveCam') -WorkingDirectory '%~dp0obs-studio\bin\64bit'"
"%~dp0python\python.exe" "%~dp0tools\run_raw_camera_output.py" --camera "4k Camera" --width 1280 --height 720 --fps 30
pause
