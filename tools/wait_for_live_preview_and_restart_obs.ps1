$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogPath = Join-Path $Root "logs\operation_log.txt"
$ObsExe = Join-Path $Root "obs-studio\bin\64bit\obs64.exe"
$ObsDir = Join-Path $Root "obs-studio\bin\64bit"
$ResetScript = Join-Path $Root "tools\reset_obs_scene.ps1"

if (!(Test-Path -LiteralPath (Split-Path $LogPath))) {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) | Out-Null
}

function Write-OpLog($Text) {
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " " + $Text)
}

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ObsWindowFinder {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
}
'@

function Test-ObsOutputWindow {
    $found = $false
    [ObsWindowFinder]::EnumWindows({
        param($handle, $param)
        if (![ObsWindowFinder]::IsWindowVisible($handle)) {
            return $true
        }
        $title = New-Object System.Text.StringBuilder 256
        [void][ObsWindowFinder]::GetWindowText($handle, $title, $title.Capacity)
        if ($title.ToString() -eq "OBS Output") {
            $script:found = $true
            return $false
        }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    return $found
}

Write-OpLog "OBS watcher waiting for OBS Output"

$deadline = (Get-Date).AddMinutes(10)
$seen = $false
while ((Get-Date) -lt $deadline) {
    if (Test-ObsOutputWindow) {
        $seen = $true
        break
    }
    Start-Sleep -Seconds 2
}

if (!$seen) {
    Write-OpLog "OBS watcher timeout: OBS Output was not detected"
    exit 0
}

Write-OpLog "OBS watcher detected OBS Output, refreshing OBS capture"

Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like ($Root + "*") } |
    ForEach-Object {
        $null = $_.CloseMainWindow()
    }
Start-Sleep -Seconds 3
Get-Process obs64,obs32,obs -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like ($Root + "*") } |
    Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item -LiteralPath (Join-Path $Root "obs-studio\config\obs-studio\.sentinel") -Recurse -Force -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $ResetScript | Out-Null

if (Test-Path -LiteralPath $ObsExe) {
    Start-Process -FilePath $ObsExe -WorkingDirectory $ObsDir -ArgumentList @("--portable", "--collection", "DeepLiveCam", "--scene", "DeepLiveCam", "--startvirtualcam") -WindowStyle Hidden
    Write-OpLog "OBS watcher restarted OBS after OBS Output appeared"
}
