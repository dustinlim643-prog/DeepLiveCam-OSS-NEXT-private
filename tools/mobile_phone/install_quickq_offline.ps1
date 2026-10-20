param([string]$SdkRoot = "")

$ErrorActionPreference = "Stop"
$ExpectedSha256 = "B22CA8CBA859D97FDA0E92DD2D262979F6B6E354DD86DF818559023AC26DF2B1"
$PackageDirectory = Join-Path $PSScriptRoot "packages"
$RuntimeDirectory = Join-Path $PSScriptRoot "runtime"
$Apk = Join-Path $RuntimeDirectory "QuickQ-official.apk"

if (!$SdkRoot) {
    $SdkRoot = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", "D:\Android", (Join-Path $env:LOCALAPPDATA "Android\Sdk")) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ "platform-tools\adb.exe")) } |
        Select-Object -First 1
}
if (!$SdkRoot) { throw "Android SDK not found." }
$Adb = Join-Path $SdkRoot "platform-tools\adb.exe"
$Parts = @(Get-ChildItem $PackageDirectory -Filter "QuickQ-official.apk.part*" -File | Sort-Object Name)
if ($Parts.Count -ne 2) { throw "Expected two QuickQ APK parts under $PackageDirectory." }

New-Item -ItemType Directory -Force -Path $RuntimeDirectory | Out-Null
$needsBuild = !(Test-Path $Apk)
if (!$needsBuild) { $needsBuild = (Get-FileHash -Algorithm SHA256 $Apk).Hash -ne $ExpectedSha256 }
if ($needsBuild) {
    Write-Host "Rebuilding verified QuickQ APK..."
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
if ($actualHash -ne $ExpectedSha256) { throw "QuickQ APK checksum mismatch: $actualHash" }
$Serial = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] }) | Select-Object -First 1
if (!$Serial) { throw "No running Android emulator was found." }

Write-Host "Installing verified QuickQ APK on $Serial..."
& $Adb -s $Serial install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "QuickQ APK installation failed." }
$installed = ((& $Adb -s $Serial shell pm path net.s17s.s17ray 2>$null) -join "").Trim()
if (!$installed) { throw "QuickQ package was not found after installation." }
Write-Host "QUICKQ_INSTALL_OK"
