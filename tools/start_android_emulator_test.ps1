param(
    [switch]$CheckOnly,
    [string]$ProxyHost = "10.0.2.2",
    [int]$ProxyPort = 8800
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogPath = Join-Path $LogDir ("android_route_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$Report = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()

function Add-Report([string]$Message) {
    $Report.Add($Message)
    Write-Host $Message
}

function Add-Failure([string]$Message) {
    $Failures.Add($Message)
    Add-Report "FAIL: $Message"
}

function Set-BlueStacksValue([string]$Name, [string]$Value) {
    $lines = Get-Content -LiteralPath $script:Config -Encoding UTF8
    $pattern = '^' + [regex]::Escape($Name) + '=".*"$'
    $replacement = $Name + '="' + $Value + '"'
    if ($lines -match $pattern) {
        $lines = $lines -replace $pattern, $replacement
    } else {
        $lines += $replacement
    }
    [System.IO.File]::WriteAllLines($script:Config, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Get-BlueStacksValue([string]$Name) {
    $pattern = '^' + [regex]::Escape($Name) + '="([^"]*)"$'
    foreach ($line in Get-Content -LiteralPath $script:Config -Encoding UTF8) {
        if ($line -match $pattern) {
            return $Matches[1]
        }
    }
    return $null
}

function Wait-AndroidBoot([string]$Serial, [int]$TimeoutSeconds = 180) {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            & $script:Adb connect $Serial 2>$null | Out-Null
            $state = & $script:Adb -s $Serial get-state 2>$null
            if ($state -match "device") {
                $boot = ((& $script:Adb -s $Serial shell getprop sys.boot_completed 2>$null) -join "").Trim()
                if ($boot -eq "1") {
                    return $true
                }
            }
            Start-Sleep -Seconds 5
        }
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    return $false
}

try {
    Add-Report "DeepLiveCam Android route report"
    Add-Report ("Time: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    Add-Report ("Mode: {0}" -f $(if ($CheckOnly) { "check" } else { "start" }))

    $BlueStacksKey = "HKLM:\SOFTWARE\BlueStacks_nxt"
    if (!(Test-Path -LiteralPath $BlueStacksKey)) {
        throw "BlueStacks 5 is not installed."
    }

    $BlueStacks = Get-ItemProperty -LiteralPath $BlueStacksKey
    $Player = Join-Path $BlueStacks.InstallDir "HD-Player.exe"
    $Adb = Join-Path $BlueStacks.InstallDir "HD-Adb.exe"
    $Config = Join-Path $BlueStacks.UserDefinedDir "bluestacks.conf"
    if (!(Test-Path -LiteralPath $Player) -or !(Test-Path -LiteralPath $Adb) -or !(Test-Path -LiteralPath $Config)) {
        throw "BlueStacks player, ADB, or configuration was not found."
    }

    $armInstances = foreach ($line in Get-Content -LiteralPath $Config -Encoding UTF8) {
        if ($line -match '^bst\.instance\.([^.]+)\.abi_list="([^"]+)"$') {
            $abis = $Matches[2] -split ','
            $instancePath = Join-Path $BlueStacks.DataDir $Matches[1]
            if ($abis -contains "arm64" -and $abis -notcontains "x86" -and $abis -notcontains "x64" -and (Test-Path -LiteralPath $instancePath)) {
                Get-Item -LiteralPath $instancePath
            }
        }
    }
    $Instance = $armInstances | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name
    if (!$Instance) {
        throw "No dedicated Android 11 ARM instance was found. Run the one-time migration checklist."
    }
    Add-Report "Instance: $Instance"

    if (!$CheckOnly) {
        Get-Process HD-Player -ErrorAction SilentlyContinue | ForEach-Object { $null = $_.CloseMainWindow() }
        Start-Sleep -Seconds 3
        Get-Process HD-Player -ErrorAction SilentlyContinue | Stop-Process -Force

        $backup = "$Config.before_deeplivecam_android.bak"
        if (!(Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $Config -Destination $backup
        }

        Set-BlueStacksValue "bst.enable_adb_access" "1"
        Set-BlueStacksValue "bst.instance.$Instance.camera_backend" "qt"
        Set-BlueStacksValue "bst.instance.$Instance.camera_device" "OBS Virtual Camera"
        Set-BlueStacksValue "bst.instance.$Instance.camera_rotation_angle" "0"
        Set-BlueStacksValue "bst.instance.$Instance.custom_resolution_selected" "1"
        Set-BlueStacksValue "bst.instance.$Instance.fb_width" "720"
        Set-BlueStacksValue "bst.instance.$Instance.fb_height" "1280"
        Set-BlueStacksValue "bst.instance.$Instance.dpi" "240"
        Set-BlueStacksValue "bst.instance.$Instance.cpus" "4"
        Set-BlueStacksValue "bst.instance.$Instance.ram" "4096"
        Set-BlueStacksValue "bst.instance.$Instance.max_fps" "30"

        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "start_deeplivecam_obs.ps1") -Mode low_latency -OutputRoute Android
        Start-Sleep -Seconds 15
        Start-Process -FilePath $Player -ArgumentList @("--instance", $Instance)
    }

    $AdbPort = Get-BlueStacksValue "bst.instance.$Instance.adb_port"
    if (!$AdbPort) {
        throw "ADB port is missing for BlueStacks instance $Instance."
    }
    $Serial = "127.0.0.1:$AdbPort"
    Add-Report "ADB: $Serial"

    if (!(Wait-AndroidBoot -Serial $Serial)) {
        throw "BlueStacks did not finish booting within 180 seconds."
    }
    Add-Report "Android boot: OK"

    $CameraDevice = Get-BlueStacksValue "bst.instance.$Instance.camera_device"
    $Width = Get-BlueStacksValue "bst.instance.$Instance.fb_width"
    $Height = Get-BlueStacksValue "bst.instance.$Instance.fb_height"
    Add-Report "BlueStacks camera: $CameraDevice"
    Add-Report "BlueStacks frame: ${Width}x${Height}"
    if ($CameraDevice -ne "OBS Virtual Camera" -or $Width -ne "720" -or $Height -ne "1280") {
        Add-Failure "BlueStacks camera or frame configuration is incorrect."
    }

    $listener = Get-NetTCPConnection -State Listen -LocalPort $ProxyPort -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @("127.0.0.1", "0.0.0.0", "::", "::1") } |
        Select-Object -First 1
    if (!$listener) {
        Add-Failure "QuickQ proxy is not listening on host port $ProxyPort."
    } else {
        Add-Report "QuickQ listener: OK (host port $ProxyPort)"
    }

    if (!$CheckOnly) {
        & $Adb -s $Serial shell settings put global http_proxy "${ProxyHost}:$ProxyPort"
        & $Adb -s $Serial shell settings put global global_http_proxy_host $ProxyHost
        & $Adb -s $Serial shell settings put global global_http_proxy_port $ProxyPort
    }
    $AndroidProxy = ((& $Adb -s $Serial shell settings get global http_proxy) -join "").Trim()
    Add-Report "Android proxy: $AndroidProxy"
    if ($AndroidProxy -ne "${ProxyHost}:$ProxyPort") {
        Add-Failure "Android proxy is not configured for QuickQ."
    }

    if ($listener) {
        try {
            $HostIp = (Invoke-RestMethod -Uri "http://api.ipify.org" -Proxy "http://127.0.0.1:$ProxyPort" -TimeoutSec 15).Trim()
            $proxyRequest = "echo -e 'GET http://api.ipify.org/ HTTP/1.0\r\nHost: api.ipify.org\r\nConnection: close\r\n\r\n' | nc -w 10 $ProxyHost $ProxyPort"
            $proxyResponse = (& $Adb -s $Serial shell $proxyRequest) -join "`n"
            $GuestIp = [regex]::Matches($proxyResponse, '(?m)^\s*(\d{1,3}(?:\.\d{1,3}){3})\s*$') |
                Select-Object -Last 1 | ForEach-Object { $_.Groups[1].Value }
            Add-Report "QuickQ host egress: $HostIp"
            Add-Report "Android proxy egress: $GuestIp"
            if (!$GuestIp -or $HostIp -ne $GuestIp) {
                Add-Failure "BlueStacks and the host do not share the same QuickQ egress."
            }
        } catch {
            Add-Failure "Could not verify QuickQ egress: $($_.Exception.Message)"
        }
    }

    $packageInfo = (& $Adb -s $Serial shell dumpsys package com.whatsapp) -join "`n"
    $Version = if ($packageInfo -match 'versionName=([^\s]+)') { $Matches[1] } else { $null }
    $CpuAbi = if ($packageInfo -match 'primaryCpuAbi=([^\s]+)') { $Matches[1] } else { $null }
    $Signature = if ($packageInfo -match 'signatures:\[([^\]]+)\]') { $Matches[1] } else { $null }
    Add-Report "WhatsApp version: $Version"
    Add-Report "WhatsApp ABI: $CpuAbi"
    Add-Report "WhatsApp signature: $Signature"
    if (!$Version) {
        Add-Failure "WhatsApp is not installed in the selected instance."
    }
    if ($CpuAbi -ne "x86_64") {
        Add-Failure "WhatsApp must use the Google Play x86_64 split package."
    }
    if ($Signature -ne "2b6cb416") {
        Add-Failure "WhatsApp signature does not match the verified official package."
    }

    $Obs = Get-Process obs64 -ErrorAction SilentlyContinue | Select-Object -First 1
    $Preview = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq "OBS Output" } | Select-Object -First 1
    Add-Report ("OBS Android profile: {0}" -f $(if ($Obs -and $Obs.MainWindowTitle -match "DeepLiveCam-Android") { "OK" } else { "NOT READY" }))
    Add-Report ("DeepLiveCam OBS Output: {0}" -f $(if ($Preview) { "OK" } else { "NOT READY" }))
    if (!$Obs -or $Obs.MainWindowTitle -notmatch "DeepLiveCam-Android") {
        Add-Failure "OBS is not running the DeepLiveCam-Android profile."
    }
    if (!$Preview) {
        Add-Failure "The DeepLiveCam OBS Output window is not running."
    }

    if (!$CheckOnly -and $Failures.Count -eq 0) {
        & $Adb -s $Serial shell monkey -p com.whatsapp -c android.intent.category.LAUNCHER 1 | Out-Null
        Start-Sleep -Seconds 3
    }
    $Activity = ((& $Adb -s $Serial shell dumpsys activity activities) | Select-String "mResumedActivity" | Select-Object -First 1).Line.Trim()
    Add-Report "Android foreground: $Activity"

    if ($Failures.Count -eq 0) {
        Add-Report "RESULT: PASS"
        Add-Report "Manual privacy gate: accept WhatsApp terms/link the account, then visually verify the in-app camera preview and remote phone."
    } else {
        Add-Report "RESULT: FAIL ($($Failures.Count) issue(s))"
    }
} catch {
    Add-Failure $_.Exception.Message
    Add-Report "RESULT: FAIL"
} finally {
    [System.IO.File]::WriteAllLines($LogPath, $Report, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Report: $LogPath"
}

if ($Failures.Count -gt 0) {
    exit 1
}
