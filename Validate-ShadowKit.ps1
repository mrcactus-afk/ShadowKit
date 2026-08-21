# Validate-ShadowKit.ps1 - Non-Pester validation
$ErrorActionPreference = 'SilentlyContinue'
$baseDir = 'C:\ShadowKit'
$fail = 0

function Check($name, $ok, $detail) {
    if ($ok) { Write-Host "[PASS] $name - $detail" -ForegroundColor Green }
    else { $script:fail++; Write-Host "[FAIL] $name - $detail" -ForegroundColor Red }
}

Write-Host "`n=== ShadowKit Validation ===" -ForegroundColor Cyan

# Check required files
$required = @(
    'ShadowController.ps1',
    'modules\ShadowIPC.psm1',
    'components\SystemCalibrator.ps1',
    'components\MemoryCleaner.ps1',
    'components\DNSFrenzy.ps1',
    'components\TimerOptimizer.ps1',
    'components\GUI-WPF.ps1',
    'components\GameOptimizer.ps1',
    'config\profile.json',
    'config\servers.json',
    'config.json'
)
foreach ($f in $required) {
    Check "File $f" (Test-Path (Join-Path $baseDir $f)) "exists"
}

# Check scheduled task
$taskController = Get-ScheduledTask -TaskName 'ShadowKitController' -ErrorAction SilentlyContinue
$taskBootReapply = Get-ScheduledTask -TaskName 'ShadowKitBootReapply' -ErrorAction SilentlyContinue
Check 'Scheduled task ShadowKitController' ($taskController -ne $null) 'registered'
Check 'Scheduled task ShadowKitBootReapply' ($taskBootReapply -ne $null) 'registered'
Check "Scheduled task" ($task -ne $null) "registered"

# Check status file
$statusFile = Join-Path $baseDir 'state\status.json'
if (Test-Path $statusFile) {
    $status = Get-Content $statusFile -Raw | ConvertFrom-Json
    $components = @('Controller','MemoryCleaner','DNSFrenzy','TimerOptimizer','SystemCalibrator')
    foreach ($comp in $components) {
        $s = $status.$comp.status
        Check "Component $comp" ($s -eq 'Running' -or $s -eq 'Enforced') "status: $s"
    }
} else { Check "Status file" $false "missing" }

# Check running processes
$procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ShadowKit*' }
$controllerProcs = @($procs | Where-Object { $_.CommandLine -like '*ShadowController.ps1*' })
Check "Controller process" ($controllerProcs.Count -gt 0) "count: $($controllerProcs.Count)"

Write-Host "`nValidation complete. Failures: $fail" -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 } else { exit 0 }

