param([switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

$components = @(
    @{ Name='SystemCalibrator'; Script='components\SystemCalibrator.ps1' },
    @{ Name='MemoryCleaner';    Script='components\MemoryCleaner.ps1' },
    @{ Name='DNSFrenzy';        Script='components\DNSFrenzy.ps1' },
    @{ Name='TimerOptimizer';   Script='components\TimerOptimizer.ps1' }
)
$logDir = Join-Path $baseDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Write-WatchLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File (Join-Path $logDir 'watchdog.log') -Append -Encoding UTF8 }

while ($true) {
    foreach ($comp in $components) {
        $proc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$($comp.Script)*" }
        if (-not $proc) {
            Write-WatchLog "$($comp.Name) not running, restarting..." warn
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$baseDir\$($comp.Script)`"" -WindowStyle Hidden
        }
    }
    $audit = & (Join-Path $baseDir 'components\SystemCalibrator.ps1') -Audit -Silent
    if ($LASTEXITCODE -ne 0) {
        Write-WatchLog "Calibrator drift detected, re-enforcing..." warn
        & (Join-Path $baseDir 'components\SystemCalibrator.ps1') -Enforce -Silent
    }
    Start-Sleep -Seconds 300
}
