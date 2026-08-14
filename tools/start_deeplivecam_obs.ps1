$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$ObsExe = Join-Path $Root "obs-studio\bin\64bit\obs64.exe"
$ObsDir = Join-Path $Root "obs-studio\bin\64bit"
$Python = Join-Path $Root "python\python.exe"
$RunPy = Join-Path $Root "run.py"
$ResetObs = Join-Path $Root "tools\reset_obs_scene.ps1"
$Watcher = Join-Path $Root "tools\wait_for_live_preview_and_restart_obs.ps1"

if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

function Add-OperationLog($Text) {
    Add-Content -LiteralPath (Join-Path $Logs "operation_log.txt") -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $Text)
}

function Stop-ProjectProcess($Names) {
    $needle = $Root.TrimEnd("\")
    Get-CimInstance Win32_Process | Where-Object {
        ($Names -contains $_.Name) -and ($_.CommandLine -like ("*" + $needle + "*"))
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Add-OperationLog "start UI + OBS requested"

$env:PATH = (Join-Path $Root "ffmpeg\bin") + ";" + (Join-Path $Root "python") + ";" + (Join-Path $Root "python\Scripts") + ";" + $env:PATH

Stop-ProjectProcess @("python.exe", "pythonw.exe")
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($Root.TrimEnd("\") + "*"))
} | ForEach-Object {
    $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    if ($p) {
        $null = $p.CloseMainWindow()
    }
}
Start-Sleep -Seconds 3
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($Root.TrimEnd("\") + "*"))
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq "powershell.exe") -and ($_.CommandLine -like "*wait_for_live_preview_and_restart_obs.ps1*")
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath (Join-Path $Root "obs-studio\config\obs-studio\.sentinel") -Recurse -Force -ErrorAction SilentlyContinue

if (!(Test-Path -LiteralPath $Python)) {
    throw "Python runtime not found: $Python"
}
if (!(Test-Path -LiteralPath (Join-Path $Root "ffmpeg\bin\ffmpeg.exe"))) {
    throw "ffmpeg not found under project: $Root"
}
if (!(Test-Path -LiteralPath $ObsExe)) {
    throw "OBS not found: $ObsExe"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $ResetObs

$DeepLiveArgs = @(
    $RunPy,
    "--execution-provider", "cuda",
    "--execution-threads", "2",
    "--frame-processor", "face_swapper_hyperswap",
    "--live-resizable",
    "--live-fps-debug",
    "--similar-face-distance", "1.5",
    "--live-face-smooth", "0.35",
    "--live-face-fit-scale", "1.06",
    "--quality-preset", "high_quality",
    "--live-xseg-mask",
    "--live-obs-output-window",
    "--no-live-virtualcam-output",
    "-l", "zh"
)
Start-Process -FilePath $Python -ArgumentList $DeepLiveArgs -WorkingDirectory $Root
Add-OperationLog "DeepLiveCam original UI started for OBS window capture"

Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $Watcher) -WindowStyle Hidden
Add-OperationLog "OBS watcher started"

Start-Sleep -Seconds 5
Start-Process -FilePath $ObsExe -ArgumentList @("--portable", "--collection", "DeepLiveCam", "--scene", "DeepLiveCam", "--startvirtualcam") -WorkingDirectory $ObsDir
Add-OperationLog "OBS started for OBS Output capture"
