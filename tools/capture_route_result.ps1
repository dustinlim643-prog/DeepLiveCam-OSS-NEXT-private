param(
    [ValidateRange(10, 300)]
    [int]$Seconds = 30
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$report = Join-Path $Logs "route_test_$stamp.txt"
$samples = [System.Collections.Generic.List[object]]::new()

function Get-LatestObsLog {
    $dir = Join-Path $Root "obs-studio\config\obs-studio\logs"
    Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-ProcessSnapshot {
    $wanted = @("python", "obs64", "WhatsApp", "WhatsApp.Root", "HD-Player")
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $wanted -contains $_.ProcessName } |
        Select-Object ProcessName, Id, CPU, WorkingSet64
}

$start = Get-Date
$initial = Get-ProcessSnapshot
$initialCpu = @{}
foreach ($p in $initial) { $initialCpu[$p.Id] = [double]$p.CPU }

for ($i = 0; $i -lt $Seconds; $i++) {
    $gpuUtil = $null
    $gpuMem = $null
    $nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if ($nvidia) {
        $gpu = & $nvidia.Source --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        if ($gpu -match '^\s*(\d+)\s*,\s*(\d+)') {
            $gpuUtil = [int]$Matches[1]
            $gpuMem = [int]$Matches[2]
        }
    }
    $workingMb = ((Get-ProcessSnapshot | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
    $samples.Add([pscustomobject]@{ GPU = $gpuUtil; GPUMemoryMB = $gpuMem; WorkingSetMB = [math]::Round($workingMb, 1) })
    Start-Sleep -Seconds 1
}

$finish = Get-Date
$final = Get-ProcessSnapshot
$elapsed = [math]::Max(1, ($finish - $start).TotalSeconds)
$cpuLogical = [Environment]::ProcessorCount
$processRows = foreach ($p in $final) {
    $before = if ($initialCpu.ContainsKey($p.Id)) { $initialCpu[$p.Id] } else { [double]$p.CPU }
    [pscustomobject]@{
        Process = $p.ProcessName
        Id = $p.Id
        AverageCPUPercent = [math]::Round((([double]$p.CPU - $before) / $elapsed) * 100 / $cpuLogical, 1)
        MemoryMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
    }
}

$obsLog = Get-LatestObsLog
$obsEvidence = @()
if ($obsLog) {
    $obsEvidence = Get-Content -LiteralPath $obsLog.FullName -ErrorAction SilentlyContinue |
        Select-String -Pattern "DroidcamVirtualOut|webcam video active|Virtual Camera|virtualcam|lagged frames|frames missed|output.*start|output.*stop" -CaseSensitive:$false |
        Select-Object -Last 40 | ForEach-Object { $_.Line }
}

$health = Get-ChildItem -LiteralPath $Logs -Filter "live_health_*.txt" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$healthTail = if ($health) { Get-Content -LiteralPath $health.FullName -Tail 40 } else { @("No live health log found") }

$pythonWindows = Get-Process python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty MainWindowTitle
$hasObsOutput = @($pythonWindows | Where-Object { $_ -eq "OBS Output" }).Count -gt 0
$validWorkload = $hasObsOutput -and ($null -ne $health)

$obsTitle = Get-Process obs64 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty MainWindowTitle
$route = if ($obsTitle -match "DeepLiveCam-Mobile") { "MobileOBS" } elseif (Get-Process HD-Player -ErrorAction SilentlyContinue) { "AndroidEmulator" } elseif (Get-Process WhatsApp.Root -ErrorAction SilentlyContinue) { "Desktop" } else { "Unknown" }
$avgGpu = ($samples | Where-Object GPU -ne $null | Measure-Object GPU -Average).Average
$maxGpu = ($samples | Where-Object GPU -ne $null | Measure-Object GPU -Maximum).Maximum
$avgGpuMem = ($samples | Where-Object GPUMemoryMB -ne $null | Measure-Object GPUMemoryMB -Average).Average
$avgWorking = ($samples | Measure-Object WorkingSetMB -Average).Average

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("Video route test report")
$lines.Add("Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("Route: $route")
$lines.Add("SampleSeconds: $Seconds")
$lines.Add("Privacy: no video frames or screenshots were captured")
$lines.Add("OBSOutputWindowDetected: $hasObsOutput")
$lines.Add("ValidLiveWorkload: $validWorkload")
$lines.Add("ValidityRule: OBS Output window and live health log must both exist")
$lines.Add("")
$lines.Add("PERFORMANCE")
$lines.Add("AverageGPUPercent: $([math]::Round([double]$avgGpu,1))")
$lines.Add("MaximumGPUPercent: $([math]::Round([double]$maxGpu,1))")
$lines.Add("AverageGPUMemoryMB: $([math]::Round([double]$avgGpuMem,1))")
$lines.Add("AverageTrackedWorkingSetMB: $([math]::Round([double]$avgWorking,1))")
$lines.Add("")
$lines.Add("PROCESSES")
$lines.AddRange([string[]]($processRows | Format-Table -AutoSize | Out-String -Width 200 | ForEach-Object { $_ -split "`r?`n" }))
$lines.Add("")
$lines.Add("OBS EVIDENCE")
$lines.Add("Log: $($obsLog.FullName)")
$lines.AddRange([string[]]$obsEvidence)
$lines.Add("")
$lines.Add("LIVE HEALTH TAIL")
$lines.Add("Log: $($health.FullName)")
$lines.AddRange([string[]]$healthTail)
$lines.Add("")
$lines.Add("USER VISUAL RESULT (fill only after remote-phone observation)")
$lines.Add("Matches real phone portrait ratio: PASS / FAIL")
$lines.Add("Remote sharpness: 1-5")
$lines.Add("Remote motion smoothness: 1-5")
$lines.Add("Face realism: 1-5")
$lines.Add("Black bars or forced landscape: NONE / TOP_BOTTOM / LEFT_RIGHT / FORCED_LANDSCAPE")
$lines.Add("Conclusion: KEEP / REJECT")

if (!$validWorkload) {
    $lines.Add("")
    $lines.Add("AUTOMATIC VERDICT: INVALID SAMPLE")
    $lines.Add("Reason: real-time face-swap output was not confirmed; do not compare these performance numbers.")
}

Set-Content -LiteralPath $report -Encoding UTF8 -Value $lines
Write-Host "Route test report: $report"
