$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SceneDir = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes"
$DesktopScene = Join-Path $SceneDir "DeepLiveCam.json"
$MobileScene = Join-Path $SceneDir "DeepLiveCam-Mobile.json"

if (!(Test-Path -LiteralPath $DesktopScene)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "reset_obs_scene.ps1") | Out-Null
}

$config = Get-Content -LiteralPath $DesktopScene -Raw -Encoding UTF8 | ConvertFrom-Json
$config.name = "DeepLiveCam-Mobile"
$config.current_scene = "DeepLiveCam-Mobile"
$config.current_program_scene = "DeepLiveCam-Mobile"
$config.resolution.x = 720
$config.resolution.y = 1280
$config.scene_order[0].name = "DeepLiveCam-Mobile"

$scene = $config.sources | Where-Object { $_.id -eq "scene" } | Select-Object -First 1
$scene.name = "DeepLiveCam-Mobile"
$scene.settings.items[0].pos.x = 0.0
$scene.settings.items[0].pos.y = 0.0
$scene.settings.items[0].align = 5
$scene.settings.items[0].bounds_type = 0
$scene.settings.items[0].bounds_align = 5
$scene.settings.items[0].crop_left = 437
$scene.settings.items[0].crop_right = 438
$scene.settings.items[0].crop_top = 0
$scene.settings.items[0].crop_bottom = 0
$scene.settings.items[0].scale_ref.x = 1280.0
$scene.settings.items[0].scale_ref.y = 720.0
$scene.settings.items[0].scale.x = 1.7777778
$scene.settings.items[0].scale.y = 1.7777778
$scene.settings.items[0].scale_rel.x = 1.7777778
$scene.settings.items[0].scale_rel.y = 1.7777778
$scene.settings.items[0].bounds.x = 720.0
$scene.settings.items[0].bounds.y = 1280.0
$scene.settings.items[0].scale_filter = "lanczos"
$scene.settings.items[0].PSObject.Properties.Remove("pos_rel")
$scene.settings.items[0].PSObject.Properties.Remove("bounds_rel")

$json = $config | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($MobileScene, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output "OBS mobile scene rebuilt at 720x1280 with deterministic 9:16 center crop."
