param(
    [ValidateSet("quality", "low_latency")]
    [string]$Mode = "low_latency",
    [string]$AvdName = "DeepLiveCam_HAL_Test_API37",
    [string]$CameraName = ""
)

$ErrorActionPreference = "Stop"
$ExpectedFingerprint = "google/sdk_gphone64_x86_64/emu64xa:17/CE2A.260420.019/15611780:userdebug/dev-keys"
$ExpectedHalSha256 = "5ed6ffad8da07534ec20ec1de372bf8eece877842a4f0996a87a80c4f4ad86f9"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Runtime = Join-Path $PSScriptRoot "runtime"
$Logs = Join-Path $Root "logs"
$Python = Join-Path $Root "python\python.exe"
$RunPy = Join-Path $Root "run.py"
$DefaultSourceFace = Join-Path $Root "source_faces\current_test_source.jpg"
$SourceFace = if ($env:DEEPLIVECAM_SOURCE_FACE) {
    $env:DEEPLIVECAM_SOURCE_FACE
} elseif (Test-Path $DefaultSourceFace) {
    $DefaultSourceFace
} else {
    Get-ChildItem (Join-Path $Root "source_faces") -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png', '.webp') } |
        Select-Object -First 1 -ExpandProperty FullName
}
$Bridge = Join-Path $PSScriptRoot "live_hal_bridge.py"
$FridaPy = Join-Path $Runtime "frida_py"
$FridaServer = Join-Path $Runtime "frida-server"
$Report = Join-Path $Logs ("mobile_phone_start_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$reportLines = [Collections.Generic.List[string]]::new()
$deepLiveProcess = $null
$bridgeProcess = $null
$disabledVirtualCameras = [Collections.Generic.List[object]]::new()
$VirtualCameraPattern = '(?i)^DroidCam Video$|OBS Virtual Camera|e2eSoft.*(?:VCam|WeCam)|(?:VCam|WeCam).*e2eSoft'

function Report([string]$Text) {
    $reportLines.Add($Text)
    Write-Host $Text
}

function Save-Report {
    [IO.File]::WriteAllLines($Report, $reportLines, [Text.UTF8Encoding]::new($false))
    Write-Host "REPORT=$Report"
}

function Restore-VirtualCameras {
    foreach ($camera in @($disabledVirtualCameras)) {
        Enable-PnpDevice -InstanceId $camera.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    if ($disabledVirtualCameras.Count -gt 0) {
        Report "Restored temporarily disabled virtual cameras: $($disabledVirtualCameras.FriendlyName -join ', ')"
        $disabledVirtualCameras.Clear()
    }
}

function Find-AndroidSdk {
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", "D:\Android", (Join-Path $env:LOCALAPPDATA "Android\Sdk"))) {
        if ($candidate -and (Test-Path (Join-Path $candidate "platform-tools\adb.exe"))) { return (Resolve-Path $candidate).Path }
    }
    throw "Android SDK not found. Run tools\mobile_phone\setup_mobile_phone.ps1."
}

function Wait-AndroidBoot([string]$Adb, [int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $offline = @(& $Adb devices | Select-String '^emulator-\d+\s+offline')
        if ($offline.Count -gt 0) { & $Adb reconnect offline 2>$null | Out-Null }
        foreach ($serial in @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] })) {
            $name = ((& $Adb -s $serial emu avd name 2>$null) -join "").Replace("OK", "").Trim()
            $booted = ((& $Adb -s $serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
            if ($name -eq $AvdName -and $booted -eq "1") { return $serial }
        }
    } while ((Get-Date) -lt $deadline)
    throw "$AvdName did not finish booting within $TimeoutSeconds seconds."
}

function Stop-OldMobileBridge {
    $pidFile = Join-Path $Logs "mobile_hal_bridge.pid"
    if (Test-Path $pidFile) {
        $oldPid = [int](Get-Content $pidFile)
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" | Where-Object {
        $_.CommandLine -like '*title=OBS Output*' -and $_.CommandLine -like '*rawvideo*'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

try {
    New-Item -ItemType Directory -Force $Logs | Out-Null
    Report "DeepLiveCam real phone fullscreen route"
    Report "Expected: DeepLiveCam -> FFmpeg I420 -> Frida -> API37 Front/270 1280x720 -> WhatsApp Android"

    $physicalCameras = @(Get-PnpDevice -Class Camera -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -notmatch $VirtualCameraPattern })
    if ($physicalCameras.Count -eq 0) {
        throw "No ready Windows camera was detected. Connect the camera before starting the mobile route."
    }
    if (!$CameraName) { $CameraName = [string]$physicalCameras[0].FriendlyName }
    if ($CameraName -notin @($physicalCameras | Select-Object -ExpandProperty FriendlyName)) {
        throw "Requested physical camera '$CameraName' is not ready. Available: $($physicalCameras.FriendlyName -join ', ')"
    }
    Report "Windows physical camera selected by name: $CameraName"

    if (!$SourceFace) {
        throw "No source face image found. Put one image in source_faces or set DEEPLIVECAM_SOURCE_FACE."
    }
    foreach ($required in @($Python, $RunPy, $SourceFace, $Bridge, $FridaServer, (Join-Path $FridaPy "frida\__init__.py"))) {
        if (!(Test-Path $required)) { throw "Missing dependency: $required. Run tools\mobile_phone\setup_mobile_phone.ps1 once." }
    }
    $Sdk = Find-AndroidSdk
    $Adb = Join-Path $Sdk "platform-tools\adb.exe"
    $Emulator = Join-Path $Sdk "emulator\emulator.exe"
    $env:ANDROID_AVD_HOME = Join-Path $env:USERPROFILE ".android\avd"

    $Serial = $null
    foreach ($candidate in @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] })) {
        $name = ((& $Adb -s $candidate emu avd name 2>$null) -join "").Replace("OK", "").Trim()
        if ($name -eq $AvdName) { $Serial = $candidate; break }
    }
    if ($Serial) {
        $qemu = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" |
            Where-Object { $_.CommandLine -like "*@$AvdName*" } | Select-Object -First 1
        if (!$qemu -or $qemu.CommandLine -notlike '*-writable-system*') {
            Report "Restarting AVD because it was not launched in the pinned writable HAL mode..."
            & $Adb -s $Serial emu kill 2>$null | Out-Null
            $Serial = $null
            $stopDeadline = (Get-Date).AddSeconds(30)
            do {
                Start-Sleep -Seconds 1
                $oldQemu = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe'" |
                    Where-Object { $_.CommandLine -like "*@$AvdName*" }
            } while ($oldQemu -and (Get-Date) -lt $stopDeadline)
            if ($oldQemu) { throw "Old AVD process did not stop cleanly within 30 seconds." }
            & $Adb reconnect offline 2>$null | Out-Null
        }
    }
    if (!$Serial) {
        $available = @(& $Emulator -list-avds 2>$null)
        if ($AvdName -notin $available) { throw "Required AVD $AvdName is missing. Run setup_mobile_phone.ps1." }
        Report "Starting pinned AVD $AvdName..."
        Start-Process -FilePath $Emulator -ArgumentList @(
            "@$AvdName", "-writable-system", "-selinux", "permissive",
            "-no-metrics",
            "-no-boot-anim", "-no-snapshot-load", "-no-snapshot-save"
        )
    }
    $Serial = Wait-AndroidBoot $Adb
    & $Adb -s $Serial root | Out-Null
    Start-Sleep -Seconds 2
    & $Adb -s $Serial shell settings put global stay_on_while_plugged_in 3 | Out-Null
    & $Adb -s $Serial shell input keyevent KEYCODE_WAKEUP | Out-Null
    & $Adb -s $Serial shell wm dismiss-keyguard | Out-Null
    Report "AVD ready: $Serial"

    $fingerprint = ((& $Adb -s $Serial shell getprop ro.build.fingerprint) -join "").Trim()
    if ($fingerprint -ne $ExpectedFingerprint) { throw "Android image drift detected. Expected $ExpectedFingerprint; got $fingerprint" }
    $halHash = (((& $Adb -s $Serial shell sha256sum /vendor/lib64/libgooglecamerahwl_impl.so) -join "") -split '\s+')[0]
    if ($halHash -ne $ExpectedHalSha256) { throw "Camera HAL drift detected: $halHash. Hard-coded frame offsets are not safe on this image." }

    $frontText = (& $Adb -s $Serial shell cat /vendor/etc/config/emu_camera_front.json) -join "`n"
    $front = $frontText | ConvertFrom-Json
    if ($front.'android.lens.facing'[0] -ne 'FRONT' -or [int]$front.'android.sensor.orientation'[0] -ne 270) {
        throw "Camera config is not Front/270. Run setup_mobile_phone.ps1 to repair it."
    }
    $streams = $front.'android.scaler.availableStreamConfigurations'
    for ($i = 0; $i -lt $streams.Count; $i += 4) {
        if ([int]$streams[$i + 1] -ne 1280 -or [int]$streams[$i + 2] -ne 720) {
            throw "Camera config contains a non-1280x720 stream. Refusing to start because WhatsApp may fall back to 4:3."
        }
    }
    Report "Camera gate: Front/270, 1280x720-only, pinned HAL"
    Report "Source face: $SourceFace"

    Stop-OldMobileBridge
    Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -in @('python.exe', 'pythonw.exe')) -and $_.CommandLine -like ("*" + $Root.TrimEnd('\') + "*")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'obs64.exe' -and $_.ExecutablePath -like ($Root.TrimEnd('\') + '*')
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    # Virtual DirectShow devices are often registered under Image, Media, or
    # SoftwareDevice instead of the Camera PnP class.
    $virtualCameras = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match $VirtualCameraPattern })
    foreach ($camera in $virtualCameras) {
        Disable-PnpDevice -InstanceId $camera.InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
        $disabledVirtualCameras.Add($camera)
    }
    if ($disabledVirtualCameras.Count -gt 0) {
        Report "Temporarily disabled virtual cameras while opening $CameraName`: $($disabledVirtualCameras.FriendlyName -join ', ')"
        Start-Sleep -Seconds 2
    }

    & $Adb -s $Serial shell am force-stop com.android.camera2 | Out-Null
    & $Adb -s $Serial shell am force-stop com.whatsapp | Out-Null
    & $Adb -s $Serial shell "setprop ctl.restart vendor.camera-provider-2-7-google" | Out-Null
    Start-Sleep -Seconds 4

    $hostServerHash = (Get-FileHash $FridaServer -Algorithm SHA256).Hash.ToLowerInvariant()
    $guestServerHash = (((& $Adb -s $Serial shell sha256sum /data/local/tmp/frida-server 2>$null) -join "") -split '\s+')[0]
    if ($guestServerHash -ne $hostServerHash) {
        & $Adb -s $Serial push $FridaServer /data/local/tmp/frida-server | Out-Null
        & $Adb -s $Serial shell chmod 755 /data/local/tmp/frida-server | Out-Null
    }
    $fridaPid = ((& $Adb -s $Serial shell pidof frida-server 2>$null) -join "").Trim()
    if (!$fridaPid) {
        & $Adb -s $Serial shell "/data/local/tmp/frida-server >/data/local/tmp/frida.log 2>&1 &" | Out-Null
        Start-Sleep -Seconds 2
    }
    & $Adb -s $Serial forward tcp:27042 tcp:27042 | Out-Null
    Report "Frida server and ADB forwarding ready"

    $qualityPreset = if ($Mode -eq 'quality') { 'high_quality' } else { 'low_latency' }
    $faceSmooth = if ($Mode -eq 'quality') { '0.35' } else { '0.25' }
    $quotedCameraName = '"' + $CameraName.Replace('"', '\"') + '"'
    $deepLiveArgs = @(
        $RunPy, '--source', $SourceFace, '--execution-provider', 'cuda', '--execution-threads', '2',
        '--frame-processor', 'face_swapper_hyperswap', '--live-resizable', '--live-fps-debug',
        '--live-health-log', '--similar-face-distance', '1.5', '--live-face-smooth', $faceSmooth,
        '--live-face-fit-scale', '1.06', '--quality-preset', $qualityPreset,
        '--camera-name', $quotedCameraName,
        '--live-obs-output-window', '--no-live-virtualcam-output', '--auto-live', '-l', 'zh'
    )
    $deepLiveArgs += if ($Mode -eq 'quality') { '--live-xseg-mask' } else { '--no-live-xseg-mask' }
    $deepLiveLog = Join-Path $Logs "mobile_deeplivecam_live.log"
    $deepLiveErr = Join-Path $Logs "mobile_deeplivecam_live.err.log"
    $bridgeLog = Join-Path $Logs "mobile_hal_bridge_live.log"
    $bridgeErr = Join-Path $Logs "mobile_hal_bridge_live.err.log"
    Remove-Item $deepLiveLog, $deepLiveErr, $bridgeLog, $bridgeErr -Force -ErrorAction SilentlyContinue
    # Keep camera diagnostics from turning non-ASCII FOURCC text into a GBK
    # UnicodeEncodeError when this script is launched outside the UTF-8 CMD wrapper.
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $deepLiveProcess = Start-Process -FilePath $Python -ArgumentList $deepLiveArgs -WorkingDirectory $Root -RedirectStandardOutput $deepLiveLog -RedirectStandardError $deepLiveErr -PassThru

    $env:MOBILE_HAL_FRIDA_PY = $FridaPy
    $bridgeProcess = Start-Process -FilePath $Python -ArgumentList @($Bridge, '--fps', '15') -WorkingDirectory $Root -RedirectStandardOutput $bridgeLog -RedirectStandardError $bridgeErr -WindowStyle Hidden -PassThru
    [IO.File]::WriteAllText((Join-Path $Logs "mobile_hal_bridge.pid"), [string]$bridgeProcess.Id, [Text.Encoding]::ASCII)
    $bridgeDeadline = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Milliseconds 500
        $fridaReady = (Test-Path $bridgeLog) -and (Select-String -Path $bridgeLog -SimpleMatch "'event': 'ready'" -Quiet)
        $firstFrameReady = (Test-Path $bridgeLog) -and (Select-String -Path $bridgeLog -SimpleMatch '[bridge] sent=1 ' -Quiet)
        if ($bridgeProcess.HasExited) {
            $errorText = if (Test-Path $bridgeErr) { Get-Content $bridgeErr -Raw } else { '' }
            throw "Mobile HAL bridge exited early. $errorText"
        }
        if ($deepLiveProcess.HasExited) {
            $errorText = if (Test-Path $deepLiveErr) { Get-Content $deepLiveErr -Raw } else { '' }
            throw "DeepLiveCam exited before producing video. $errorText"
        }
    } while ((!$fridaReady -or !$firstFrameReady) -and (Get-Date) -lt $bridgeDeadline)
    if (!$fridaReady) { throw "Mobile HAL bridge did not attach to the camera provider." }
    if (!$firstFrameReady) { throw "DeepLiveCam did not produce a capturable OBS Output frame within 3 minutes." }
    Restore-VirtualCameras
    Report "DeepLiveCam first output frame verified (OBS application is not used)"
    Report "Live HAL bridge ready: center 9:16 crop, upright orientation, 15 fps input"

    $wa = ((& $Adb -s $Serial shell pm path com.whatsapp 2>$null) -join "").Trim()
    if (!$wa) { throw "Official WhatsApp is not installed in $AvdName. Install/login once, then rerun." }

    foreach ($permission in @('android.permission.CAMERA', 'android.permission.RECORD_AUDIO')) {
        & $Adb -s $Serial shell pm grant com.whatsapp $permission 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not grant WhatsApp permission: $permission" }
    }
    foreach ($appOp in @('CAMERA', 'RECORD_AUDIO')) {
        & $Adb -s $Serial shell cmd appops set com.whatsapp $appOp allow 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not allow WhatsApp app-op: $appOp" }
    }
    $cameraAppOp = ((& $Adb -s $Serial shell cmd appops get com.whatsapp CAMERA 2>$null) -join "`n")
    if ($cameraAppOp -notmatch 'CAMERA:\s+allow') {
        throw "WhatsApp camera app-op is not allowed: $cameraAppOp"
    }
    Report "WhatsApp camera and microphone permissions verified"

    & $Adb -s $Serial shell am start -n com.whatsapp/.Main | Out-Null
    Report "WhatsApp launched; account data preserved"
    Report "RESULT: READY"
    Save-Report
} catch {
    Restore-VirtualCameras
    if ($bridgeProcess -and !$bridgeProcess.HasExited) {
        Stop-Process -Id $bridgeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if ($deepLiveProcess -and !$deepLiveProcess.HasExited) {
        Stop-Process -Id $deepLiveProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Report ("RESULT: ERROR - " + $_.Exception.Message)
    Save-Report
    exit 1
}
