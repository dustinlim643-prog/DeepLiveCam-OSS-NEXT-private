param(
    [ValidateSet("quality", "low_latency")]
    [string]$Mode = "low_latency",
    [string]$AvdName = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
New-Item -ItemType Directory -Path $Logs -Force | Out-Null
$Report = Join-Path $Logs ("avd_4x3_start_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$Lines = [System.Collections.Generic.List[string]]::new()
$Started = Get-Date

function Add-Report([string]$Text) {
    $Lines.Add($Text)
    Write-Host $Text
}

function Save-Report {
    [System.IO.File]::WriteAllLines($Report, $Lines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "REPORT=$Report"
}

function Find-AndroidSdk {
    $candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        "D:\Android\SDK",
        (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
        "C:\Android\Sdk"
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "platform-tools\adb.exe")) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

try {
    Add-Report "DeepLiveCam AVD native 4:3 route"
    Add-Report ("Time: {0}" -f $Started.ToString("yyyy-MM-dd HH:mm:ss"))
    Add-Report "Expected chain: DeepLiveCam -> OBS 640x480 -> DroidCam -> AVD Front/90 -> WhatsApp"
    Add-Report ""

    $Sdk = Find-AndroidSdk
    if (!$Sdk) { throw "Android SDK was not found." }
    $Adb = Join-Path $Sdk "platform-tools\adb.exe"
    $Emulator = Join-Path $Sdk "emulator\emulator.exe"
    if (!(Test-Path -LiteralPath $Emulator)) { throw "Android Emulator was not found: $Emulator" }

    # Prefer the current API 37 AVD because it has the working WhatsApp account and Quick Boot state.
    $avdHomeCandidates = @(
        $env:ANDROID_AVD_HOME,
        (Join-Path $env:USERPROFILE ".android\avd"),
        "D:\Android\Avd"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $projectAvdHome = $avdHomeCandidates | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ "Medium_Phone_API_37.0.ini")
    } | Select-Object -First 1
    if (!$projectAvdHome) {
        $projectAvdHome = $avdHomeCandidates | Where-Object {
            Test-Path -LiteralPath (Join-Path $_ "DeepLiveCam_Phone_API37.ini")
        } | Select-Object -First 1
    }
    if (!$projectAvdHome) { $projectAvdHome = $avdHomeCandidates | Select-Object -First 1 }
    if (!$projectAvdHome) { throw "No Android AVD home was found." }
    $env:ANDROID_AVD_HOME = (Resolve-Path -LiteralPath $projectAvdHome).Path
    Add-Report "AVD home: $env:ANDROID_AVD_HOME"

    $Avds = @(& $Emulator -list-avds 2>$null | Where-Object { $_.Trim() })
    if (!$AvdName) {
        $preferred = @("Medium_Phone_API_37.0", "DeepLiveCam_Phone_API37", "DeepLiveCam_Phone")
        $AvdName = $preferred | Where-Object { $_ -in $Avds } | Select-Object -First 1
        if (!$AvdName) { $AvdName = $Avds | Select-Object -First 1 }
    }
    if (!$AvdName -or $AvdName -notin $Avds) {
        throw "Requested AVD was not found. Available: $($Avds -join ', ')"
    }
    Add-Report "AVD: $AvdName"

    $WebcamOutput = @(& $Emulator "@$AvdName" -webcam-list 2>&1)
    $droidLine = $WebcamOutput | Where-Object { $_ -match "DroidCam" } | Select-Object -First 1
    if (!$droidLine -or $droidLine -notmatch "'(webcam\d+)'" ) {
        throw "DroidCam Video was not exposed to Android Emulator."
    }
    $Webcam = $Matches[1]
    Add-Report "AVD front-camera host input: $Webcam ($droidLine)"

    # The emulator must open DroidCam only after the new OBS producer is active.
    $running = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] })
    foreach ($serial in $running) {
        Add-Report "Stopping stale emulator camera client: $serial"
        & $Adb -s $serial emu kill 2>$null | Out-Null
    }
    $stopDeadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 2
        $remaining = @(& $Adb devices | Select-String '^emulator-\d+\s+device')
    } while ($remaining.Count -gt 0 -and (Get-Date) -lt $stopDeadline)

    Add-Report "Starting isolated OBS profile DeepLiveCam-AVD-4x3..."
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start_deeplivecam_obs.ps1") -Mode $Mode -OutputRoute AVD4x3
    if ($LASTEXITCODE -ne 0) { throw "DeepLiveCam/OBS startup failed with exit code $LASTEXITCODE" }

    $producerDeadline = (Get-Date).AddMinutes(3)
    $producerReady = $false
    do {
        Start-Sleep -Seconds 2
        $obs = Get-Process obs64 -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match "DeepLiveCam-AVD-4x3" }
        $latestObsLog = Get-ChildItem (Join-Path $Root "obs-studio\config\obs-studio\logs") -Filter "*.txt" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $mapped = $false
        if ($latestObsLog -and $latestObsLog.LastWriteTime -ge $Started.AddMinutes(-1)) {
            $mapped = [bool](Select-String -LiteralPath $latestObsLog.FullName -Pattern "DroidcamVirtualOut.*mapped|droidcam_virtual_output=" -CaseSensitive:$false -Quiet)
        }
        if ($obs -and $mapped) { $producerReady = $true }
    } while (!$producerReady -and (Get-Date) -lt $producerDeadline)
    if (!$producerReady) { throw "OBS/DroidCam producer did not become ready within 3 minutes." }
    Add-Report "OBS/DroidCam producer: READY at 640x480"

    Add-Report "Starting AVD with Quick Boot; use a cold boot only when the saved state is invalid."
    Start-Process -FilePath $Emulator -ArgumentList @("@$AvdName", "-camera-front", $Webcam, "-camera-back", "none", "-no-boot-anim")
    $bootDeadline = (Get-Date).AddMinutes(4)
    $Serial = $null
    do {
        Start-Sleep -Seconds 3
        $Serial = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] }) | Select-Object -First 1
        if ($Serial) {
            $boot = ((& $Adb -s $Serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
        }
    } while ((!$Serial -or $boot -ne "1") -and (Get-Date) -lt $bootDeadline)
    if (!$Serial -or $boot -ne "1") { throw "AVD did not complete boot within 4 minutes." }
    Add-Report "ADB: $Serial"

    & $Adb -s $Serial shell settings put system accelerometer_rotation 0 | Out-Null
    & $Adb -s $Serial shell settings put system user_rotation 0 | Out-Null
    $CameraDump = (& $Adb -s $Serial shell dumpsys media.camera 2>&1) -join "`n"
    if ($CameraDump -notmatch 'Facing:\s*Front[\s\S]{0,300}?Orientation:\s*(90|270)') {
        throw "AVD camera metadata is not Front with 90/270-degree orientation."
    }
    $Orientation = $Matches[1]
    if ($CameraDump -notmatch '\[34 640 480 OUTPUT \]') {
        throw "AVD Camera HAL does not advertise the required 640x480 private stream."
    }
    Add-Report "Camera HAL: Front / Orientation $Orientation / 640x480 supported"

    $wa = ((& $Adb -s $Serial shell pm path com.whatsapp 2>$null) -join "").Trim()
    if ($wa) {
        & $Adb -s $Serial shell am force-stop com.whatsapp | Out-Null
        & $Adb -s $Serial shell am start -n com.whatsapp/.Main | Out-Null
        Add-Report "WhatsApp: launched; existing account data was preserved"
    } else {
        Add-Report "WhatsApp: NOT INSTALLED"
    }

    Add-Report "RESULT: TECHNICAL_GATE_PASS"
    Add-Report "Manual gate: place one video call and judge only remote fill, face size, sharpness, and black borders."
    Save-Report
    exit 0
} catch {
    Add-Report ("RESULT: ERROR - " + $_.Exception.Message)
    Save-Report
    exit 1
}
