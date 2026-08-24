@echo off
chcp 65001 >nul
cd /d "%~dp0"
"%~dp0python\python.exe" "%~dp0tools\test_camera_capture.py" --camera-name "4k Camera" --width 1280 --height 720 --fps 30 --seconds 8
pause
