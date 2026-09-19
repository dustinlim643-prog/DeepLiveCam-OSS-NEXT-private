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

$armInstances = foreach ($line in Get-Content -LiteralPath $Config -Encoding UTF8) {
    if ($line -match '^bst\.instance\.([^.]+)\.abi_list="([^"]+)"$') {
        $abis = $Matches[2] -split ','
        $instancePath = Join-Path $BlueStacks.DataDir $Matches[1]
        if ($abis -contains "arm64" -and $abis -notcontains "x86" -and $abis -notcontains "x64" -and (Test-Path -LiteralPath $instancePath)) {
            Get-Item -LiteralPath $instancePath
        }
    }
}
$Instance = $armInstances | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name
if (!$Instance) {
    throw "A BlueStacks Android 11 ARM-only instance was not found. Create one with ARM 64-bit enabled and x86 disabled."
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

Set-BlueStacksValue "bst.enable_adb_access" "1"
Set-BlueStacksValue "bst.instance.$Instance.camera_backend" "qt"
Set-BlueStacksValue "bst.instance.$Instance.camera_device" "OBS Virtual Camera"
Set-BlueStacksValue "bst.instance.$Instance.camera_rotation_angle" "0"
Set-BlueStacksValue "bst.instance.$Instance.custom_resolution_selected" "1"
Set-BlueStacksValue "bst.instance.$Instance.fb_width" "720"
Set-BlueStacksValue "bst.instance.$Instance.fb_height" "1280"
Set-BlueStacksValue "bst.instance.$Instance.max_fps" "30"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start_deeplivecam_obs.ps1") -Mode low_latency -OutputRoute Android
Start-Sleep -Seconds 15
Start-Process -FilePath $Player -ArgumentList @("--instance", $Instance)

Write-Host "Android test route started: OBS Virtual Camera 720x1280 -> BlueStacks $Instance."
