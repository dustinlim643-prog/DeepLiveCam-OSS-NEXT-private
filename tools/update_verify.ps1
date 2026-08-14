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
Check-File "OBS DeepLiveCam scene" (Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json")
Check-File "migration plan" (Join-Path $Root "FEATURE_MIGRATION_PLAN.zh-CN.md")

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
        $text -match "Stop-Process" -and $text -match "obs64"
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
if ($SceneText -match "sharpness_filter") { Add-Line "OK OBS sharpen filter found" } else { Add-Line "WARN OBS sharpen filter not found" }
if ($SceneText -match "color_filter") { Add-Line "OK OBS color filter found" } else { Add-Line "WARN OBS color filter not found" }

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
