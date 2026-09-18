$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BlueStacksKey = "HKLM:\SOFTWARE\BlueStacks_nxt"
if (!(Test-Path -LiteralPath $BlueStacksKey)) {
    throw "BlueStacks 5 is not installed."
}

$BlueStacks = Get-ItemProperty -LiteralPath $BlueStacksKey
$Player = Join-Path $BlueStacks.InstallDir "HD-Player.exe"
$Config = Join-Path $BlueStacks.UserDefinedDir "bluestacks.conf"
if (!(Test-Path -LiteralPath $Player) -or !(Test-Path -LiteralPath $Config)) {
    throw "BlueStacks player or configuration was not found."
}

Get-Process HD-Player -ErrorAction SilentlyContinue | ForEach-Object {
    $null = $_.CloseMainWindow()
}
Start-Sleep -Seconds 3
Get-Process HD-Player -ErrorAction SilentlyContinue | Stop-Process -Force

$backup = "$Config.before_deeplivecam_android.bak"
if (!(Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $Config -Destination $backup
}

function Set-BlueStacksValue($Name, $Value) {
    $lines = Get-Content -LiteralPath $Config -Encoding UTF8
    $prefix = [regex]::Escape($Name) + '=".*"$'
    $replacement = $Name + '="' + $Value + '"'
    if ($lines -match $prefix) {
        $lines = $lines -replace $prefix, $replacement
    } else {
        $lines += $replacement
    }
    [System.IO.File]::WriteAllLines($Config, $lines, [System.Text.UTF8Encoding]::new($false))
}

Set-BlueStacksValue "bst.instance.Pie64.camera_backend" "qt"
Set-BlueStacksValue "bst.instance.Pie64.camera_device" "OBS Virtual Camera"
Set-BlueStacksValue "bst.instance.Pie64.camera_rotation_angle" "0"
Set-BlueStacksValue "bst.instance.Pie64.custom_resolution_selected" "1"
Set-BlueStacksValue "bst.instance.Pie64.fb_width" "720"
Set-BlueStacksValue "bst.instance.Pie64.fb_height" "1280"
Set-BlueStacksValue "bst.instance.Pie64.max_fps" "30"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start_deeplivecam_obs.ps1") -Mode low_latency -OutputRoute Android
Start-Sleep -Seconds 15
Start-Process -FilePath $Player -ArgumentList @("--instance", "Pie64")

Write-Host "Android test route started: OBS Virtual Camera 720x1280 -> BlueStacks Pie64."
