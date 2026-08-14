@echo off
set "ROOT=%~dp0"
cd /d "%ROOT%"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -LiteralPath ($env:ROOT + 'logs\operation_log.txt') -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' stop requested')"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process python,pythonw -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($env:ROOT + '*') } | Stop-Process -Force -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$obs = Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue; foreach ($p in $obs) { $null = $p.CloseMainWindow() }; Start-Sleep -Seconds 5; Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -LiteralPath ($env:ROOT + 'obs-studio\config\obs-studio\.sentinel') -Recurse -Force -ErrorAction SilentlyContinue"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -LiteralPath ($env:ROOT + 'logs\operation_log.txt') -Encoding UTF8 -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' DeepLiveCam and OBS stopped')"
echo Done.
