# ShadowKit Launcher v1.0
$ErrorActionPreference = "Stop"
$root = "C:\ShadowKit"

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       SHADOWKIT LAUNCHER v1.0" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Start Controller (daemon mode)" -ForegroundColor White
    Write-Host "  [2] Start WPF Dashboard" -ForegroundColor White
    Write-Host "  [3] Start Controller + Dashboard" -ForegroundColor White
    Write-Host "  [4] Clean Restart (stop + start)" -ForegroundColor White
    Write-Host "  [5] Run System Audit" -ForegroundColor White
    Write-Host "  [6] Run Diagnostics" -ForegroundColor White
    Write-Host "  [7] Run Tests" -ForegroundColor White
    Write-Host "  [8] View Status" -ForegroundColor White
    Write-Host "  [9] Uninstall ShadowKit" -ForegroundColor Red
    Write-Host ""
    Write-Host "  [Q] Quit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
}

function Start-Controller {
    Write-Host "`nStarting ShadowController..." -ForegroundColor Green
    $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\ShadowController.ps1`"" -WindowStyle Hidden -PassThru
    Write-Host "Controller started (PID: $($proc.Id))" -ForegroundColor Green
    Start-Sleep 2
}

function Start-Dashboard {
    Write-Host "`nStarting WPF Dashboard..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\components\GUI-WPF.ps1`"" -WindowStyle Normal
    Write-Host "Dashboard launched." -ForegroundColor Green
    Start-Sleep 1
}

function Show-Status {
    Write-Host "`n--- ShadowKit Status ---" -ForegroundColor Cyan
    if (Test-Path "$root\state\status.json") {
        $status = Get-Content "$root\state\status.json" -Raw | ConvertFrom-Json
        $status.PSObject.Properties | ForEach-Object {
            $color = switch ($_.Value.status) {
                "Running" { "Green" }
                "Enforcing" { "Green" }
                "Applied" { "Green" }
                "Crashed" { "Red" }
                "Failed" { "Red" }
                default { "Yellow" }
            }
            Write-Host "  $($_.Name): " -NoNewline
            Write-Host "$($_.Value.status)" -ForegroundColor $color
        }
    } else {
        Write-Host "  No status file found." -ForegroundColor Red
    }
    Write-Host ""
    Pause
}

do {
    Show-Menu
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" { Start-Controller; Pause }
        "2" { Start-Dashboard; Pause }
        "3" { Start-Controller; Start-Sleep 3; Start-Dashboard; Pause }
        "4" { & "$root\tools\AIO-CleanRestart.ps1"; Pause }
        "5" { & "$root\tools\AIO-Audit.ps1"; Pause }
        "6" { & "$root\tools\Diagnose-ShadowKit.ps1"; Pause }
        "7" { & "$root\tests\Run-Tests.ps1"; Pause }
        "8" { Show-Status }
        "9" { 
            $confirm = Read-Host "Are you sure? (yes/no)"
            if ($confirm -eq "yes") { & "$root\Uninstall-ShadowKit.ps1" }
        }
        "Q" { exit }
        "q" { exit }
        default { Write-Host "Invalid option." -ForegroundColor Red; Start-Sleep 1 }
    }
} while ($true)
