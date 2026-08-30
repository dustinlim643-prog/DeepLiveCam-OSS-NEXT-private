$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$ObsRoot = Join-Path $Root "obs-studio\config\obs-studio"
$Scene = Join-Path $ObsRoot "basic\scenes\DeepLiveCam.json"
$Profiles = Join-Path $ObsRoot "basic\profiles"

if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Report = Join-Path $Logs "whatsapp_video_chain_$stamp.txt"

function Add-Line($Text = "") {
    Add-Content -LiteralPath $Report -Encoding UTF8 -Value $Text
    Write-Output $Text
}

function Read-IniValue($Path, $Section, $Key) {
    if (!(Test-Path -LiteralPath $Path)) {
        return $null
    }
    $inSection = $false
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue) {
        $trim = $line.Trim()
        if ($trim -eq "[$Section]") {
            $inSection = $true
            continue
        }
        if ($inSection -and $trim.StartsWith("[") -and $trim.EndsWith("]")) {
            return $null
        }
        if ($inSection -and $trim -match ("^\s*" + [regex]::Escape($Key) + "\s*=(.*)$")) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

Add-Line "WhatsApp video chain diagnostic"
Add-Line ("Time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Add-Line ("Root: " + $Root)
Add-Line ""

Add-Line "1. Expected chain"
Add-Line "  DeepLiveCam OBS Output -> OBS window capture -> DroidCam Virtual Output -> DroidCam Video -> WhatsApp"
Add-Line ""

Add-Line "2. Processes"
$proc = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "python|obs64|WhatsApp|DroidCam" } |
    Sort-Object ProcessName, Id
if ($proc) {
    foreach ($p in $proc) {
        Add-Line ("  {0} pid={1} title={2}" -f $p.ProcessName, $p.Id, $p.MainWindowTitle)
    }
} else {
    Add-Line "  FAIL: no related process found"
}
Add-Line ""

Add-Line "3. Devices"
$devices = Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match "Droid|OBS|Camera" } |
    Sort-Object Class, FriendlyName
if ($devices) {
    foreach ($d in $devices) {
        Add-Line ("  {0} class={1} name={2}" -f $d.Status, $d.Class, $d.FriendlyName)
    }
} else {
    Add-Line "  FAIL: no DroidCam/OBS/Camera device found"
}
Add-Line ""

Add-Line "4. OBS profile and scene"
$userIni = Join-Path $ObsRoot "user.ini"
Add-Line ("  user.ini exists=" + (Test-Path -LiteralPath $userIni))
Add-Line ("  Profile=" + (Read-IniValue $userIni "Basic" "Profile"))
Add-Line ("  ProfileDir=" + (Read-IniValue $userIni "Basic" "ProfileDir"))
Add-Line ("  SceneCollection=" + (Read-IniValue $userIni "Basic" "SceneCollection"))
Add-Line ("  SceneCollectionFile=" + (Read-IniValue $userIni "Basic" "SceneCollectionFile"))

$deepProfile = Join-Path $Profiles "DeepLiveCam\basic.ini"
Add-Line ("  DeepLiveCam profile exists=" + (Test-Path -LiteralPath $deepProfile))
if (Test-Path -LiteralPath $deepProfile) {
    Add-Line ("  DroidCam AutoStart=" + (Read-IniValue $deepProfile "DroidCamVirtualOutput" "AutoStart"))
    Add-Line ("  Base=" + (Read-IniValue $deepProfile "Video" "BaseCX") + "x" + (Read-IniValue $deepProfile "Video" "BaseCY"))
    Add-Line ("  Output=" + (Read-IniValue $deepProfile "Video" "OutputCX") + "x" + (Read-IniValue $deepProfile "Video" "OutputCY"))
    Add-Line ("  FPS=" + (Read-IniValue $deepProfile "Video" "FPSCommon"))
}

Add-Line ("  DeepLiveCam scene exists=" + (Test-Path -LiteralPath $Scene))
if (Test-Path -LiteralPath $Scene) {
    try {
        $j = Get-Content -LiteralPath $Scene -Raw -Encoding UTF8 | ConvertFrom-Json
        $src = $j.sources | Where-Object { $_.name -eq "DeepLiveCam OBS Output" } | Select-Object -First 1
        Add-Line ("  source exists=" + [bool]$src)
        if ($src) {
            Add-Line ("  source id=" + $src.id)
            Add-Line ("  capture window=" + $src.settings.window)
            Add-Line ("  capture method=" + $src.settings.method)
        }
        Add-Line ("  current_scene=" + $j.current_scene)
        Add-Line ("  resolution=" + $j.resolution.x + "x" + $j.resolution.y)
    } catch {
        Add-Line ("  FAIL: scene parse failed: " + $_.Exception.Message)
    }
}
Add-Line ""

Add-Line "5. Latest OBS evidence"
$obsLogDir = Join-Path $ObsRoot "logs"
if (!(Test-Path -LiteralPath $obsLogDir)) {
    Add-Line "  FAIL: OBS log directory not found"
} else {
    $obsLog = Get-ChildItem -LiteralPath $obsLogDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (!$obsLog) {
        Add-Line "  FAIL: no OBS log found"
    } else {
        Add-Line ("  file=" + $obsLog.FullName)
        $lines = Get-Content -LiteralPath $obsLog.FullName -Encoding UTF8 -ErrorAction SilentlyContinue |
            Select-String -Pattern "droidcam|DroidCam|webcam video active|webcam became inactive|AutoStart|window-capture|OBS Output|failed|black|stopping" -CaseSensitive:$false |
            Select-Object -Last 80
        foreach ($line in $lines) {
            Add-Line ("  " + $line.Line)
        }
    }
}
Add-Line ""

Add-Line "6. Quick conclusion rules"
Add-Line "  If OBS preview has swapped video but WhatsApp shows Start DroidCam/black: DroidCam Virtual Output is not active or WhatsApp is reading the wrong stale device stream."
Add-Line "  If OBS preview is black: OBS window capture is not locked to OBS Output."
Add-Line "  If OBS log has no droidcam-virtual-output loaded: plugin is missing or OBS is not using bundled portable plugin path."
Add-Line "  If AutoStart is not true: OBS will not feed DroidCam Video until manually started."
Add-Line "  If WhatsApp sees DroidCam Video but no image, restart order matters: stop project, start project, wait OBS Output, wait OBS DroidCam active, then open WhatsApp."
Add-Line ""
Add-Line ("Report: " + $Report)
