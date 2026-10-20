param([string]$SdkRoot = "")

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Report = Join-Path $Root "logs\mobile_black_screen_diagnostic.txt"
$Screenshot = Join-Path $Root "logs\mobile_android_screen.png"
$lines = [Collections.Generic.List[string]]::new()

function Add-Line([string]$Text) {
    $lines.Add($Text)
    Write-Host $Text
}

if (!$SdkRoot) {
    $SdkRoot = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", "D:\Android", (Join-Path $env:LOCALAPPDATA "Android\Sdk")) |
        Where-Object { $_ -and (Test-Path (Join-Path $_ "platform-tools\adb.exe")) } |
        Select-Object -First 1
}
if (!$SdkRoot) { throw "Android SDK not found." }
$Adb = Join-Path $SdkRoot "platform-tools\adb.exe"
$Serial = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] }) | Select-Object -First 1
if (!$Serial) { throw "No running Android emulator was found." }

New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
Add-Line "Serial: $Serial"
Add-Line "BootCompleted: $(((& $Adb -s $Serial shell getprop sys.boot_completed) -join '').Trim())"
Add-Line "AVD: $(((& $Adb -s $Serial emu avd name 2>$null) -join ' ').Replace('OK', '').Trim())"

& $Adb -s $Serial shell screencap -p /sdcard/mobile_android_screen.png | Out-Null
& $Adb -s $Serial pull /sdcard/mobile_android_screen.png $Screenshot | Out-Null
if (!(Test-Path $Screenshot)) { throw "Android screencap failed." }

Add-Type -AssemblyName System.Drawing
$bitmap = [Drawing.Bitmap]::FromFile($Screenshot)
try {
    [long]$sum = 0
    [long]$samples = 0
    [long]$nonBlack = 0
    $colors = [Collections.Generic.HashSet[int]]::new()
    for ($y = 0; $y -lt $bitmap.Height; $y += 20) {
        for ($x = 0; $x -lt $bitmap.Width; $x += 20) {
            $pixel = $bitmap.GetPixel($x, $y)
            $brightness = [int](($pixel.R + $pixel.G + $pixel.B) / 3)
            $sum += $brightness
            $samples++
            if ($brightness -gt 8) { $nonBlack++ }
            [void]$colors.Add((($pixel.R -shr 4) -shl 8) -bor (($pixel.G -shr 4) -shl 4) -bor ($pixel.B -shr 4))
        }
    }
    $mean = [Math]::Round($sum / [double]$samples, 2)
    $visibleRatio = [Math]::Round($nonBlack / [double]$samples, 4)
    Add-Line "GuestScreenshot: $($bitmap.Width)x$($bitmap.Height) meanBrightness=$mean visibleRatio=$visibleRatio coarseColors=$($colors.Count)"
    if ($mean -lt 3 -and $visibleRatio -lt 0.01) {
        Add-Line "GuestDisplayResult: BLACK_INSIDE_ANDROID"
    } else {
        Add-Line "GuestDisplayResult: ANDROID_FRAMEBUFFER_HAS_CONTENT"
    }
} finally {
    $bitmap.Dispose()
}

Add-Line "CurrentFocus:"
(& $Adb -s $Serial shell dumpsys window windows | Select-String 'mCurrentFocus|mFocusedApp') | ForEach-Object { Add-Line ($_.Line.Trim()) }
Add-Line "AndroidProcesses:"
foreach ($package in @('surfaceflinger', 'com.android.systemui', 'com.whatsapp', 'net.s17s.s17ray')) {
    Add-Line "  $package=$(((& $Adb -s $Serial shell pidof $package 2>$null) -join '').Trim())"
}

Add-Line "WindowsOBSProcesses:"
$obs = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('obs64.exe', 'obs32.exe', 'obs.exe') })
if ($obs.Count -eq 0) {
    Add-Line "  NONE"
} else {
    $obs | ForEach-Object { Add-Line "  PID=$($_.ProcessId) Path=$($_.ExecutablePath) Cmd=$($_.CommandLine)" }
}
Add-Line "DeepLiveCamOutputWindows:"
$pythonWindows = @(Get-Process python, pythonw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle })
if ($pythonWindows.Count -eq 0) {
    Add-Line "  NONE"
} else {
    $pythonWindows | ForEach-Object { Add-Line "  PID=$($_.Id) Title=$($_.MainWindowTitle)" }
}

[IO.File]::WriteAllLines($Report, $lines, [Text.UTF8Encoding]::new($false))
Write-Host "SCREENSHOT=$Screenshot"
Write-Host "REPORT=$Report"
