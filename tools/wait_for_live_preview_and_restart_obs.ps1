$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogPath = Join-Path $Root "logs\operation_log.txt"
$ObsExe = Join-Path $Root "obs-studio\bin\64bit\obs64.exe"
$ObsDir = Join-Path $Root "obs-studio\bin\64bit"
$ResetScript = Join-Path $Root "tools\reset_obs_scene.ps1"

if (!(Test-Path -LiteralPath (Split-Path $LogPath))) {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) | Out-Null
}

function Write-OpLog($Text) {
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $Text)
}

Write-OpLog "OBS watcher waiting for Live Preview"

$deadline = (Get-Date).AddMinutes(10)
$seen = $false
while ((Get-Date) -lt $deadline) {
    $livePreview = Get-Process python,pythonw -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -like ($Root + "*") -and
            $_.MainWindowTitle -eq "Live Preview"
        } |
        Select-Object -First 1

    if ($livePreview) {
        $seen = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (!$seen) {
    Write-OpLog "OBS watcher timeout: Live Preview was not detected"
    exit 0
}

Write-OpLog "OBS watcher detected Live Preview, refreshing OBS capture"

Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like ($Root + "*") } |
    ForEach-Object {
        $null = $_.CloseMainWindow()
    }
Start-Sleep -Seconds 3
Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like ($Root + "*") } |
    Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item -LiteralPath (Join-Path $Root "obs-studio\config\obs-studio\.sentinel") -Recurse -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $ResetScript | Out-Null

if (Test-Path -LiteralPath $ObsExe) {
    Start-Process -FilePath $ObsExe -WorkingDirectory $ObsDir -ArgumentList @("--portable", "--collection", "DeepLiveCam", "--scene", "DeepLiveCam", "--startvirtualcam") -WindowStyle Hidden
    Write-OpLog "OBS watcher restarted OBS after Live Preview appeared"
}
