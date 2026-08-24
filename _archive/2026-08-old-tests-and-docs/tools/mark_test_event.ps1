$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

$eventText = Read-Host "输入测试事件，例如：开始静止 / 开始快速转头 / WhatsApp变糊 / 结束"
if ([string]::IsNullOrWhiteSpace($eventText)) {
    $eventText = "未命名测试事件"
}

$day = Get-Date -Format "yyyyMMdd"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$line = "$stamp [test-event] $eventText"

Add-Content -LiteralPath (Join-Path $Logs "live_health_$day.txt") -Encoding UTF8 -Value $line
Add-Content -LiteralPath (Join-Path $Logs "operation_log.txt") -Encoding UTF8 -Value $line

Write-Host "已记录：$line"
