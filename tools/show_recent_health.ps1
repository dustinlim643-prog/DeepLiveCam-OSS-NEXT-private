$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"

if (!(Test-Path -LiteralPath $Logs)) {
    Write-Output "No logs directory found: $Logs"
    exit 0
}

$health = Get-ChildItem -LiteralPath $Logs -Filter "live_health_*.txt" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (!$health) {
    Write-Output "No live_health_*.txt found."
    exit 0
}

Write-Output "Latest health log:"
Write-Output $health.FullName
Write-Output ""
Write-Output "Last 40 lines:"
Get-Content -LiteralPath $health.FullName -Encoding UTF8 | Select-Object -Last 40

$obsLogDir = Join-Path $Root "obs-studio\config\obs-studio\logs"
if (Test-Path -LiteralPath $obsLogDir) {
    $obsLog = Get-ChildItem -LiteralPath $obsLogDir -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($obsLog) {
        Write-Output ""
        Write-Output "Latest OBS DroidCam lines:"
        Write-Output $obsLog.FullName
        Get-Content -LiteralPath $obsLog.FullName -Encoding UTF8 |
            Select-String -Pattern "Droidcam|AutoStart|webcam video active|webcam became inactive|Total frames output|window-capture|failed" -CaseSensitive:$false |
            Select-Object -Last 40
    }
}
