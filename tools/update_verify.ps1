$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$Report = Join-Path $Logs "update_verify.txt"
$Failed = $false

if (!(Test-Path -LiteralPath $Logs)) {
    New-Item -ItemType Directory -Path $Logs | Out-Null
}

function Add-Line($Text) {
    Add-Content -LiteralPath $Report -Encoding UTF8 -Value $Text
}

function Check-File($Label, $Path) {
    if (Test-Path -LiteralPath $Path) {
        Add-Line "OK $Label`: $Path"
    } else {
        Add-Line "ERROR missing $Label`: $Path"
        $script:Failed = $true
    }
}

Set-Content -LiteralPath $Report -Encoding UTF8 -Value "DeepLiveCam OSS update verification"
Add-Line ("Time: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Add-Line "Root: $Root"
Add-Line ""

Check-File "python runtime" (Join-Path $Root "python\python.exe")
Check-File "ffmpeg" (Join-Path $Root "ffmpeg\bin\ffmpeg.exe")
Check-File "OBS executable" (Join-Path $Root "obs-studio\bin\64bit\obs64.exe")
Check-File "OBS portable marker" (Join-Path $Root "obs-studio\portable_mode.txt")
Check-File "inswapper model" (Join-Path $Root "models\inswapper_128.onnx")
Check-File "inswapper fp16 model" (Join-Path $Root "models\inswapper_128_fp16.onnx")
Check-File "GPEN-256 model" (Join-Path $Root "models\GPEN-BFR-256.onnx")
Check-File "OBS DeepLiveCam scene" (Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json")
Check-File "migration plan" (Join-Path $Root "FEATURE_MIGRATION_PLAN.zh-CN.md")
Check-File "user guide" (Join-Path $Root "使用说明.txt")

$BatFiles = Get-ChildItem -LiteralPath $Root -Filter "*.bat" -File
$StartScriptItem = $BatFiles | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match "run.py" -and $text -match "--startvirtualcam"
    } catch {
        $false
    }
} | Select-Object -First 1
$StopScriptItem = $BatFiles | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match "DeepLiveCam and OBS stopped"
    } catch {
        $false
    }
} | Select-Object -First 1

if ($StartScriptItem) {
    Add-Line "OK start script: $($StartScriptItem.FullName)"
} else {
    Add-Line "ERROR start script not found by content"
    $Failed = $true
}
if ($StopScriptItem) {
    Add-Line "OK stop script: $($StopScriptItem.FullName)"
} else {
    Add-Line "ERROR stop script not found by content"
    $Failed = $true
}

$RootBatNames = @($BatFiles | ForEach-Object { $_.Name } | Sort-Object)
$ExpectedBatNames = @("停止_DeepLiveCam_OBS.bat", "启动_DeepLiveCam_OBS.bat", "更新后自检验证.bat")
$UnexpectedBatNames = @($RootBatNames | Where-Object { $_ -notin $ExpectedBatNames })
$MissingBatNames = @($ExpectedBatNames | Where-Object { $_ -notin $RootBatNames })
if ($UnexpectedBatNames.Count -eq 0 -and $MissingBatNames.Count -eq 0) {
    Add-Line "OK root launcher list is clean: $($RootBatNames -join ', ')"
} else {
    if ($UnexpectedBatNames.Count -gt 0) { Add-Line "ERROR unexpected root bat files: $($UnexpectedBatNames -join ', ')"; $Failed = $true }
    if ($MissingBatNames.Count -gt 0) { Add-Line "ERROR missing root bat files: $($MissingBatNames -join ', ')"; $Failed = $true }
}

$Python = Join-Path $Root "python\python.exe"
$RunPy = Join-Path $Root "run.py"
$HelpOut = Join-Path $Logs "run_help.txt"

Add-Line ""
Add-Line "Checking command line parameters..."
& $Python $RunPy --help *> $HelpOut
$HelpText = Get-Content -LiteralPath $HelpOut -Raw
if ($HelpText -match "--live-fps-debug") { Add-Line "OK --live-fps-debug exposed" } else { Add-Line "ERROR missing --live-fps-debug in run.py help"; $Failed = $true }
if ($HelpText -match "--similar-face-distance") { Add-Line "OK --similar-face-distance exposed" } else { Add-Line "ERROR missing --similar-face-distance in run.py help"; $Failed = $true }
if ($HelpText -match "--quality-preset") { Add-Line "OK --quality-preset exposed" } else { Add-Line "ERROR missing --quality-preset in run.py help"; $Failed = $true }

Add-Line ""
Add-Line "Checking startup script parameters..."
if ($StartScriptItem) {
    $StartText = Get-Content -LiteralPath $StartScriptItem.FullName -Raw
    if ($StartText -match "--live-fps-debug") { Add-Line "OK startup script has --live-fps-debug" } else { Add-Line "ERROR startup script missing --live-fps-debug"; $Failed = $true }
    if ($StartText -match "--execution-provider cuda") { Add-Line "OK startup script uses cuda provider" } else { Add-Line "ERROR startup script missing cuda provider"; $Failed = $true }
    if ($StartText -match "face_enhancer_gpen256") { Add-Line "OK startup script enables GPEN-256 detail enhancer" } else { Add-Line "ERROR startup script missing GPEN-256 detail enhancer"; $Failed = $true }
    if ($StartText -match "--quality-preset balanced") { Add-Line "OK startup script uses balanced quality preset" } else { Add-Line "ERROR startup script missing balanced quality preset"; $Failed = $true }
} else {
    Add-Line "ERROR startup script parameter check skipped because start script was not found"
    $Failed = $true
}

Add-Line ""
Add-Line "Checking OBS capture target..."
$ScenePath = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json"
$SceneText = if (Test-Path -LiteralPath $ScenePath) { Get-Content -LiteralPath $ScenePath -Raw } else { "" }
if ($SceneText -match "Live Preview:Qt625QWindowIcon:python.exe") { Add-Line "OK OBS targets Live Preview" } else { Add-Line "ERROR OBS scene is not targeting Live Preview"; $Failed = $true }
if ($SceneText -match '"x":\s*1280' -and $SceneText -match '"y":\s*720') { Add-Line "OK OBS scene contains 1280x720 sizing" } else { Add-Line "ERROR OBS scene missing 1280x720 sizing"; $Failed = $true }
if ($SceneText -match "sharpness_filter") { Add-Line "OK OBS sharpen filter found" } else { Add-Line "WARN OBS sharpen filter not found" }
if ($SceneText -match "color_filter") { Add-Line "OK OBS color filter found" } else { Add-Line "WARN OBS color filter not found" }

Add-Line ""
Add-Line "Checking git noise..."
$TrackedNoise = (& git -C $Root status --porcelain=v1)
if (($TrackedNoise | Measure-Object).Count -eq 0) {
    Add-Line "OK git tracked/untracked status is clean"
} else {
    Add-Line "ERROR git has visible tracked/untracked changes:"
    $TrackedNoise | ForEach-Object { Add-Line $_ }
    $Failed = $true
}
$IgnoredCount = ((& git -C $Root ls-files --others -i --exclude-standard) | Measure-Object).Count
Add-Line "INFO ignored runtime/dependency files hidden from normal git status: $IgnoredCount"

Add-Line ""
Add-Line "Checking Python syntax..."
$CompileFiles = @(
    "modules\globals.py",
    "modules\core.py",
    "modules\ui.py",
    "modules\face_analyser.py",
    "modules\processors\frame\core.py",
    "modules\processors\frame\face_swapper.py",
    "modules\processors\frame\face_enhancer.py",
    "modules\processors\frame\face_enhancer_gpen256.py",
    "modules\processors\frame\face_enhancer_gpen512.py"
)
& $Python -m py_compile @CompileFiles *>> $Report
if ($LASTEXITCODE -eq 0) { Add-Line "OK Python compile passed" } else { Add-Line "ERROR Python compile failed"; $Failed = $true }

Add-Line ""
if ($Failed) {
    Add-Line "RESULT: FAIL"
    Get-Content -LiteralPath $Report
    exit 1
}

Add-Line "RESULT: PASS"
Get-Content -LiteralPath $Report
exit 0
