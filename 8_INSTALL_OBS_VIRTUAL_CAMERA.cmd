@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_obs_virtual_camera.ps1"
if errorlevel 1 pause
