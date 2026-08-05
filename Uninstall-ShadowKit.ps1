<#
.SYNOPSIS
    Uninstalls CAT Core Automation â€“ removes scheduled task, kills processes, deletes folder.
.DESCRIPTION
    This script stops and deletes the scheduled task, terminates any running
    MasterController processes, and optionally removes the entire C:\\ShadowKit folder.
    Run as Administrator.
#>

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "CAT Core Automation Uninstaller" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Yellow

# ---------------------------------------------------------------------
# 1. Remove scheduled task
# ---------------------------------------------------------------------
$taskName = "ShadowKitController"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Removing scheduled task '$taskName'..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled task removed." -ForegroundColor Green
} else {
    Write-Host "Scheduled task not found." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# 2. Kill any running MasterController processes
# ---------------------------------------------------------------------
Write-Host "Looking for running MasterController processes..." -ForegroundColor Yellow
$runningProcesses = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -like "*MasterController.ps1*"
}
if ($runningProcesses) {
    foreach ($proc in $runningProcesses) {
        Write-Host "Terminating process ID $($proc.Id)..." -ForegroundColor Yellow
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Processes terminated." -ForegroundColor Green
} else {
    Write-Host "No MasterController processes are currently running." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
# 3. Ask about deleting the folder
# ---------------------------------------------------------------------
$folder = "C:\\ShadowKit"
if (Test-Path $folder) {
    $answer = Read-Host "Do you want to delete the entire $folder folder? (y/n)"
    if ($answer -eq 'y' -or $answer -eq 'Y') {
        Remove-Item -Path $folder -Recurse -Confirm -ErrorAction SilentlyContinue
        Write-Host "Folder deleted." -ForegroundColor Green
    } else {
        Write-Host "Folder kept." -ForegroundColor Gray
    }
} else {
    Write-Host "Folder not found." -ForegroundColor DarkGray
}

Write-Host "Uninstall completed." -ForegroundColor Cyan
