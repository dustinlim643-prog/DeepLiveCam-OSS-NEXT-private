param(
    [string]$ApkDir = ""
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BlueStacksKey = "HKLM:\SOFTWARE\BlueStacks_nxt"
if (!(Test-Path -LiteralPath $BlueStacksKey)) {
    throw "BlueStacks 5 is not installed."
}

$BlueStacks = Get-ItemProperty -LiteralPath $BlueStacksKey
$Player = Join-Path $BlueStacks.InstallDir "HD-Player.exe"
$Adb = Join-Path $BlueStacks.InstallDir "HD-Adb.exe"
$Config = Join-Path $BlueStacks.UserDefinedDir "bluestacks.conf"
if (!(Test-Path -LiteralPath $Player) -or !(Test-Path -LiteralPath $Adb) -or !(Test-Path -LiteralPath $Config)) {
    throw "BlueStacks player, ADB, or configuration was not found."
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
    throw "No dedicated Android 11 ARM instance was found."
}

$portPattern = '^bst\.instance\.' + [regex]::Escape($Instance) + '\.adb_port="([^"]+)"$'
$AdbPort = foreach ($line in Get-Content -LiteralPath $Config -Encoding UTF8) {
    if ($line -match $portPattern) { $Matches[1]; break }
}
if (!$AdbPort) {
    throw "ADB port is missing for BlueStacks instance $Instance."
}
$Serial = "127.0.0.1:$AdbPort"

if (!$ApkDir) {
    $candidates = @(
        (Join-Path $Root "third_party\WhatsApp-Play-x86_64"),
        (Join-Path $BlueStacks.UserDefinedDir "SharedFolder\WhatsApp-Play-x86_64"),
        "D:\BlueStacks_nxt\SharedFolder\WhatsApp-Play-x86_64"
    )
    $ApkDir = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$ApkDir -or !(Test-Path -LiteralPath $ApkDir)) {
    throw "WhatsApp x86_64 split APK folder was not found. Supply -ApkDir or place it in third_party\WhatsApp-Play-x86_64."
}

$files = Get-ChildItem -LiteralPath $ApkDir -Filter "*.apk" -File
$base = $files | Where-Object { $_.BaseName -notmatch '-(config|i18n)_' -and $_.BaseName -notmatch '-config\.' } | Select-Object -First 1
$x64 = $files | Where-Object { $_.Name -match 'config\.x86_64\.apk$' } | Select-Object -First 1
$density = $files | Where-Object { $_.Name -match 'config\.[^.]+dpi\.apk$' } | Select-Object -First 1
$language = $files | Where-Object { $_.Name -match 'i18n_[^.]+\.apk$' } | Select-Object -First 1
if (!$base -or !$x64 -or !$density -or !$language) {
    throw "The APK folder must contain base, x86_64, density, and language split APKs."
}

$oldPreference = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
& $Adb connect $Serial 2>$null | Out-Null
$state = ((& $Adb -s $Serial get-state 2>$null) -join "").Trim()
$ErrorActionPreference = $oldPreference
if ($state -ne "device") {
    Start-Process -FilePath $Player -ArgumentList @("--instance", $Instance)
    $deadline = (Get-Date).AddSeconds(180)
    do {
        Start-Sleep -Seconds 5
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        & $Adb connect $Serial 2>$null | Out-Null
        $state = ((& $Adb -s $Serial get-state 2>$null) -join "").Trim()
        $boot = if ($state -eq "device") { ((& $Adb -s $Serial shell getprop sys.boot_completed 2>$null) -join "").Trim() } else { "" }
        $ErrorActionPreference = $oldPreference
    } while (($state -ne "device" -or $boot -ne "1") -and (Get-Date) -lt $deadline)
    if ($state -ne "device" -or $boot -ne "1") {
        throw "BlueStacks did not finish booting within 180 seconds."
    }
}

$apks = @($base.FullName, $x64.FullName, $density.FullName, $language.FullName)
Write-Host "Installing verified-layout WhatsApp split package into $Instance..."
& $Adb -s $Serial install-multiple -r $apks
if ($LASTEXITCODE -ne 0) {
    throw "ADB install-multiple failed."
}

$packageInfo = (& $Adb -s $Serial shell dumpsys package com.whatsapp) -join "`n"
$version = if ($packageInfo -match 'versionName=([^\s]+)') { $Matches[1] } else { $null }
$abi = if ($packageInfo -match 'primaryCpuAbi=([^\s]+)') { $Matches[1] } else { $null }
$signature = if ($packageInfo -match 'signatures:\[([^\]]+)\]') { $Matches[1] } else { $null }
Write-Host "Version=$version ABI=$abi Signature=$signature"
if (!$version -or $abi -ne "x86_64" -or $signature -ne "2b6cb416") {
    throw "Installed WhatsApp did not pass ABI/signature verification."
}

Write-Host "WhatsApp split package installation verified. Account linking remains a manual privacy step."
