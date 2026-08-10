<#
.SYNOPSIS
    Installs ShadowKit v7.0 – copies files, registers scheduled task, creates shortcut.
.DESCRIPTION
    Run this script as Administrator. It will:
      1. Create C:\ShadowKit if it doesn't exist.
      2. Copy all files from the current folder into C:\ShadowKit.
      3. Register a scheduled task 'ShadowKitController' that launches ShadowController.ps1 at startup.
      4. **Does NOT start the controller immediately** – relies on the task to start at next boot.
      5. Create a desktop shortcut.
#>

# Ensure admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "ShadowKit Installer v7.0" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Yellow

$targetDir = "C:\ShadowKit"
if (-not (Test-Path $targetDir)) {
    Write-Host "Creating $targetDir ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying all files to $targetDir ..." -ForegroundColor Yellow
Copy-Item -Path ".\*" -Destination $targetDir -Recurse -Force

# Ensure logs and state directories
$logDir = "$targetDir\logs"
$stateDir = "$targetDir\state"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

# Register scheduled task (runs as SYSTEM, hidden)
$taskName = "ShadowKitController"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\ShadowController.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden -MultipleInstances IgnoreNew

Write-Host "Registering scheduled task '$taskName'..." -ForegroundColor Yellow
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest | Out-Null

# Do NOT start the controller; it will run at next boot
Write-Host "Task registered. The controller will start automatically at the next boot." -ForegroundColor Green

# Desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcut = $WshShell.CreateShortcut("$desktopPath\ShadowKit.lnk")
$shortcut.TargetPath = "$targetDir\Launch-ShadowKit.bat"
$shortcut.WorkingDirectory = $targetDir
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Description = "ShadowKit"
$shortcut.Save()

Write-Host "Installation complete. ShadowKit will start on next boot." -ForegroundColor Green