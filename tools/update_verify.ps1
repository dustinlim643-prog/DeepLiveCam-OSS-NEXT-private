$ErrorActionPreference = "Continue"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Logs = Join-Path $Root "logs"
$Report = Join-Path $Logs "update_verify.txt"
$Failed = $false
$env:PATH = (Join-Path $Root "ffmpeg\bin") + ";" + (Join-Path $Root "python") + ";" + (Join-Path $Root "python\Scripts") + ";" + $env:PATH

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
Check-File "HyperSwap 256 model" (Join-Path $Root "models\hyperswap_1a_256.onnx")
Check-File "XSeg mask model" (Join-Path $Root "models\xseg.onnx")
Check-File "GPEN-256 model" (Join-Path $Root "models\GPEN-BFR-256.onnx")
Check-File "HyperSwap processor" (Join-Path $Root "modules\processors\frame\face_swapper_hyperswap.py")
Check-File "OBS Live Preview watcher" (Join-Path $Root "tools\wait_for_live_preview_and_restart_obs.ps1")
Check-File "start helper" (Join-Path $Root "tools\start_deeplivecam_obs.ps1")
Check-File "stop helper" (Join-Path $Root "tools\stop_deeplivecam_obs.ps1")
Check-File "OBS DeepLiveCam scene" (Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json")
Check-File "migration plan" (Join-Path $Root "FEATURE_MIGRATION_PLAN.zh-CN.md")
$UserGuideItem = Get-ChildItem -LiteralPath $Root -Filter "*.txt" -File | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $text -match "DeepLiveCam \+ OBS" -and $text -match "OBS Virtual Camera"
    } catch {
        $false
    }
} | Select-Object -First 1
if ($UserGuideItem) {
    Add-Line "OK user guide: $($UserGuideItem.FullName)"
} else {
    Add-Line "ERROR user guide not found by content"
    $Failed = $true
}

$LauncherFiles = Get-ChildItem -LiteralPath $Root -File | Where-Object { $_.Extension -in @(".cmd", ".bat") }
$StartScriptItem = $LauncherFiles | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match "start_deeplivecam_obs\.ps1"
    } catch {
        $false
    }
} | Select-Object -First 1
$StopScriptItem = $LauncherFiles | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match "stop_deeplivecam_obs\.ps1"
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

$RootLauncherNames = @($LauncherFiles | ForEach-Object { $_.Name } | Sort-Object)
$SelfCheckScriptItem = $LauncherFiles | Where-Object {
    try {
        $text = Get-Content -LiteralPath $_.FullName -Raw
        $text -match "tools\\update_verify\.ps1"
    } catch {
        $false
    }
} | Select-Object -First 1
if ($RootLauncherNames.Count -eq 3 -and $StartScriptItem -and $StopScriptItem -and $SelfCheckScriptItem) {
    Add-Line "OK root launcher list is clean: $($RootLauncherNames -join ', ')"
} else {
    Add-Line "ERROR root launcher list is not clean or incomplete: $($RootLauncherNames -join ', ')"
    Add-Line "Expected exactly 3 launchers by role: start, stop, self-check"
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
if ($HelpText -match "face_swapper_hyperswap") { Add-Line "OK HyperSwap processor is exposed" } else { Add-Line "ERROR HyperSwap processor is not exposed"; $Failed = $true }
if ($HelpText -match "--live-face-smooth") { Add-Line "OK --live-face-smooth exposed" } else { Add-Line "ERROR missing --live-face-smooth in run.py help"; $Failed = $true }
if ($HelpText -match "--live-face-fit-scale") { Add-Line "OK --live-face-fit-scale exposed" } else { Add-Line "ERROR missing --live-face-fit-scale in run.py help"; $Failed = $true }
if ($HelpText -match "--live-xseg-mask") { Add-Line "OK --live-xseg-mask exposed" } else { Add-Line "ERROR missing --live-xseg-mask in run.py help"; $Failed = $true }
if ($HelpText -match "--live-obs-output-window") { Add-Line "OK --live-obs-output-window exposed" } else { Add-Line "ERROR missing --live-obs-output-window in run.py help"; $Failed = $true }

Add-Line ""
Add-Line "Checking startup script parameters..."
if ($StartScriptItem) {
    $StartText = Get-Content -LiteralPath (Join-Path $Root "tools\start_deeplivecam_obs.ps1") -Raw
    if ($StartText -match "--live-fps-debug") { Add-Line "OK startup script has --live-fps-debug" } else { Add-Line "ERROR startup script missing --live-fps-debug"; $Failed = $true }
    if ($StartText -match "--execution-provider" -and $StartText -match '"cuda"') { Add-Line "OK startup script uses cuda provider" } else { Add-Line "ERROR startup script missing cuda provider"; $Failed = $true }
    if ($StartText -match "face_swapper_hyperswap") { Add-Line "OK startup script uses HyperSwap 256 swapper" } else { Add-Line "ERROR startup script is not using HyperSwap 256"; $Failed = $true }
    if ($StartText -notmatch "face_enhancer_gpen256") { Add-Line "OK startup script leaves GPEN disabled by default for FPS" } else { Add-Line "ERROR startup script should not enable GPEN by default"; $Failed = $true }
    if ($StartText -match "--live-face-smooth" -and $StartText -match '"0\.35"') { Add-Line "OK startup script enables single-face smoothing" } else { Add-Line "ERROR startup script missing live face smoothing"; $Failed = $true }
    if ($StartText -match "--live-face-fit-scale" -and $StartText -match '"1\.06"') { Add-Line "OK startup script enables face fit scale" } else { Add-Line "ERROR startup script missing face fit scale"; $Failed = $true }
    if ($StartText -match "--quality-preset" -and $StartText -match '"high_quality"') { Add-Line "OK startup script uses high_quality preset" } else { Add-Line "ERROR startup script missing high_quality preset"; $Failed = $true }
    if ($StartText -match "--live-xseg-mask") { Add-Line "OK startup script enables XSeg mask" } else { Add-Line "ERROR startup script missing XSeg mask"; $Failed = $true }
    if ($StartText -match "--live-obs-output-window") { Add-Line "OK startup script enables OBS output window" } else { Add-Line "ERROR startup script missing OBS output window"; $Failed = $true }
    if ($StartText -match "wait_for_live_preview_and_restart_obs\.ps1") { Add-Line "OK startup script refreshes OBS after OBS Output appears" } else { Add-Line "ERROR startup script missing OBS Output watcher"; $Failed = $true }
} else {
    Add-Line "ERROR startup script parameter check skipped because start script was not found"
    $Failed = $true
}

Add-Line ""
Add-Line "Checking OBS capture target..."
$ScenePath = Join-Path $Root "obs-studio\config\obs-studio\basic\scenes\DeepLiveCam.json"
$SceneText = if (Test-Path -LiteralPath $ScenePath) { Get-Content -LiteralPath $ScenePath -Raw } else { "" }
if ($SceneText -match "OBS Output:HighGUI class:python.exe") { Add-Line "OK OBS targets OBS Output" } else { Add-Line "ERROR OBS scene is not targeting OBS Output"; $Failed = $true }
if ($SceneText -match '"method":\s*1') { Add-Line "OK OBS window capture uses BitBlt compatibility mode" } else { Add-Line "ERROR OBS window capture is not using BitBlt compatibility mode"; $Failed = $true }
if ($SceneText -match '"x":\s*1280' -and $SceneText -match '"y":\s*720') { Add-Line "OK OBS scene contains 1280x720 sizing" } else { Add-Line "ERROR OBS scene missing 1280x720 sizing"; $Failed = $true }
if ($SceneText -match "DeepLiveCam OBS Output") { Add-Line "OK OBS source is named for OBS Output" } else { Add-Line "ERROR OBS source is not named for OBS Output"; $Failed = $true }
if ($SceneText -match "sharpness_filter") { Add-Line "OK OBS sharpen filter found" } else { Add-Line "WARN OBS sharpen filter not found" }
if ($SceneText -match "color_filter") { Add-Line "OK OBS color filter found" } else { Add-Line "WARN OBS color filter not found" }

Add-Line ""
Add-Line "Checking HyperSwap ONNX runtime..."
$HyperSwapCheck = @'
from pathlib import Path
import onnxruntime as ort
root = Path(r"__ROOT__")
path = root / "models" / "hyperswap_1a_256.onnx"
session = ort.InferenceSession(str(path), providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
providers = session.get_providers()
inputs = {inp.name: inp.shape for inp in session.get_inputs()}
outputs = {out.name: out.shape for out in session.get_outputs()}
assert inputs.get("source") == [1, 512], inputs
assert inputs.get("target") == [1, 3, 256, 256], inputs
assert outputs.get("output") == [1, 3, 256, 256], outputs
assert "CUDAExecutionProvider" in providers, providers
print("OK HyperSwap providers: " + ", ".join(providers))
'@
$HyperSwapCheck = $HyperSwapCheck.Replace("__ROOT__", $Root)
$HyperSwapCheckPath = Join-Path $Logs "hyperswap_onnx_check.py"
Set-Content -LiteralPath $HyperSwapCheckPath -Encoding UTF8 -Value $HyperSwapCheck
& $Python $HyperSwapCheckPath *>> $Report
if ($LASTEXITCODE -eq 0) {
    Add-Line "OK HyperSwap ONNX IO and CUDA provider passed"
} else {
    Add-Line "ERROR HyperSwap ONNX IO/CUDA provider check failed"
    $Failed = $true
}

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
    "modules\face_analyser.py",
    "modules\ui.py",
    "modules\face_analyser.py",
    "modules\processors\frame\core.py",
    "modules\processors\frame\face_swapper.py",
    "modules\processors\frame\face_swapper_hyperswap.py",
    "modules\processors\frame\face_enhancer.py",
    "modules\processors\frame\face_enhancer_gpen256.py",
    "modules\processors\frame\face_enhancer_gpen512.py"
)
& $Python -m py_compile @CompileFiles *>> $Report
if ($LASTEXITCODE -eq 0) { Add-Line "OK Python compile passed" } else { Add-Line "ERROR Python compile failed"; $Failed = $true }

Add-Line ""
Add-Line "Checking PowerShell script syntax..."
$PsScripts = @(
    "tools\reset_obs_scene.ps1",
    "tools\update_verify.ps1",
    "tools\wait_for_live_preview_and_restart_obs.ps1",
    "tools\start_deeplivecam_obs.ps1",
    "tools\stop_deeplivecam_obs.ps1"
)
foreach ($PsScript in $PsScripts) {
    $PsPath = Join-Path $Root $PsScript
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($PsPath, [ref]$null, [ref]$null)
        Add-Line "OK PowerShell syntax: $PsScript"
    } catch {
        Add-Line "ERROR PowerShell syntax failed: $PsScript - $($_.Exception.Message)"
        $Failed = $true
    }
}

Add-Line ""
if ($Failed) {
    Add-Line "RESULT: FAIL"
    Get-Content -LiteralPath $Report
    exit 1
}

Add-Line "RESULT: PASS"
Get-Content -LiteralPath $Report
exit 0
