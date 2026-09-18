@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_android_emulator_test.ps1"
if errorlevel 1 pause
