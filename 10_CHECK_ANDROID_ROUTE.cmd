@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_android_emulator_test.ps1" -CheckOnly
if errorlevel 1 pause
