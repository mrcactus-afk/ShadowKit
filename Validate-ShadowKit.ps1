# Validate-ShadowKit.ps1 - Comprehensive validation
$ErrorActionPreference = 'SilentlyContinue'
$baseDir = 'C:\ShadowKit'
$fail = 0

function Check($name, $ok, $detail) {
    if ($ok) { Write-Host "[PASS] $name - $detail" -ForegroundColor Green }
    else { $script:fail++; Write-Host "[FAIL] $name - $detail" -ForegroundColor Red }
}

Write-Host "`n=== ShadowKit Validation ===" -ForegroundColor Cyan

# Required files
$required = @(
    'ShadowController.ps1',
    'BootReapply.ps1',
    'Launch-ShadowKit.ps1',
    'Uninstall-ShadowKit.ps1',
    'Validate-ShadowKit.ps1',
    'modules\ShadowIPC.psm1',
    'components\SystemCalibrator.ps1',
    'components\MemoryCleaner.ps1',
    'components\DNSFrenzy.ps1',
    'components\TimerOptimizer.ps1',
    'components\GameOptimizer.ps1',
    'components\GUI-WPF.ps1',
    'components\NetworkOptimizer.ps1',
    'components\FileSystemTuner.ps1',
    'components\PowerTuner.ps1',
    'components\DebloatEnforcer.ps1',
    'components\GPUTuner.ps1',
    'components\SecurityTweaker.ps1',
    'Tier1-Apply.ps1',
    'Tier1-Revert.ps1',
    'config\profile.json',
    'config\servers.json',
    'config.json'
)
foreach ($f in $required) {
    Check "File $f" (Test-Path (Join-Path $baseDir $f)) "exists"
}

# Scheduled tasks
$taskController = Get-ScheduledTask -TaskName 'ShadowKitController' -ErrorAction SilentlyContinue
$taskBootReapply = Get-ScheduledTask -TaskName 'ShadowKitBootReapply' -ErrorAction SilentlyContinue
Check "Task ShadowKitController" ($taskController -ne $null) "registered"
Check "Task ShadowKitBootReapply" ($taskBootReapply -ne $null) "registered"

# Status file
$statusFile = Join-Path $baseDir 'state\status.json'
if (Test-Path $statusFile) {
    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
    $components = @('Controller','MemoryCleaner','DNSFrenzy','TimerOptimizer','SystemCalibrator')
    foreach ($comp in $components) {
        $s = $status.$comp.status
        Check "Component $comp" ($s -eq 'Running' -or $s -eq 'Enforced') "status: $s"
    }
    # Optional Tier1 components (status may vary)
    $tier1 = @('NetworkOptimizer','FileSystemTuner','PowerTuner','DebloatEnforcer','GPUTuner','SecurityTweaker')
    foreach ($comp in $tier1) {
        if ($status.$comp) {
            $s = $status.$comp.status
            Check "Tier1 $comp" ($s -eq 'Applied' -or $s -eq 'Reverted' -or $s -eq 'Skipped') "status: $s"
        }
    }
} else {
    Check "Status file" $false "missing"
}

# Processes
$procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ShadowKit*' }
$controllerProcs = @($procs | Where-Object { $_.CommandLine -like '*ShadowController.ps1*' })
Check "Controller process" ($controllerProcs.Count -gt 0) "count: $($controllerProcs.Count)"

Write-Host "`nValidation complete. Failures: $fail" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }
