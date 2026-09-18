param(
    [ValidateSet("quality", "low_latency")]
    [string]$Mode = "quality",
    [ValidateSet("Desktop", "Mobile")]
    [string]$OutputRoute = "Desktop"
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$ObsExe = Join-Path $Root "obs-studio\bin\64bit\obs64.exe"
$ObsDir = Join-Path $Root "obs-studio\bin\64bit"
$Python = Join-Path $Root "python\python.exe"
$RunPy = Join-Path $Root "run.py"
$DefaultSourceFace = Join-Path $Root "source_faces\current_test_source.jpg"
$ResetObs = Join-Path $Root "tools\reset_obs_scene.ps1"
$ResetObsMobile = Join-Path $Root "tools\reset_obs_mobile_scene.ps1"
$Watcher = Join-Path $Root "tools\wait_for_live_preview_and_restart_obs.ps1"
$ObsConfigRoot = Join-Path $Root "obs-studio\config\obs-studio"
$ObsProfileRoot = Join-Path $Root "obs-studio\config\obs-studio\basic\profiles"

if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

function Add-OperationLog($Text) {
    Add-Content -LiteralPath (Join-Path $Logs "operation_log.txt") -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $Text)
}

function Stop-ProjectProcess($Names) {
    $needle = $Root.TrimEnd("\")
    Get-CimInstance Win32_Process | Where-Object {
        ($Names -contains $_.Name) -and ($_.CommandLine -like ("*" + $needle + "*"))
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Set-IniValue($Path, $Section, $Key, $Value) {
    if (!(Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
        Set-Content -LiteralPath $Path -Encoding UTF8 -Value ""
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]](Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue))
    $sectionHeader = "[$Section]"
    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $sectionHeader) {
            $sectionIndex = $i
            break
        }
    }
    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") {
            $lines.Add("")
        }
        $lines.Add($sectionHeader)
        $lines.Add("$Key=$Value")
    } else {
        $insertAt = $lines.Count
        $keyIndex = -1
        for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim().StartsWith("[") -and $lines[$i].Trim().EndsWith("]")) {
                $insertAt = $i
                break
            }
            if ($lines[$i] -match ("^\s*" + [regex]::Escape($Key) + "\s*=")) {
                $keyIndex = $i
                break
            }
        }
        if ($keyIndex -ge 0) {
            $lines[$keyIndex] = "$Key=$Value"
        } else {
            $lines.Insert($insertAt, "$Key=$Value")
        }
    }
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
}

function Set-ObsOutputProfile($ProfileName, $EnableDroidCam, $Width, $Height, $SceneCollection) {
    if (!(Test-Path -LiteralPath $ObsProfileRoot)) {
        New-Item -ItemType Directory -Path $ObsProfileRoot -Force | Out-Null
    }

    $profileDir = Join-Path $ObsProfileRoot $ProfileName
    if (!(Test-Path -LiteralPath $profileDir)) {
        $sourceProfile = Get-ChildItem -LiteralPath $ObsProfileRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "basic.ini") } |
            Select-Object -First 1

        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        if ($sourceProfile) {
            Copy-Item -LiteralPath (Join-Path $sourceProfile.FullName "*") -Destination $profileDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $preferredBasicIni = Join-Path $profileDir "basic.ini"
    Set-IniValue $preferredBasicIni "General" "Name" $ProfileName
    Set-IniValue $preferredBasicIni "DroidCamVirtualOutput" "AutoStart" $EnableDroidCam.ToString().ToLowerInvariant()
    Set-IniValue $preferredBasicIni "Video" "BaseCX" $Width
    Set-IniValue $preferredBasicIni "Video" "BaseCY" $Height
    Set-IniValue $preferredBasicIni "Video" "OutputCX" $Width
    Set-IniValue $preferredBasicIni "Video" "OutputCY" $Height
    Set-IniValue $preferredBasicIni "Video" "FPSType" "0"
    Set-IniValue $preferredBasicIni "Video" "FPSCommon" "30"
    Set-IniValue $preferredBasicIni "Video" "ScaleType" "bicubic"
    Set-IniValue $preferredBasicIni "Video" "ColorFormat" "NV12"
    Set-IniValue $preferredBasicIni "Video" "ColorSpace" "709"
    Set-IniValue $preferredBasicIni "Video" "ColorRange" "Partial"

    $userIni = Join-Path $ObsConfigRoot "user.ini"
    Set-IniValue $userIni "Basic" "Profile" $ProfileName
    Set-IniValue $userIni "Basic" "ProfileDir" $ProfileName
    Set-IniValue $userIni "Basic" "SceneCollection" $SceneCollection
    Set-IniValue $userIni "Basic" "SceneCollectionFile" "$SceneCollection.json"
    Add-OperationLog "OBS profile=$ProfileName DroidCamAutoStart=$EnableDroidCam route=$OutputRoute"
}

Add-OperationLog "start UI + OBS requested mode=$Mode route=$OutputRoute"

$env:PATH = (Join-Path $Root "ffmpeg\bin") + ";" + (Join-Path $Root "python") + ";" + (Join-Path $Root "python\Scripts") + ";" + $env:PATH

Stop-ProjectProcess @("python.exe", "pythonw.exe")
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($Root.TrimEnd("\") + "*"))
} | ForEach-Object {
    $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
    if ($p) {
        $null = $p.CloseMainWindow()
    }
}
Start-Sleep -Seconds 3
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -in @("obs64.exe", "obs32.exe", "obs.exe")) -and ($_.ExecutablePath -like ($Root.TrimEnd("\") + "*"))
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq "powershell.exe") -and ($_.CommandLine -like "*wait_for_live_preview_and_restart_obs.ps1*")
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath (Join-Path $Root "obs-studio\config\obs-studio\.sentinel") -Recurse -Force -ErrorAction SilentlyContinue

if (!(Test-Path -LiteralPath $Python)) {
    throw "Python runtime not found: $Python"
}
if (!(Test-Path -LiteralPath (Join-Path $Root "ffmpeg\bin\ffmpeg.exe"))) {
    throw "ffmpeg not found under project: $Root"
}
if (!(Test-Path -LiteralPath $ObsExe)) {
    throw "OBS not found: $ObsExe"
}
if (!(Test-Path -LiteralPath $DefaultSourceFace)) {
    throw "Default source face not found: $DefaultSourceFace"
}

$ObsProfile = if ($OutputRoute -eq "Mobile") { "DeepLiveCam-Mobile" } else { "DeepLiveCam" }
$UseDroidCam = $OutputRoute -eq "Desktop"
$ObsCollection = if ($OutputRoute -eq "Mobile") { "DeepLiveCam-Mobile" } else { "DeepLiveCam" }
$ObsWidth = if ($OutputRoute -eq "Mobile") { 720 } else { 1280 }
$ObsHeight = if ($OutputRoute -eq "Mobile") { 1280 } else { 720 }
if ($OutputRoute -eq "Mobile") {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ResetObsMobile
} else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ResetObs
}
Set-ObsOutputProfile $ObsProfile $UseDroidCam $ObsWidth $ObsHeight $ObsCollection

$QualityPreset = "high_quality"
$UseXSeg = $true
$FaceFitScale = "1.06"
$FaceSmooth = "0.35"

if ($Mode -eq "low_latency") {
    $QualityPreset = "low_latency"
    $UseXSeg = $false
    $FaceFitScale = "1.06"
    $FaceSmooth = "0.25"
}

$DeepLiveArgs = @(
    $RunPy,
    "--source", $DefaultSourceFace,
    "--execution-provider", "cuda",
    "--execution-threads", "2",
    "--frame-processor", "face_swapper_hyperswap",
    "--live-resizable",
    "--live-fps-debug",
    "--live-health-log",
    "--similar-face-distance", "1.5",
    "--live-face-smooth", $FaceSmooth,
    "--live-face-fit-scale", $FaceFitScale,
    "--quality-preset", $QualityPreset,
    "--live-obs-output-window",
    "--no-live-virtualcam-output",
    "--auto-live",
    "-l", "zh"
)
if ($UseXSeg) {
    $DeepLiveArgs += "--live-xseg-mask"
} else {
    $DeepLiveArgs += "--no-live-xseg-mask"
}
Start-Process -FilePath $Python -ArgumentList $DeepLiveArgs -WorkingDirectory $Root
Add-OperationLog "DeepLiveCam original UI started for OBS window capture mode=$Mode preset=$QualityPreset xseg=$UseXSeg"

if ($OutputRoute -eq "Mobile") {
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $Watcher, "-ProfileName", $ObsProfile, "-CollectionName", $ObsCollection, "-StartVirtualCam") -WindowStyle Hidden
} else {
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $Watcher, "-ProfileName", $ObsProfile, "-CollectionName", $ObsCollection) -WindowStyle Hidden
}
Add-OperationLog "OBS watcher started"

Start-Sleep -Seconds 5
$ObsArgs = @("--portable", "--profile", $ObsProfile, "--collection", $ObsCollection, "--scene", $ObsCollection)
if ($OutputRoute -eq "Mobile") {
    $ObsArgs += "--startvirtualcam"
}
Start-Process -FilePath $ObsExe -ArgumentList $ObsArgs -WorkingDirectory $ObsDir
Add-OperationLog "OBS started route=$OutputRoute profile=$ObsProfile"
