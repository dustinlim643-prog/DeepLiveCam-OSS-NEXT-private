param(
    [ValidateSet("quality", "low_latency")]
    [string]$Mode = "quality"
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
$Watcher = Join-Path $Root "tools\wait_for_live_preview_and_restart_obs.ps1"
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
    Set-Content -LiteralPath $Path -Encoding UTF8 -Value $lines
}

function Enable-DroidCamOutput {
    if (!(Test-Path -LiteralPath $ObsProfileRoot)) {
        return
    }
    Get-ChildItem -LiteralPath $ObsProfileRoot -Directory | ForEach-Object {
        $basicIni = Join-Path $_.FullName "basic.ini"
        Set-IniValue $basicIni "DroidCamVirtualOutput" "AutoStart" "true"
        Set-IniValue $basicIni "Video" "BaseCX" "1280"
        Set-IniValue $basicIni "Video" "BaseCY" "720"
        Set-IniValue $basicIni "Video" "OutputCX" "1280"
        Set-IniValue $basicIni "Video" "OutputCY" "720"
        Set-IniValue $basicIni "Video" "FPSType" "0"
        Set-IniValue $basicIni "Video" "FPSCommon" "30"
    }
}

Add-OperationLog "start UI + OBS requested mode=$Mode"

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

& powershell -NoProfile -ExecutionPolicy Bypass -File $ResetObs
Enable-DroidCamOutput

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

Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $Watcher) -WindowStyle Hidden
Add-OperationLog "OBS watcher started"

Start-Sleep -Seconds 5
Start-Process -FilePath $ObsExe -ArgumentList @("--portable", "--profile", "DeepLiveCam", "--collection", "DeepLiveCam", "--scene", "DeepLiveCam") -WorkingDirectory $ObsDir
Add-OperationLog "OBS started for OBS Output capture with DroidCam Virtual Output autostart"
