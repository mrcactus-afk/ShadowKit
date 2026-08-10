# =====================================================================
# Setup-ShadowKit.ps1 – Self‑elevating installer v7.2
# If not running as Administrator, it re‑launches itself with RunAs.
# =====================================================================

# ---- Self‑elevation block ----
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires Administrator privileges. Re‑launching..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Wait
    exit
}

# ---- Installation ----
Write-Host "ShadowKit Installer v7.2 (elevated)" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Yellow

$targetDir = "C:\ShadowKit"
if (-not (Test-Path $targetDir)) {
    Write-Host "Creating $targetDir ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying all files to $targetDir ..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $targetDir -Recurse -Force -ErrorAction SilentlyContinue

# Ensure logs and state directories
$logDir = "$targetDir\logs"
$stateDir = "$targetDir\state"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

# Clean up leftover component logs (optional)
Get-ChildItem $logDir -Filter "*_controller.log" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem $logDir -Filter "*_controller.err" -ErrorAction SilentlyContinue | Remove-Item -Force

# Register scheduled task
$taskName = "ShadowKitController"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\ShadowController.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden -MultipleInstances IgnoreNew

Write-Host "Registering scheduled task '$taskName'..." -ForegroundColor Yellow
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest | Out-Null

# Start the task immediately (so it runs now)
Write-Host "Starting controller..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# Desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcut = $WshShell.CreateShortcut("$desktopPath\ShadowKit.lnk")
$shortcut.TargetPath = "$targetDir\Launch-ShadowKit.bat"
$shortcut.WorkingDirectory = $targetDir
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Description = "ShadowKit"
$shortcut.Save()

Write-Host "Installation complete. ShadowKit is running and will start at every boot." -ForegroundColor Green