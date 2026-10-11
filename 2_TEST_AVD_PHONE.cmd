@echo off
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\test_android_avd_phone.ps1" %*
if errorlevel 1 pause
