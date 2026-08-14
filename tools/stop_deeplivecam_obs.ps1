$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

function Add-OperationLog($Text) {
    Add-Content -LiteralPath (Join-Path $Logs "operation_log.txt") -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $Text)
}

Add-OperationLog "stop requested"

$needle = $Root.TrimEnd("\")

Get-CimInstance Win32_Process | Where-Object {
    (($_.Name -in @("python.exe", "pythonw.exe")) -and ($_.CommandLine -like ("*" + $needle + "*"))) -or
    (($_.Name -eq "powershell.exe") -and ($_.CommandLine -like "*wait_for_live_preview_and_restart_obs.ps1*"))
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

$obsProcesses = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($needle + "*"))
}
foreach ($process in $obsProcesses) {
    $p = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    if ($p) {
        $null = $p.CloseMainWindow()
    }
}

Start-Sleep -Seconds 5

Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($needle + "*"))
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath (Join-Path $Root "obs-studio\config\obs-studio\.sentinel") -Recurse -Force -ErrorAction SilentlyContinue
Add-OperationLog "DeepLiveCam and OBS stopped"

