@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_deeplivecam_obs.ps1"
if errorlevel 1 pause

