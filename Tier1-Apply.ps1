# Tier1-Apply.ps1 - Applies all Tier 1 safe optimizations
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
& (Join-Path $baseDir 'components\NetworkOptimizer.ps1') -Apply
& (Join-Path $baseDir 'components\FileSystemTuner.ps1') -Apply
& (Join-Path $baseDir 'components\PowerTuner.ps1') -Apply
& (Join-Path $baseDir 'components\DebloatEnforcer.ps1') -Apply
& (Join-Path $baseDir 'components\GPUTuner.ps1') -Apply
Write-Host 'Tier 1 optimizations applied.' -ForegroundColor Green
