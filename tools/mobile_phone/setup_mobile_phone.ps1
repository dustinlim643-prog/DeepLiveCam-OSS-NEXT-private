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

function Find-AndroidSdk {
    if ($SdkRoot) { return $SdkRoot }
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, "D:\Android\SDK", (Join-Path $env:LOCALAPPDATA "Android\Sdk"))) {
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

if (!(Test-Path $Python) -or !(Test-Path $Ffmpeg)) { throw "Project Python/FFmpeg runtime is incomplete." }
New-Item -ItemType Directory -Force $Runtime | Out-Null
$Sdk = Find-AndroidSdk
$Adb = Join-Path $Sdk "platform-tools\adb.exe"
$Emulator = Join-Path $Sdk "emulator\emulator.exe"
$AvdManager = Get-ChildItem (Join-Path $Sdk "cmdline-tools") -Filter avdmanager.bat -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

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
    $image = Join-Path $Sdk "system-images\android-37.0\google_apis\x86_64\system.img"
    if (!(Test-Path $image)) { throw "Required system image is missing: system-images;android-37.0;google_apis;x86_64 revision 6." }
    'no' | & $AvdManager create avd --force --name $AvdName --package "system-images;android-37.0;google_apis;x86_64" --device "pixel_7"
}
$config = Join-Path $env:ANDROID_AVD_HOME "$AvdName.avd\config.ini"
if (!(Test-Path $config)) { throw "AVD config not found: $config" }
Set-IniValue $config "hw.camera.front" "emulated"
Set-IniValue $config "hw.camera.front.orientation" "270"
Set-IniValue $config "hw.camera.back" "emulated"
Set-IniValue $config "disk.dataPartition.size" "16G"

$running = @(& $Adb devices | Select-String '^emulator-\d+\s+device' | ForEach-Object { ($_.Line -split '\s+')[0] })
foreach ($serial in $running) { & $Adb -s $serial emu kill 2>$null | Out-Null }
Start-Sleep -Seconds 4
Start-Process -FilePath $Emulator -ArgumentList @("@$AvdName", "-writable-system", "-selinux", "permissive", "-no-snapshot-load", "-no-boot-anim")
$Serial = Wait-AndroidBoot $Adb
& $Adb -s $Serial root | Out-Null
Start-Sleep -Seconds 2

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

& $Adb -s $Serial shell "mount -o rw,remount /vendor" 2>$null | Out-Null
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
