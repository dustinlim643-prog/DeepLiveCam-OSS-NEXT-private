@echo off
set "ROOT=%~dp0"
set "SCENE=%ROOT%obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json"
set "OBS_EXE=%ROOT%obs-studio\bin\64bit\obs64.exe"
set "OBS_DIR=%ROOT%obs-studio\bin\64bit"

cd /d "%ROOT%"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=$env:SCENE; $j=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; foreach($s in $j.sources){ if($s.name -eq 'DeepLiveCam Live Preview'){ $s.settings.window='Live Preview:Qt625QWindowIcon:python.exe'; $s.settings.method=2; $s.settings.client_area=$true; $s.settings.cursor=$false }; if($s.id -eq 'scene' -and $s.name -eq 'DeepLiveCam'){ foreach($i in $s.settings.items){ if($i.name -eq 'DeepLiveCam Live Preview'){ $i.pos.x=0.0; $i.pos.y=0.0; $i.scale.x=1.0; $i.scale.y=1.0; $i.bounds.x=1280.0; $i.bounds.y=720.0; $i.scale_ref.x=1280.0; $i.scale_ref.y=720.0; $i.scale_filter='lanczos' } } } }; $j.resolution.x=1280; $j.resolution.y=720; $j | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $p -Encoding UTF8"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -like ($env:ROOT + '*') } | Stop-Process -Force -ErrorAction SilentlyContinue"
timeout /t 2 /nobreak >nul
start "" /D "%OBS_DIR%" "%OBS_EXE%" --portable --collection "DeepLiveCam" --scene "DeepLiveCam" --startvirtualcam

echo OBS capture reset to Live Preview.
echo If OBS is still blank, make sure DeepLiveCam has already opened the Live Preview window.
pause
