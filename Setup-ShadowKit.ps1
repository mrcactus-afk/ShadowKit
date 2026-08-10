<#
.SYNOPSIS
    Installs ShadowKit – copies files, creates scheduled task, starts it.
.DESCRIPTION
    Run this script as Administrator. It will:
      1. Create C:\ShadowKit if it doesn't exist.
      2. Copy all files from the current folder into C:\ShadowKit.
      3. Clean Export-ModuleMember from ShadowLogger.ps1 and ShadowIPC.ps1 (if present).
      4. Create logs and state directories.
      5. Register a scheduled task 'ShadowKitController' that launches ShadowController.ps1 at startup.
      6. Start the task immediately.
      7. Create a desktop shortcut.
#>

# Ensure admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "ShadowKit Installer v6.9" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Yellow

$targetDir = "C:\ShadowKit"
if (-not (Test-Path $targetDir)) {
    Write-Host "Creating $targetDir ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "Copying all files to $targetDir ..." -ForegroundColor Yellow
Copy-Item -Path ".\*" -Destination $targetDir -Recurse -Force

# Clean Export-ModuleMember from ShadowLogger.ps1 and ShadowIPC.ps1
$filesToClean = @(
    "$targetDir\components\ShadowLogger.ps1",
    "$targetDir\components\ShadowIPC.ps1"
)
foreach ($f in $filesToClean) {
    if (Test-Path $f) {
        $content = Get-Content $f -Raw
        if ($content -match 'export-modulemember') {
            $newContent = $content -replace '(?im)^\s*export-modulemember\s+.*$', ''
            $newContent | Out-File $f -Encoding UTF8 -Force
            Write-Host "Cleaned $f" -ForegroundColor Green
        }
    }
}

# Ensure logs and state directories
$logDir = "$targetDir\logs"
$stateDir = "$targetDir\state"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

# Register scheduled task
$taskName = "ShadowKitController"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\ShadowController.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden -MultipleInstances IgnoreNew

Write-Host "Registering scheduled task '$taskName'..." -ForegroundColor Yellow
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest | Out-Null

Write-Host "Starting the task..." -ForegroundColor Yellow
Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$targetDir\ShadowController.ps1`""

# Desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcut = $WshShell.CreateShortcut("$desktopPath\ShadowKit.lnk")
$shortcut.TargetPath = "$targetDir\Launch-ShadowKit.bat"
$shortcut.WorkingDirectory = $targetDir
$shortcut.IconLocation = "powershell.exe,0"
$shortcut.Description = "ShadowKit"
$shortcut.Save()

Write-Host "Installation complete. ShadowKit is running and will start on every boot." -ForegroundColor Green
