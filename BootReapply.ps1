# BootReapply.ps1 - Reapplies Tier1 optimizations at boot
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
$logFile = Join-Path $baseDir 'logs\bootreapply.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
function Write-BootLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

# Use mutex to prevent concurrent runs
$mutexName = 'Global\ShadowKitBootReapplyMutex'
try {
    $existing = [System.Threading.Mutex]::OpenExisting($mutexName)
    Write-BootLog 'Another boot reapply running. Exiting.' warn
    exit 0
} catch {
    $mtx = New-Object System.Threading.Mutex($false, $mutexName)
    try { if (-not $mtx.WaitOne(0)) { Write-BootLog 'Mutex contention. Exiting.' warn; exit 0 } }
    catch { Write-BootLog "Mutex error: $_" error; exit 1 }
}

Write-BootLog 'Boot reapply started.'

if (-not (Test-Path $baseDir)) { Write-BootLog 'ShadowKit folder missing. Exiting.' error; exit 1 }

# Run Tier1 Apply script
try {
    $tier1 = Join-Path $baseDir 'Tier1-Apply.ps1'
    if (Test-Path $tier1) {
        & $tier1
        Write-BootLog 'Tier1 optimizations re-applied.'
    } else {
        Write-BootLog 'Tier1-Apply.ps1 not found.' error
    }
} catch {
    Write-BootLog "Tier1 reapply failed: $_" error
}

# Optional: SecurityTweaker auto-apply can be enabled by adding the following line to this script:
# & (Join-Path $baseDir 'components\SecurityTweaker.ps1') -Apply
# WARNING: This lowers kernel security. Only enable if you understand the risk.

if ($mtx) { $mtx.ReleaseMutex(); $mtx.Dispose() }
Write-BootLog 'Boot reapply completed.'
