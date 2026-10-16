@echo off
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\start_avd_phone_4x3.ps1" %*
if errorlevel 1 pause
