param(
    [string]$AvdName = "DeepLiveCam_HAL_Test_API37",
    [string]$SdkRoot = ""
)

$ErrorActionPreference = "Stop"
$FridaVersion = "17.23.3"
$ExpectedFingerprint = "google/sdk_gphone64_x86_64/emu64xa:17/CE2A.260420.019/15611780:userdebug/dev-keys"
$ExpectedHalSha256 = "5ed6ffad8da07534ec20ec1de372bf8eece877842a4f0996a87a80c4f4ad86f9"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Runtime = Join-Path $PSScriptRoot "runtime"
$Python = Join-Path $Root "python\python.exe"
$Ffmpeg = Join-Path $Root "ffmpeg\bin\ffmpeg.exe"
$BaseRuntimeFiles = @(
    $Python,
    $Ffmpeg,
    (Join-Path $Root "models\hyperswap_1a_256.onnx"),
    (Join-Path $Root "models\inswapper_128.onnx"),
    (Join-Path $Root "models\insightface\models\buffalo_l\det_10g.onnx")
)

function Find-AndroidSdk {
    if ($SdkRoot) {
        if (Test-Path (Join-Path $SdkRoot "platform-tools\adb.exe")) {
            return (Resolve-Path $SdkRoot).Path
        }
        throw "Invalid Android SDK root: $SdkRoot (platform-tools\adb.exe not found)."
    }
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", "D:\Android", (Join-Path $env:LOCALAPPDATA "Android\Sdk"))) {
        if ($candidate -and (Test-Path (Join-Path $candidate "platform-tools\adb.exe"))) {
            return (Resolve-Path $candidate).Path
        }
    }
    throw "Android SDK not found. Install Android Studio/SDK or pass -SdkRoot."
}

function Wait-AndroidBoot([string]$Adb, [int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 3
        $serial = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] }) | Select-Object -First 1
        if ($serial) {
            $booted = ((& $Adb -s $serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
            if ($booted -eq "1") { return $serial }
        }
    } while ((Get-Date) -lt $deadline)
    throw "AVD did not finish booting within $TimeoutSeconds seconds."
}

function Invoke-AdbCommand([string]$Adb, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $Adb @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Enable-WritableVendor([string]$Adb, [string]$Serial) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'root'))
        [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'wait-for-device'))
        Start-Sleep -Seconds 2
        $identity = Invoke-AdbCommand $Adb @('-s', $Serial, 'shell', 'id')
        if ($identity.ExitCode -eq 0 -and $identity.Output -match 'uid=0') { break }
        if ($attempt -eq 3) { throw "ADB root failed after three attempts.`n$($identity.Output)" }
    }

    $remount = Invoke-AdbCommand $Adb @('-s', $Serial, 'remount')
    $writeTest = Invoke-AdbCommand $Adb @('-s', $Serial, 'shell', 'touch /vendor/etc/config/.dlc_write_test && rm /vendor/etc/config/.dlc_write_test')
    if ($remount.ExitCode -eq 0 -and $writeTest.ExitCode -eq 0) { return }

    Write-Host "Disabling Android verified partitions and rebooting once..."
    [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'disable-verity'))
    [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'reboot'))
    $Serial = Wait-AndroidBoot $Adb
    [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'root'))
    [void](Invoke-AdbCommand $Adb @('-s', $Serial, 'wait-for-device'))
    Start-Sleep -Seconds 2
    $remount = Invoke-AdbCommand $Adb @('-s', $Serial, 'remount')
    $writeTest = Invoke-AdbCommand $Adb @('-s', $Serial, 'shell', 'touch /vendor/etc/config/.dlc_write_test && rm /vendor/etc/config/.dlc_write_test')
    if ($remount.ExitCode -ne 0 -or $writeTest.ExitCode -ne 0) {
        throw "Unable to make /vendor writable.`nadb remount:`n$($remount.Output)`nwrite test:`n$($writeTest.Output)"
    }
}

function Set-IniValue([string]$Path, [string]$Key, [string]$Value) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]](Get-Content -LiteralPath $Path))
    $index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^' + [regex]::Escape($Key) + '=')) { $index = $i; break }
    }
    if ($index -ge 0) { $lines[$index] = "$Key=$Value" } else { $lines.Add("$Key=$Value") }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}

function Build-FrontConfig([string]$Source, [string]$Target) {
    $camera = Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json
    function Keep-Tuples([object[]]$Values, [int]$TupleSize, [int]$WidthIndex, [int]$HeightIndex) {
        $result = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $Values.Count; $i += $TupleSize) {
            if ([int]$Values[$i + $WidthIndex] -eq 1280 -and [int]$Values[$i + $HeightIndex] -eq 720) {
                for ($j = 0; $j -lt $TupleSize; $j++) { $result.Add([string]$Values[$i + $j]) }
            }
        }
        return $result.ToArray()
    }
    $camera.'android.lens.facing' = @('FRONT')
    $camera.'android.sensor.orientation' = @('270')
    $camera.'android.sensor.info.activeArraySize' = @('0', '0', '1280', '720')
    $camera.'android.sensor.info.pixelArraySize' = @('1280', '720')
    $camera.'android.sensor.info.preCorrectionActiveArraySize' = @('0', '0', '1280', '720')
    $sizes = $camera.'android.control.availableExtendedSceneModeMaxSizes'
    for ($i = 0; $i -lt $sizes.Count; $i += 3) {
        if ([int]$sizes[$i] -ne 0) { $sizes[$i + 1] = '1280'; $sizes[$i + 2] = '720' }
    }
    $camera.'android.control.availableExtendedSceneModeMaxSizes' = $sizes
    $camera.'android.scaler.availableStreamConfigurations' = Keep-Tuples $camera.'android.scaler.availableStreamConfigurations' 4 1 2
    $camera.'android.scaler.availableMinFrameDurations' = Keep-Tuples $camera.'android.scaler.availableMinFrameDurations' 4 1 2
    $camera.'android.scaler.availableStallDurations' = Keep-Tuples $camera.'android.scaler.availableStallDurations' 4 1 2
    if ($camera.'android.scaler.availableStreamConfigurations'.Count -eq 0) { throw "No 1280x720 streams remained in generated front-camera config." }
    [IO.File]::WriteAllText($Target, ($camera | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

$missingBaseRuntime = @($BaseRuntimeFiles | Where-Object { !(Test-Path $_) })
if ($missingBaseRuntime.Count -gt 0) {
    throw "Base DeepLiveCam runtime is incomplete. Git does not contain these large files. Restore them from the complete project package first:`n$($missingBaseRuntime -join "`n")"
}
New-Item -ItemType Directory -Force $Runtime | Out-Null
$Sdk = Find-AndroidSdk
$Adb = Join-Path $Sdk "platform-tools\adb.exe"
$Emulator = Join-Path $Sdk "emulator\emulator.exe"
$EmulatorCheck = Join-Path $Sdk "emulator\emulator-check.exe"
$AvdManager = Get-ChildItem (Join-Path $Sdk "cmdline-tools") -Filter avdmanager.bat -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
$Java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "" }
if (!$Java -or !(Test-Path $Java)) {
    $Java = Get-ChildItem (Join-Path $Sdk "portable-jdk") -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
        Select-Object -First 1 -ExpandProperty FullName
    if ($Java) { $env:JAVA_HOME = Split-Path (Split-Path $Java -Parent) -Parent }
}
if (!$Java -or !(Test-Path $Java)) { throw "Java 17+ not found. Restore the portable JDK under $Sdk\portable-jdk." }
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

Write-Host "[1/5] Installing pinned Frida runtime $FridaVersion..."
$FridaPy = Join-Path $Runtime "frida_py"
if (!(Test-Path (Join-Path $FridaPy "frida\__init__.py"))) {
    & $Python -m pip install --target $FridaPy "frida==$FridaVersion"
    if ($LASTEXITCODE -ne 0) { throw "Frida Python installation failed." }
}
$FridaServer = Join-Path $Runtime "frida-server"
if (!(Test-Path $FridaServer)) {
    $archive = Join-Path $Runtime "frida-server.xz"
    Invoke-WebRequest -UseBasicParsing "https://github.com/frida/frida/releases/download/$FridaVersion/frida-server-$FridaVersion-android-x86_64.xz" -OutFile $archive
    & $Python -c "import lzma,shutil; shutil.copyfileobj(lzma.open(r'$archive','rb'),open(r'$FridaServer','wb'))"
    if ($LASTEXITCODE -ne 0) { throw "Frida server extraction failed." }
    Remove-Item $archive -Force
}

Write-Host "[2/5] Checking the pinned API 37 Google APIs AVD..."
$env:ANDROID_AVD_HOME = Join-Path $env:USERPROFILE ".android\avd"
$avds = @(& $Emulator -list-avds 2>$null)
if ($AvdName -notin $avds) {
    if (!$AvdManager) { throw "avdmanager.bat not found. Install Android SDK Command-line Tools." }
    $imageDirectory = Join-Path $Sdk "system-images\android-37.0\google_apis\x86_64"
    $image = Join-Path $imageDirectory "system.img"
    $portableImageDirectory = Join-Path $Sdk "x86_64"
    if (!(Test-Path $image) -and (Test-Path (Join-Path $portableImageDirectory "system.img"))) {
        Write-Host "Restoring portable API 37 image directory layout..."
        New-Item -ItemType Directory -Force -Path (Split-Path $imageDirectory -Parent) | Out-Null
        Move-Item -LiteralPath $portableImageDirectory -Destination $imageDirectory
    }
    if (!(Test-Path $image)) { throw "Required system image is missing: system-images;android-37.0;google_apis;x86_64 revision 6." }
    'no' | & $AvdManager create avd --force --name $AvdName --package "system-images;android-37.0;google_apis;x86_64"
    if ($LASTEXITCODE -ne 0) { throw "AVD creation failed with exit code $LASTEXITCODE." }
}
$config = Join-Path $env:ANDROID_AVD_HOME "$AvdName.avd\config.ini"
if (!(Test-Path $config)) { throw "AVD config not found: $config" }
Set-IniValue $config "hw.camera.front" "emulated"
Set-IniValue $config "hw.camera.front.orientation" "270"
Set-IniValue $config "hw.camera.back" "emulated"
Set-IniValue $config "hw.initialOrientation" "portrait"
Set-IniValue $config "hw.lcd.width" "1080"
Set-IniValue $config "hw.lcd.height" "2400"
Set-IniValue $config "hw.lcd.density" "420"
Set-IniValue $config "hw.cpu.ncore" "4"
Set-IniValue $config "hw.ramSize" "2G"
Set-IniValue $config "disk.dataPartition.size" "16G"
Set-IniValue $config "hw.gpu.enabled" "yes"
Set-IniValue $config "hw.gpu.mode" "swiftshader"

$accelResult = (& $EmulatorCheck accel 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "Android emulator hardware acceleration is unavailable. Enable Windows Hypervisor Platform and reboot before retrying.`n$accelResult"
}

$running = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] })
foreach ($serial in $running) { & $Adb -s $serial emu kill 2>$null | Out-Null }
Start-Sleep -Seconds 4
Start-Process -FilePath $Emulator -ArgumentList @("@$AvdName", "-writable-system", "-selinux", "permissive", "-gpu", "swiftshader", "-no-metrics", "-no-snapshot-load", "-no-boot-anim")
$Serial = Wait-AndroidBoot $Adb
& $Adb -s $Serial shell settings put global stay_on_while_plugged_in 3 | Out-Null
& $Adb -s $Serial shell input keyevent KEYCODE_WAKEUP | Out-Null
& $Adb -s $Serial shell wm dismiss-keyguard | Out-Null
Enable-WritableVendor $Adb $Serial

$fingerprint = ((& $Adb -s $Serial shell getprop ro.build.fingerprint) -join "").Trim()
if ($fingerprint -ne $ExpectedFingerprint) {
    throw "Unsupported Android image. Expected revision-6 fingerprint: $ExpectedFingerprint; got: $fingerprint"
}
$halHash = (((& $Adb -s $Serial shell sha256sum /vendor/lib64/libgooglecamerahwl_impl.so) -join "") -split '\s+')[0]
if ($halHash -ne $ExpectedHalSha256) { throw "Camera HAL build changed; refusing unsafe hard-coded frame offsets. SHA256=$halHash" }

Write-Host "[3/5] Building and applying Front/270/1280x720-only Camera HAL configuration..."
$Back = Join-Path $Runtime "emu_camera_back.base.json"
$Front = Join-Path $Runtime "emu_camera_front.720p-only.json"
$Main = Join-Path $Runtime "emu_camera_main.video.json"
$Video = Join-Path $Runtime "phone_front_1280x720.mp4"
& $Adb -s $Serial pull /vendor/etc/config/emu_camera_back.json $Back | Out-Null
Build-FrontConfig $Back $Front
$mainObject = [ordered]@{ cameras = @(
    [ordered]@{ type = 'back'; filename = 'emu_camera_back.json' },
    [ordered]@{ type = 'front'; filename = 'emu_camera_front.json'; source = 'video'; file_path = '/vendor/etc/config/phone_front_1280x720.mp4' },
    [ordered]@{ type = 'depth'; filename = 'emu_camera_depth.json' },
    [ordered]@{ type = 'external'; filename = 'emu_camera_external.json' }
) }
[IO.File]::WriteAllText($Main, ($mainObject | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
if (!(Test-Path $Video)) {
    & $Ffmpeg -hide_banner -loglevel error -f lavfi -i "testsrc2=size=1280x720:rate=30" -t 3 -c:v libx264 -profile:v baseline -pix_fmt yuv420p -movflags +faststart -y $Video
    if ($LASTEXITCODE -ne 0) { throw "Camera fallback video generation failed." }
}

& $Adb -s $Serial push $Front /vendor/etc/config/emu_camera_front.json | Out-Null
& $Adb -s $Serial push $Main /vendor/etc/config/emu_camera_main.json | Out-Null
& $Adb -s $Serial push $Video /vendor/etc/config/phone_front_1280x720.mp4 | Out-Null
& $Adb -s $Serial shell "chmod 644 /vendor/etc/config/emu_camera_front.json /vendor/etc/config/emu_camera_main.json /vendor/etc/config/phone_front_1280x720.mp4; setprop ctl.restart vendor.camera-provider-2-7-google"
Start-Sleep -Seconds 4

Write-Host "[4/5] Installing Frida server in the Android guest..."
& $Adb -s $Serial push $FridaServer /data/local/tmp/frida-server | Out-Null
& $Adb -s $Serial shell "chmod 755 /data/local/tmp/frida-server"

Write-Host "[5/5] Verifying WhatsApp and camera prerequisites..."
$wa = ((& $Adb -s $Serial shell pm path com.whatsapp 2>$null) -join "").Trim()
if (!$wa) { Write-Warning "Official WhatsApp is not installed. Install it and complete the one-time login manually." }
$sourceFace = Get-ChildItem (Join-Path $Root "source_faces") -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.jpg', '.jpeg', '.png', '.webp') } |
    Select-Object -First 1
if (!$sourceFace) { Write-Warning "No source face image found. Put one image in source_faces before daily startup." }
Write-Host "SETUP_OK"
Write-Host "Fingerprint: $fingerprint"
Write-Host "AVD: $AvdName ($Serial)"
Write-Host "Next daily action: run 2_START_MOBILE_PHONE_FULLSCREEN.cmd"
