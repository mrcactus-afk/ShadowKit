# Update-ShadowKit.ps1 - Self-update with validation and rollback
param([switch]$Force, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
$logFile = Join-Path $baseDir 'logs\update.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
function Write-UpdateLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

Write-UpdateLog 'Update started.'
Set-Location $baseDir

# 1. Check if git repo exists
if (-not (Test-Path (Join-Path $baseDir '.git'))) {
    Write-UpdateLog 'Not a git repository. Update requires git clone.' error
    if (-not $Silent) { Write-Host 'Update failed: not a git repo.' -ForegroundColor Red }
    exit 1
}

# 2. Capture current commit for rollback
$currentCommit = git rev-parse HEAD 2>$null
if (-not $currentCommit) {
    Write-UpdateLog 'Could not determine current commit.' warn
}

# 3. Pull latest
try {
    $pullOutput = git pull origin main 2>&1
    $pullExit = $LASTEXITCODE
    $pullOutput | Out-String | ForEach-Object { Write-UpdateLog "git pull: $_" }
    if ($pullExit -ne 0) {
        Write-UpdateLog 'git pull failed.' error
        if ($currentCommit) {
            git reset --hard $currentCommit 2>$null | Out-Null
            Write-UpdateLog "Rolled back to $currentCommit"
        }
        if (-not $Silent) { Write-Host 'Update failed. Rolled back.' -ForegroundColor Red }
        exit 1
    }
} catch {
    Write-UpdateLog "Update exception: $_" error
    if ($currentCommit) {
        git reset --hard $currentCommit 2>$null | Out-Null
        Write-UpdateLog "Rolled back to $currentCommit"
    }
    if (-not $Silent) { Write-Host 'Update failed with exception. Rolled back.' -ForegroundColor Red }
    exit 1
}

# 4. Restart controller if running
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ShadowController.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 2
    Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$baseDir\ShadowController.ps1`""
    Write-UpdateLog 'Controller restarted.'
} catch {
    Write-UpdateLog "Controller restart failed: $_" warn
}

Write-UpdateLog 'Update completed successfully.'
if (-not $Silent) { Write-Host 'Update completed.' -ForegroundColor Green }
exit 0
