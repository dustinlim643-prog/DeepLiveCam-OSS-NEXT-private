$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$DriverDir = Join-Path $Root "obs-studio\data\obs-plugins\win-dshow"
$Driver64 = Join-Path $DriverDir "obs-virtualcam-module64.dll"
$Driver32 = Join-Path $DriverDir "obs-virtualcam-module32.dll"
$Clsid64 = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{A3FCE0F5-3493-419F-958A-ABA1250EC20B}"
$Clsid32 = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\{A3FCE0F5-3493-419F-958A-ABA1250EC20B}"

if (!(Test-Path -LiteralPath $Driver64) -or !(Test-Path -LiteralPath $Driver32)) {
    throw "OBS Virtual Camera driver DLLs are missing under: $DriverDir"
}

if (!(Test-Path -LiteralPath $Clsid64)) {
    $regsvr64 = Join-Path $env:WINDIR "System32\regsvr32.exe"
    $process = Start-Process -FilePath $regsvr64 -Verb RunAs -Wait -PassThru -ArgumentList @("/i", "/s", ('"' + $Driver64 + '"'))
    if ($process.ExitCode -ne 0) {
        throw "64-bit OBS Virtual Camera registration failed with exit code $($process.ExitCode)"
    }
}

if (!(Test-Path -LiteralPath $Clsid32)) {
    $regsvr32 = Join-Path $env:WINDIR "SysWOW64\regsvr32.exe"
    $process = Start-Process -FilePath $regsvr32 -Verb RunAs -Wait -PassThru -ArgumentList @("/i", "/s", ('"' + $Driver32 + '"'))
    if ($process.ExitCode -ne 0) {
        throw "32-bit OBS Virtual Camera registration failed with exit code $($process.ExitCode)"
    }
}

if (!(Test-Path -LiteralPath $Clsid64)) {
    throw "OBS Virtual Camera registration was not found after installation."
}

Write-Host "OBS Virtual Camera installed successfully."
Write-Host "Close Telegram completely, restart the mobile format, and then reopen Telegram."
