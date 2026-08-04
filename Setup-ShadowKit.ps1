<#
.SYNOPSIS
    Installs CAT Core Automation – copies files, creates scheduled task, starts it.
.DESCRIPTION
    Run this script as Administrator. It will:
      1. Create C:\\ShadowKit if it doesn't exist.
      2. Copy all files from the current folder into C:\\ShadowKit.
      3. Register a scheduled task named 'CATCoreMaster' that launches MasterController.ps1 at startup.
      4. Start the task immediately.
#>

# Ensure we are running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "CAT Core Automation Installer" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Yellow

# ---------------------------------------------------------------------
# Step 1: Create target directory and copy files
# ---------------------------------------------------------------------
$targetDir = "C:\\ShadowKit"
if (-not (Test-Path $targetDir)) {
    Write-Host "Creating $targetDir ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying all files from current folder to $targetDir ..." -ForegroundColor Yellow
Copy-Item -Path ".\*" -Destination $targetDir -Recurse -Force

# ---------------------------------------------------------------------
# Step 2: Create scheduled task
# ---------------------------------------------------------------------
$taskName = "CATCoreMaster"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\MasterController.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden

Write-Host "Registering scheduled task '$taskName'..." -ForegroundColor Yellow
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest

# ---------------------------------------------------------------------
# Step 3: Start the task immediately
# ---------------------------------------------------------------------
Write-Host "Starting the task..." -ForegroundColor Yellow
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\MasterController.ps1`""

Write-Host "Installation complete. CAT Core Automation is now running and will start automatically on every boot." -ForegroundColor Green