param(
    [int]$Seconds = 180
)

$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Report = Join-Path $Logs "whatsapp_quality_$stamp.txt"
$ScenePath = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json"
$ProfileRoot = Join-Path $Root "obs-studio\config\obs-studio\basic\profiles"

function Add-Line($Text) {
    Add-Content -LiteralPath $Report -Encoding UTF8 -Value $Text
}

Add-Line "WhatsApp quality diagnostic"
Add-Line ("Time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Add-Line "Root: $Root"
Add-Line ""

Add-Line "OBS profile video settings:"
Get-ChildItem -LiteralPath $ProfileRoot -Recurse -Filter basic.ini -ErrorAction SilentlyContinue | ForEach-Object {
    Add-Line ("Profile: " + $_.FullName)
    Get-Content -LiteralPath $_.FullName | Select-String -Pattern "BaseCX|BaseCY|OutputCX|OutputCY|FPSCommon|DroidCamVirtualOutput|AutoStart" | ForEach-Object {
        Add-Line ("  " + $_.Line)
    }
}

Add-Line ""
Add-Line "OBS scene effective source placement:"
if (Test-Path -LiteralPath $ScenePath) {
    try {
        $scene = Get-Content -LiteralPath $ScenePath -Raw | ConvertFrom-Json
        $scene.resolution | ConvertTo-Json -Compress | ForEach-Object { Add-Line ("  canvas=" + $_) }
        $scene.sources | Where-Object { $_.id -eq "scene" } | ForEach-Object {
            $_.settings.items | ForEach-Object {
                Add-Line ("  item=" + $_.name)
                Add-Line ("  pos=" + ($_.pos | ConvertTo-Json -Compress))
                Add-Line ("  bounds=" + ($_.bounds | ConvertTo-Json -Compress))
                Add-Line ("  scale_ref=" + ($_.scale_ref | ConvertTo-Json -Compress))
            }
        }
    } catch {
        Add-Line ("  failed to parse scene: " + $_.Exception.Message)
    }
} else {
    Add-Line "  scene file not found"
}

Add-Line ""
Add-Line "Running processes:"
Get-Process | Where-Object { $_.ProcessName -match "python|obs64|WhatsApp" } | ForEach-Object {
    Add-Line ("  {0} pid={1} cpu={2} start={3}" -f $_.ProcessName, $_.Id, $_.CPU, $_.StartTime)
}

Add-Line ""
Add-Line "WhatsApp TCP connections:"
$wa = Get-Process | Where-Object { $_.ProcessName -match "WhatsApp" }
foreach ($p in $wa) {
    Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Line ("  pid={0} state={1} local={2}:{3} remote={4}:{5}" -f $p.Id, $_.State, $_.LocalAddress, $_.LocalPort, $_.RemoteAddress, $_.RemotePort)
    }
}

Add-Line ""
Add-Line "Network ping sample:"
$targets = @("1.1.1.1", "8.8.8.8", "www.whatsapp.com")
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    foreach ($target in $targets) {
        $t = Get-Date -Format "HH:mm:ss"
        $result = Test-Connection -ComputerName $target -Count 1 -ErrorAction SilentlyContinue
        if ($result) {
            $latency = ($result | Select-Object -First 1).Latency
            if ($null -eq $latency) {
                $latency = ($result | Select-Object -First 1).ResponseTime
            }
            Add-Line ("  {0} {1} ok latency_ms={2}" -f $t, $target, $latency)
        } else {
            Add-Line ("  {0} {1} timeout" -f $t, $target)
        }
    }
    Start-Sleep -Seconds 5
}

Add-Line ""
Add-Line ("Done: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Output $Report
