# Uninstall-ShadowKit.ps1 - Safe uninstall with restore
param([switch]$Force)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator." -ForegroundColor Red
    exit 1
}
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'

Write-Host "ShadowKit Uninstaller" -ForegroundColor Cyan

# 1. Restore system state
Write-Host "Restoring system state..." -ForegroundColor Yellow
if (Test-Path (Join-Path $baseDir 'components\SystemCalibrator.ps1')) {
    & (Join-Path $baseDir 'components\SystemCalibrator.ps1') -Restore -Silent
}
if (Test-Path (Join-Path $baseDir 'components\GameOptimizer.ps1')) {
    & (Join-Path $baseDir 'components\GameOptimizer.ps1') -Revert -Silent
}

# 2. Stop and remove scheduled tasks
Write-Host "Removing scheduled tasks..." -ForegroundColor Yellow
Get-ScheduledTask -TaskName 'ShadowKitController','ShadowKitWatchdog' -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# 3. Kill all ShadowKit processes
Write-Host "Stopping processes..." -ForegroundColor Yellow
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ShadowKit*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 2

# 4. Remove folder
if (Test-Path $baseDir) {
    if ($Force) {
        Remove-Item $baseDir -Recurse -Force
        Write-Host "Removed $baseDir" -ForegroundColor Green
    } else {
        $answer = Read-Host "Delete $baseDir ? (y/n)"
        if ($answer -eq 'y') { Remove-Item $baseDir -Recurse -Force; Write-Host "Removed $baseDir" -ForegroundColor Green }
        else { Write-Host "Folder kept." -ForegroundColor Gray }
    }
}
Write-Host "Uninstall complete." -ForegroundColor Green
