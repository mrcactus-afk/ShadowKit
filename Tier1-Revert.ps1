# Tier1-Revert.ps1 - Reverts all Tier 1 safe optimizations
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
& (Join-Path $baseDir 'components\NetworkOptimizer.ps1') -Revert
& (Join-Path $baseDir 'components\FileSystemTuner.ps1') -Revert
& (Join-Path $baseDir 'components\PowerTuner.ps1') -Revert
& (Join-Path $baseDir 'components\DebloatEnforcer.ps1') -Revert
& (Join-Path $baseDir 'components\GPUTuner.ps1') -Revert
Write-Host 'Tier 1 optimizations reverted.' -ForegroundColor Green
