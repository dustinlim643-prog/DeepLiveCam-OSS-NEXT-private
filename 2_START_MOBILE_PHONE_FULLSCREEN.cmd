@echo off
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\mobile_phone\start_mobile_phone.ps1" -Mode low_latency
if errorlevel 1 pause
