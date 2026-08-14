$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SceneDir = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes"
$ScenePath = Join-Path $SceneDir "DeepLiveCam.json"

if (!(Test-Path -LiteralPath $SceneDir)) {
    New-Item -ItemType Directory -Path $SceneDir | Out-Null
}

if (Test-Path -LiteralPath $ScenePath) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item -LiteralPath $ScenePath -Destination "$ScenePath.bak_$stamp" -Force
}

$windowSourceUuid = "350903a8-0f4f-4ee7-b240-ad0bee11a0cc"
$sceneUuid = "6c379030-2b5b-4873-9e8f-7fa9527a3ffc"

$sceneConfig = [ordered]@{
    name = "DeepLiveCam"
    sources = @(
        [ordered]@{
            prev_ver = 537001985
            name = "DeepLiveCam Live Preview"
            uuid = $windowSourceUuid
            id = "window_capture"
            versioned_id = "window_capture"
            settings = [ordered]@{
                priority = 1
                window = "Live Preview:Qt625QWindowIcon:python.exe"
                method = 2
                cursor = $false
                compatibility = $false
                client_area = $true
            }
            mixers = 0
            sync = 0
            flags = 0
            volume = 1.0
            balance = 0.5
            enabled = $true
            muted = $false
            "push-to-mute" = $false
            "push-to-mute-delay" = 0
            "push-to-talk" = $false
            "push-to-talk-delay" = 0
            hotkeys = [ordered]@{
                "libobs.mute" = @()
                "libobs.unmute" = @()
                "libobs.push-to-mute" = @()
                "libobs.push-to-talk" = @()
            }
            deinterlace_mode = 0
            deinterlace_field_order = 0
            monitoring_type = 0
            private_settings = [ordered]@{}
            filters = @(
                [ordered]@{
                    prev_ver = 537001985
                    name = "01 Sharpen"
                    uuid = "9ff9789e-6fac-4e99-8cd3-4eb59bca006c"
                    id = "sharpness_filter"
                    versioned_id = "sharpness_filter"
                    settings = [ordered]@{ sharpness = 0.18 }
                    mixers = 0
                    sync = 0
                    flags = 0
                    volume = 1.0
                    balance = 0.5
                    enabled = $true
                    muted = $false
                    "push-to-mute" = $false
                    "push-to-mute-delay" = 0
                    "push-to-talk" = $false
                    "push-to-talk-delay" = 0
                    hotkeys = [ordered]@{}
                    deinterlace_mode = 0
                    deinterlace_field_order = 0
                    monitoring_type = 0
                    private_settings = [ordered]@{}
                },
                [ordered]@{
                    prev_ver = 537001985
                    name = "02 Color Stable"
                    uuid = "8c429d63-8137-4085-a9e3-a72652c86b55"
                    id = "color_filter"
                    versioned_id = "color_filter"
                    settings = [ordered]@{
                        contrast = 0.06
                        brightness = 0
                        saturation = 0.04
                        hue_shift = 0
                        opacity = 1
                    }
                    mixers = 0
                    sync = 0
                    flags = 0
                    volume = 1.0
                    balance = 0.5
                    enabled = $true
                    muted = $false
                    "push-to-mute" = $false
                    "push-to-mute-delay" = 0
                    "push-to-talk" = $false
                    "push-to-talk-delay" = 0
                    hotkeys = [ordered]@{}
                    deinterlace_mode = 0
                    deinterlace_field_order = 0
                    monitoring_type = 0
                    private_settings = [ordered]@{}
                }
            )
        },
        [ordered]@{
            prev_ver = 537001985
            name = "DeepLiveCam"
            uuid = $sceneUuid
            id = "scene"
            versioned_id = "scene"
            settings = [ordered]@{
                id_counter = 1
                custom_size = $false
                items = @(
                    [ordered]@{
                        name = "DeepLiveCam Live Preview"
                        source_uuid = $windowSourceUuid
                        visible = $true
                        locked = $true
                        rot = 0.0
                        scale_ref = [ordered]@{ x = 1280.0; y = 720.0 }
                        align = 5
                        bounds_type = 2
                        bounds_align = 5
                        bounds_crop = $false
                        crop_left = 0
                        crop_top = 0
                        crop_right = 0
                        crop_bottom = 0
                        id = 1
                        group_item_backup = $false
                        pos = [ordered]@{ x = 0.0; y = 0.0 }
                        scale = [ordered]@{ x = 1.0; y = 1.0 }
                        scale_rel = [ordered]@{ x = 1.0; y = 1.0 }
                        bounds = [ordered]@{ x = 1280.0; y = 720.0 }
                        scale_filter = "lanczos"
                        blend_method = "default"
                        blend_type = "normal"
                        show_transition = [ordered]@{ duration = 0 }
                        hide_transition = [ordered]@{ duration = 0 }
                        private_settings = [ordered]@{}
                    }
                )
            }
            mixers = 0
            sync = 0
            flags = 0
            volume = 1.0
            balance = 0.5
            enabled = $true
            muted = $false
            "push-to-mute" = $false
            "push-to-mute-delay" = 0
            "push-to-talk" = $false
            "push-to-talk-delay" = 0
            hotkeys = [ordered]@{
                "OBSBasic.SelectScene" = @()
                "libobs.show_scene_item.1" = @()
                "libobs.hide_scene_item.1" = @()
            }
            deinterlace_mode = 0
            deinterlace_field_order = 0
            monitoring_type = 0
            canvas_uuid = "6c69626f-6273-4c00-9d88-c5136d61696e"
            private_settings = [ordered]@{}
        }
    )
    groups = @()
    scene_order = @([ordered]@{ name = "DeepLiveCam" })
    current_scene = "DeepLiveCam"
    current_program_scene = "DeepLiveCam"
    canvases = @()
    current_transition = "Fade"
    transition_duration = 300
    transitions = @()
    quick_transitions = @()
    saved_projectors = @()
    preview_locked = $false
    scaling_enabled = $false
    scaling_level = -12
    scaling_off_x = 0.0
    scaling_off_y = 0.0
    "virtual-camera" = [ordered]@{ type2 = 3 }
    modules = [ordered]@{
        "scripts-tool" = @()
        "output-timer" = [ordered]@{
            streamTimerHours = 0
            streamTimerMinutes = 0
            streamTimerSeconds = 30
            recordTimerHours = 0
            recordTimerMinutes = 0
            recordTimerSeconds = 30
            autoStartStreamTimer = $false
            autoStartRecordTimer = $false
            pauseRecordTimer = $true
        }
        "auto-scene-switcher" = [ordered]@{
            interval = 300
            non_matching_scene = ""
            switch_if_not_matching = $false
            active = $false
            switches = @()
        }
        captions = [ordered]@{
            source = ""
            enabled = $false
            lang_id = 2052
            provider = "mssapi"
        }
    }
    resolution = [ordered]@{ x = 1280; y = 720 }
    version = 2
}

$sceneConfig | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $ScenePath -Encoding UTF8
Write-Output "OBS scene rebuilt for Live Preview at 1280x720."
