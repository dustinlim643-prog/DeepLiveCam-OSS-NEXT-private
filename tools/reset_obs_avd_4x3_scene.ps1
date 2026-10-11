$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SceneDir = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes"
$DesktopScene = Join-Path $SceneDir "DeepLiveCam.json"
$AvdScene = Join-Path $SceneDir "DeepLiveCam-AVD-4x3.json"

if (!(Test-Path -LiteralPath $DesktopScene)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "reset_obs_scene.ps1") | Out-Null
}

$config = Get-Content -LiteralPath $DesktopScene -Raw -Encoding UTF8 | ConvertFrom-Json
$sceneName = "DeepLiveCam-AVD-4x3"
$config.name = $sceneName
$config.current_scene = $sceneName
$config.current_program_scene = $sceneName
$config.resolution.x = 640
$config.resolution.y = 480
$config.scene_order[0].name = $sceneName

$scene = $config.sources | Where-Object { $_.id -eq "scene" } | Select-Object -First 1
if (!$scene -or !$scene.settings.items -or $scene.settings.items.Count -lt 1) {
    throw "Stable OBS scene item was not found."
}
$scene.name = $sceneName

# The DeepLiveCam window is 1280x720. Crop it to 960x720 (4:3), then
# scale it to the exact 640x480 stream requested by the AVD Camera HAL.
$item = $scene.settings.items[0]
$item.pos.x = 0.0
$item.pos.y = 0.0
$item.rot = 0.0
$item.align = 5
$item.bounds_type = 2
$item.bounds_align = 5
$item.bounds_crop = $false
$item.crop_left = 160
$item.crop_top = 0
$item.crop_right = 160
$item.crop_bottom = 0
$item.scale_ref.x = 640.0
$item.scale_ref.y = 480.0
$item.scale.x = 1.0
$item.scale.y = 1.0
$item.scale_rel.x = 1.0
$item.scale_rel.y = 1.0
$item.bounds.x = 640.0
$item.bounds.y = 480.0
$item.scale_filter = "lanczos"
$item.PSObject.Properties.Remove("pos_rel")
$item.PSObject.Properties.Remove("bounds_rel")

$json = $config | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($AvdScene, $json, [System.Text.UTF8Encoding]::new($false))
Write-Output "OBS AVD 4:3 scene rebuilt: input crop=160/160, canvas=640x480, no embedded black bars."
