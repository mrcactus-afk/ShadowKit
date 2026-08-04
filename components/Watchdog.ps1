param([switch]$Silent)
$configPath = "C:\\ShadowKit\config.json"
$logDir = "C:\\ShadowKit\logs"
$logFile = Join-Path $logDir "watchdog.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $configPath)) { Write-Error "Config missing"; exit 1 }
$config = Get-Content $configPath | ConvertFrom-Json
$wdCfg = $config.watchdog
if (-not $wdCfg.enabled) { Write-Host "Watchdog disabled"; exit 0 }
$repairScript = $wdCfg.repairScript
$checkArgs = $wdCfg.checkArgs
$repairArgs = $wdCfg.repairArgs

function Write-WatchdogLog {
    param($Message, $Level = "info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $entry | Out-File -Append $logFile
    if (-not $Silent) {
        if ($Level -eq "error") { Write-Host $entry -ForegroundColor Red }
        else { Write-Host $entry -ForegroundColor Cyan }
    }
}

Write-WatchdogLog "Performing integrity check..."
try {
    & $repairScript $checkArgs -ErrorAction Stop
    $exit = $LASTEXITCODE
} catch { $exit = 1; Write-WatchdogLog "Check failed: $_" "error" }
if ($exit -ne 0) {
    Write-WatchdogLog "Drift detected. Running repair..." "warn"
    try {
        & $repairScript $repairArgs -Force -ErrorAction Stop
        if ($LASTEXITCODE -eq 0) { Write-WatchdogLog "Repair succeeded" }
        else { Write-WatchdogLog "Repair exit code $LASTEXITCODE" "error" }
    } catch { Write-WatchdogLog "Repair failed: $_" "error" }
} else {
    Write-WatchdogLog "Integrity OK"
}