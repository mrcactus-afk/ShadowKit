# Setup-ShadowKit.ps1 - ShadowKit v8.0 one-command installer
param([switch]$SkipValidation)
$ErrorActionPreference = 'Stop'

# Self-elevate
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Wait
    exit
}

$targetDir = 'C:\ShadowKit'
$sourceDir = $PSScriptRoot

Write-Host "=== ShadowKit v8.0 Setup ===" -ForegroundColor Cyan

# 1. Stop existing install
Write-Host "`n[1/8] Stopping existing processes and tasks..." -ForegroundColor Yellow
$taskNames = @(
    'ShadowKitController','ShadowKitBootReapply','ShadowKitThermalManager',
    'ShadowKitThermalUndervolt','ShadowKitPowerContextAC','ShadowKitPowerContextCheck',
    'ShadowKitEventMonitor','ShadowKitWatchdog'
)
foreach ($t in $taskNames) {
    Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ShadowKit*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 2

# 2. Copy files if installing from a different source dir
if ($sourceDir -ne $targetDir) {
    Write-Host "[2/8] Copying files to $targetDir ..." -ForegroundColor Yellow
    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceDir '*') -Destination $targetDir -Recurse -Force
} else {
    Write-Host "[2/8] Source is already $targetDir - skipping copy." -ForegroundColor Yellow
}

# 3. Ensure directories
Write-Host "[3/8] Creating directories..." -ForegroundColor Yellow
foreach ($d in @('modules','components','state','logs','config','tests')) {
    New-Item -ItemType Directory -Path (Join-Path $targetDir $d) -Force | Out-Null
}

# 4. ACL hardening
Write-Host "[4/8] Hardening ACLs..." -ForegroundColor Yellow
$acl = Get-Acl $targetDir
$acl.SetAccessRuleProtection($true, $false)
$acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
$acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Set-Acl -Path $targetDir -AclObject $acl

# 5. Register scheduled tasks
Write-Host "[5/8] Registering scheduled tasks..." -ForegroundColor Yellow
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$periodicTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)

$tasks = @(
    @{ Name = 'ShadowKitController';        Script = 'ShadowController.ps1';          Args = '';        Trigger = $startupTrigger },
    @{ Name = 'ShadowKitBootReapply';      Script = 'BootReapply.ps1';              Args = '';        Trigger = $startupTrigger },
    @{ Name = 'ShadowKitThermalManager';   Script = 'components\ThermalManager.ps1'; Args = '-Monitor'; Trigger = $startupTrigger },
    @{ Name = 'ShadowKitThermalUndervolt'; Script = 'components\ThermalUndervolt.ps1'; Args = '-Apply';  Trigger = $startupTrigger },
    @{ Name = 'ShadowKitPowerContextAC';   Script = 'components\PowerContextSwitcher.ps1'; Args = '-Once'; Trigger = $startupTrigger },
    @{ Name = 'ShadowKitPowerContextCheck'; Script = 'components\PowerContextSwitcher.ps1'; Args = '-Once'; Trigger = $periodicTrigger },
    @{ Name = 'ShadowKitEventMonitor';     Script = 'components\EventMonitor.ps1';    Args = '';        Trigger = $startupTrigger }
)
foreach ($t in $tasks) {
    $scriptPath = Join-Path $targetDir $t.Script
    if (Test-Path $scriptPath) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" $($t.Args)"
        Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $t.Trigger -Principal $principal -Settings $settings -Force | Out-Null
        Write-Host "  Registered $($t.Name)"
    } else {
        Write-Host "  SKIP $($t.Name): script not found" -ForegroundColor Yellow
    }
}

# 6. Desktop shortcut
Write-Host "[6/8] Creating desktop shortcut..." -ForegroundColor Yellow
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\ShadowKit.lnk")
$shortcut.TargetPath = "$targetDir\Launch-ShadowKit.bat"
$shortcut.WorkingDirectory = $targetDir
$shortcut.Save()

# 7. Start controller
Write-Host "[7/8] Starting controller..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName 'ShadowKitController' -ErrorAction SilentlyContinue
Start-Sleep 10

# 8. Validation
if (-not $SkipValidation) {
    Write-Host "[8/8] Running validation..." -ForegroundColor Yellow
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    $validator = Join-Path $targetDir 'Validate-ShadowKit.ps1'
    if (Test-Path $validator) { & $validator } else { Write-Host "  Validator not found - skipping." -ForegroundColor Yellow }
}

Write-Host "`nShadowKit v8.0 installation complete." -ForegroundColor Green
Write-Host "Dashboard: & C:\ShadowKit\components\GUI-WPF.ps1" -ForegroundColor Cyan
