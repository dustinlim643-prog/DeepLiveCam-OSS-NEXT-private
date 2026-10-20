param([string]$SdkRoot = "")

$ErrorActionPreference = "Stop"
$ExpectedSha256 = "4B92CF77D25492DCB381534341FB50B01D59418E408AD4C2BDFFB18D2EEB807F"
$PackageDirectory = Join-Path $PSScriptRoot "packages"
$RuntimeDirectory = Join-Path $PSScriptRoot "runtime"
$Apk = Join-Path $RuntimeDirectory "WhatsApp-official.apk"

if (!$SdkRoot) {
    $SdkRoot = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", "D:\Android", (Join-Path $env:LOCALAPPDATA "Android\Sdk")) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ "platform-tools\adb.exe")) } |
        Select-Object -First 1
}
if (!$SdkRoot) { throw "Android SDK not found." }
$Adb = Join-Path $SdkRoot "platform-tools\adb.exe"
$Parts = @(Get-ChildItem $PackageDirectory -Filter "WhatsApp-official.apk.part*" -File | Sort-Object Name)
if ($Parts.Count -ne 2) { throw "Expected two WhatsApp APK parts under $PackageDirectory." }

New-Item -ItemType Directory -Force -Path $RuntimeDirectory | Out-Null
$needsBuild = !(Test-Path $Apk)
if (!$needsBuild) { $needsBuild = (Get-FileHash -Algorithm SHA256 $Apk).Hash -ne $ExpectedSha256 }
if ($needsBuild) {
    Write-Host "Rebuilding verified WhatsApp APK..."
    $output = [IO.File]::Create($Apk)
    try {
        foreach ($part in $Parts) {
            $input = [IO.File]::OpenRead($part.FullName)
            try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
    } finally {
        $output.Dispose()
    }
}

$actualHash = (Get-FileHash -Algorithm SHA256 $Apk).Hash
if ($actualHash -ne $ExpectedSha256) { throw "WhatsApp APK checksum mismatch: $actualHash" }
$Serial = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] }) | Select-Object -First 1
if (!$Serial) { throw "No running Android emulator was found." }

Write-Host "Installing verified WhatsApp APK on $Serial..."
& $Adb -s $Serial install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "WhatsApp APK installation failed." }
$installed = ((& $Adb -s $Serial shell pm path com.whatsapp 2>$null) -join "").Trim()
if (!$installed) { throw "WhatsApp package was not found after installation." }
Write-Host "WHATSAPP_INSTALL_OK"
