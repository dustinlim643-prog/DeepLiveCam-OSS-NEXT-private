param(
    [switch]$CheckOnly,
    [string]$AvdName = "DeepLiveCam_Phone",
    [string]$Webcam = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Report = Join-Path $LogDir ("avd_phone_check_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$Lines = [System.Collections.Generic.List[string]]::new()

function Add-Report([string]$Text) {
    $Lines.Add($Text)
    Write-Host $Text
}

function Find-AndroidSdk {
    $candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "D:\Android\Sdk",
        "C:\Android\Sdk"
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "platform-tools\adb.exe")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Save-Report {
    [System.IO.File]::WriteAllLines($Report, $Lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "REPORT=$Report"
}

try {
    Add-Report "DeepLiveCam official AVD phone-camera gate"
    Add-Report ("Time: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    Add-Report "Purpose: verify phone front-camera metadata before WhatsApp login"
    Add-Report ""

    $Sdk = Find-AndroidSdk
    if (!$Sdk) {
        Add-Report "RESULT: SDK_NOT_INSTALLED"
        Add-Report "Android SDK/Emulator is not installed. BlueStacks is intentionally not used by this test."
        Save-Report
        exit 2
    }

    $Adb = Join-Path $Sdk "platform-tools\adb.exe"
    $Emulator = Join-Path $Sdk "emulator\emulator.exe"
    if (!(Test-Path -LiteralPath $Emulator)) {
        Add-Report "RESULT: EMULATOR_NOT_INSTALLED"
        Save-Report
        exit 2
    }
    Add-Report "SDK: $Sdk"

    $Avds = @(& $Emulator -list-avds 2>$null)
    if ($AvdName -notin $Avds) {
        Add-Report "RESULT: AVD_NOT_CREATED"
        Add-Report "Expected AVD: $AvdName"
        Save-Report
        exit 2
    }
    Add-Report "AVD: $AvdName"

    $WebcamOutput = @(& $Emulator "@$AvdName" -webcam-list 2>&1)
    Add-Report "Available host cameras:"
    foreach ($line in $WebcamOutput) { Add-Report ("  " + $line) }

    if (!$Webcam) {
        $droidLine = $WebcamOutput | Where-Object { $_ -match "DroidCam" } | Select-Object -First 1
        if ($droidLine -and $droidLine -match "'(webcam\d+)'" ) {
            $Webcam = $Matches[1]
        }
    }
    if (!$Webcam) {
        Add-Report "RESULT: DROIDCAM_WEBCAM_NOT_IDENTIFIED"
        Add-Report "Run again with an explicit camera, for example: 2_TEST_AVD_PHONE.cmd -Webcam webcam1"
        Save-Report
        exit 2
    }
    Add-Report "Selected front camera input: $Webcam"

    if ($CheckOnly) {
        Add-Report "RESULT: PREREQUISITES_PASS"
        Save-Report
        exit 0
    }

    $before = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_ -split '\s+')[0] })
    Start-Process -FilePath $Emulator -ArgumentList @("@$AvdName", "-camera-front", $Webcam, "-camera-back", "none", "-no-snapshot-load")

    $deadline = (Get-Date).AddMinutes(4)
    $Serial = $null
    do {
        Start-Sleep -Seconds 3
        $devices = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_ -split '\s+')[0] })
        $Serial = $devices | Where-Object { $_ -notin $before } | Select-Object -First 1
        if (!$Serial -and $devices.Count -eq 1) { $Serial = $devices[0] }
        if ($Serial) {
            $boot = ((& $Adb -s $Serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
            if ($boot -eq "1") { break }
        }
    } while ((Get-Date) -lt $deadline)

    if (!$Serial -or $boot -ne "1") {
        Add-Report "RESULT: AVD_BOOT_FAILED"
        Save-Report
        exit 1
    }
    Add-Report "ADB: $Serial"

    $CameraDump = (& $Adb -s $Serial shell dumpsys media.camera 2>&1) -join "`n"
    $match = [regex]::Match($CameraDump, 'Facing:\s*Front[\s\S]{0,800}?Orientation:\s*(90|270)')
    if (!$match.Success) {
        $match = [regex]::Match($CameraDump, 'android\.lens\.facing[^\n]*\[\s*0\s*\][\s\S]{0,3000}?android\.sensor\.orientation[^\n]*\[\s*(90|270)\s*\]')
    }

    if ($match.Success) {
        Add-Report ("Front camera orientation: {0}" -f $match.Groups[1].Value)
        Add-Report "RESULT: CAMERA_METADATA_PASS"
        Add-Report "Next gate: open the Android Camera app and verify the live DroidCam frame. Do not log in to WhatsApp yet."
        Save-Report
        exit 0
    }

    $summary = $CameraDump -split "`n" | Where-Object { $_ -match 'Facing:|Orientation:|android\.lens\.facing|android\.sensor\.orientation' }
    Add-Report "Camera metadata found:"
    foreach ($line in $summary) { Add-Report ("  " + $line.Trim()) }
    Add-Report "RESULT: CAMERA_METADATA_FAIL"
    Add-Report "Stop condition reached: the AVD did not expose a 90/270-degree phone front camera."
    Save-Report
    exit 1
} catch {
    Add-Report ("RESULT: ERROR - " + $_.Exception.Message)
    Save-Report
    exit 1
}
