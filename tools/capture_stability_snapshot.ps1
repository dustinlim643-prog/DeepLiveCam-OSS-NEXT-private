param(
    [string]$Label = "",
    [int]$HealthLines = 120,
    [switch]$SkipNetwork
)

$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Report = Join-Path $Logs "stability_snapshot_$stamp.txt"

function Add-Line($Text = "") {
    Add-Content -LiteralPath $Report -Encoding UTF8 -Value $Text
}

function Get-Number($Line, $Name) {
    $match = [regex]::Match($Line, "$Name=([0-9]+(?:\.[0-9]+)?)")
    if ($match.Success) {
        return [double]$match.Groups[1].Value
    }
    return $null
}

function Get-Percent($Line, $Name) {
    $match = [regex]::Match($Line, "$Name=([0-9]+(?:\.[0-9]+)?)%")
    if ($match.Success) {
        return [double]$match.Groups[1].Value
    }
    return $null
}

function Add-Stat($Name, $Values, $WarnLessThan = $null, $WarnGreaterThan = $null) {
    $valid = @($Values | Where-Object { $null -ne $_ })
    if ($valid.Count -eq 0) {
        Add-Line ("  {0}: no data" -f $Name)
        return
    }

    $avg = ($valid | Measure-Object -Average).Average
    $min = ($valid | Measure-Object -Minimum).Minimum
    $max = ($valid | Measure-Object -Maximum).Maximum
    $state = "OK"
    if ($null -ne $WarnLessThan -and $avg -lt $WarnLessThan) {
        $state = "WARN"
    }
    if ($null -ne $WarnGreaterThan -and $max -gt $WarnGreaterThan) {
        $state = "WARN"
    }

    Add-Line ("  {0}: avg={1:N1} min={2:N1} max={3:N1} state={4}" -f $Name, $avg, $min, $max, $state)
}

Add-Line "DeepLiveCam stability snapshot"
Add-Line ("Time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
if ($Label.Trim().Length -gt 0) {
    Add-Line ("Label: " + $Label)
}
Add-Line ("Root: " + $Root)
Add-Line ""

Add-Line "1. Process state"
$processes = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "python|obs64|WhatsApp|DroidCam" } |
    Sort-Object ProcessName, Id
if ($processes) {
    foreach ($p in $processes) {
        $title = ""
        try { $title = $p.MainWindowTitle } catch {}
        Add-Line ("  {0} pid={1} cpu={2:N1} title={3}" -f $p.ProcessName, $p.Id, $p.CPU, $title)
    }
} else {
    Add-Line "  WARN: no python/obs64/WhatsApp/DroidCam process found"
}
Add-Line ""

Add-Line "2. Camera devices"
try {
    $devices = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "Droid|OBS|Camera" } |
        Sort-Object Class, FriendlyName
    if ($devices) {
        foreach ($d in $devices) {
            Add-Line ("  {0} class={1} name={2}" -f $d.Status, $d.Class, $d.FriendlyName)
        }
    } else {
        Add-Line "  WARN: no DroidCam/OBS/Camera device found"
    }
} catch {
    Add-Line ("  WARN: device query failed: " + $_.Exception.Message)
}
Add-Line ""

Add-Line "3. DeepLiveCam health summary"
$health = Get-ChildItem -LiteralPath $Logs -Filter "live_health_*.txt" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (!$health) {
    Add-Line "  WARN: no live_health_*.txt found"
} else {
    Add-Line ("  file=" + $health.FullName)
    $healthRaw = Get-Content -LiteralPath $health.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
    $healthLinesData = @($healthRaw | Where-Object { $_ -match "\[live-health\]" } | Select-Object -Last $HealthLines)
    $cameraLines = @($healthRaw | Where-Object { $_ -match "\[live-camera\]" } | Select-Object -Last 5)

    if ($cameraLines.Count -gt 0) {
        Add-Line "  recent camera lines:"
        foreach ($line in $cameraLines) {
            Add-Line ("    " + $line)
        }
    }

    if ($healthLinesData.Count -eq 0) {
        Add-Line "  WARN: no [live-health] lines found"
    } else {
        Add-Line ("  sampled_health_lines=" + $healthLinesData.Count)
        Add-Stat "process_fps" ($healthLinesData | ForEach-Object { Get-Number $_ "process_fps" }) 25 $null
        Add-Stat "camera_fps" ($healthLinesData | ForEach-Object { Get-Number $_ "camera_fps" }) 25 $null
        Add-Stat "miss_rate_percent" ($healthLinesData | ForEach-Object { Get-Percent $_ "miss_rate" }) $null 5
        Add-Stat "max_consecutive_missed" ($healthLinesData | ForEach-Object { Get-Number $_ "max_consecutive_missed" }) $null 2
        Add-Stat "queue_in" ($healthLinesData | ForEach-Object { Get-Number $_ "queue_in" }) $null 1
        Add-Stat "queue_out" ($healthLinesData | ForEach-Object { Get-Number $_ "queue_out" }) $null 1
        Add-Stat "avg_ms_total" ($healthLinesData | ForEach-Object { Get-Number $_ "avg_ms_total" }) $null 40
        Add-Stat "avg_ms_detect" ($healthLinesData | ForEach-Object { Get-Number $_ "avg_ms_detect" }) $null 18
        Add-Stat "avg_ms_swap" ($healthLinesData | ForEach-Object { Get-Number $_ "avg_ms_swap" }) $null 28
        Add-Stat "avg_ms_enhance" ($healthLinesData | ForEach-Object { Get-Number $_ "avg_ms_enhance" }) $null 8
    }
}
Add-Line ""

Add-Line "4. OBS and DroidCam output"
$obsLogDir = Join-Path $Root "obs-studio\config\obs-studio\logs"
if (!(Test-Path -LiteralPath $obsLogDir)) {
    Add-Line ("  WARN: OBS log directory not found: " + $obsLogDir)
} else {
    $obsLog = Get-ChildItem -LiteralPath $obsLogDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (!$obsLog) {
        Add-Line "  WARN: no OBS log found"
    } else {
        Add-Line ("  file=" + $obsLog.FullName)
        $obsText = Get-Content -LiteralPath $obsLog.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
        $obsMatches = @($obsText | Select-String -Pattern "Droidcam|DroidCam|AutoStart|webcam video active|webcam became inactive|Total frames output|Total drawn frames|window-capture|OBS Output|failed|lagged|skipped|stalled" -CaseSensitive:$false)
        if ($obsMatches.Count -eq 0) {
            Add-Line "  WARN: no matching OBS/DroidCam lines found"
        } else {
            foreach ($m in ($obsMatches | Select-Object -Last 80)) {
                Add-Line ("  " + $m.Line)
            }
        }
    }
}
Add-Line ""

Add-Line "5. WhatsApp network/process signals"
$wa = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "WhatsApp" }
if (!$wa) {
    Add-Line "  WARN: WhatsApp process not found"
} else {
    foreach ($p in $wa) {
        Add-Line ("  WhatsApp pid={0} title={1}" -f $p.Id, $p.MainWindowTitle)
        try {
            $tcp = Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq "Established" } |
                Select-Object -First 20
            if ($tcp) {
                foreach ($c in $tcp) {
                    Add-Line ("    tcp {0}:{1} -> {2}:{3} state={4}" -f $c.LocalAddress, $c.LocalPort, $c.RemoteAddress, $c.RemotePort, $c.State)
                }
            } else {
                Add-Line "    WARN: no established TCP connection found for WhatsApp process"
            }
        } catch {
            Add-Line ("    WARN: TCP query failed: " + $_.Exception.Message)
        }
    }
}
Add-Line ""

Add-Line "6. Network quick sample"
if ($SkipNetwork) {
    Add-Line "  skipped"
} else {
    $targets = @("1.1.1.1", "8.8.8.8", "www.whatsapp.com")
    foreach ($target in $targets) {
        try {
            $samples = @(Test-Connection -ComputerName $target -Count 5 -ErrorAction SilentlyContinue)
            if ($samples.Count -eq 0) {
                Add-Line ("  {0}: WARN timeout/loss=100%" -f $target)
            } else {
                $latencies = @($samples | ForEach-Object {
                    if ($null -ne $_.Latency) { [double]$_.Latency } else { [double]$_.ResponseTime }
                })
                $avg = ($latencies | Measure-Object -Average).Average
                $max = ($latencies | Measure-Object -Maximum).Maximum
                $loss = [math]::Round((1.0 - ($samples.Count / 5.0)) * 100.0, 1)
                $state = "OK"
                if ($loss -gt 0 -or $max -gt 180) { $state = "WARN" }
                Add-Line ("  {0}: avg_ms={1:N1} max_ms={2:N1} loss={3}% state={4}" -f $target, $avg, $max, $loss, $state)
            }
        } catch {
            Add-Line ("  {0}: WARN failed {1}" -f $target, $_.Exception.Message)
        }
    }
}
Add-Line ""

Add-Line "7. Interpretation guide"
Add-Line "  process_fps/camera_fps low: local capture or processing bottleneck."
Add-Line "  miss_rate/max_consecutive_missed high: local face lost, pose/edge/occlusion problem."
Add-Line "  queue_in/queue_out high: local processing cannot keep up."
Add-Line "  avg_ms_detect high: detector/tracker cost is high."
Add-Line "  avg_ms_swap high: face swap model cost is high."
Add-Line "  avg_ms_enhance high: enhancer/GPEN/GFPGAN cost is high."
Add-Line "  DroidCam inactive/stopping in OBS: virtual output chain problem."
Add-Line "  network loss/high max latency: WhatsApp quality can drop even if local output is sharp."
Add-Line ""
Add-Line ("Done: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))

Write-Output "Stability snapshot written:"
Write-Output $Report
