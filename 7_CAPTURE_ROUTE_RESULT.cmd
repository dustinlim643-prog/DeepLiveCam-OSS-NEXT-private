@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\capture_route_result.ps1" -Seconds 30
if errorlevel 1 pause
