@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\capture_stability_snapshot.ps1" %*
pause
