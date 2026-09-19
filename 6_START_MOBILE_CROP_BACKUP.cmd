@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_deeplivecam_obs.ps1" -Mode low_latency -OutputRoute Mobile
if errorlevel 1 pause
