$ErrorActionPreference = 'Stop'
$root = 'C:\ShadowKit'

function Show-Menu {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "       SHADOWKIT v8.0 LAUNCHER" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Start Controller" -ForegroundColor White
    Write-Host "  [2] Start WPF Dashboard" -ForegroundColor White
    Write-Host "  [3] Start Both" -ForegroundColor White
    Write-Host "  [4] Stop Controller" -ForegroundColor White
    Write-Host "  [5] Run System Audit" -ForegroundColor White
    Write-Host "  [6] Restore SystemCalibrator" -ForegroundColor White
    Write-Host "  [7] Apply GameOptimizer" -ForegroundColor White
    Write-Host "  [8] Revert GameOptimizer" -ForegroundColor White
    Write-Host "  [Q] Quit" -ForegroundColor Gray
    Write-Host ""
}

do {
    Show-Menu
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\ShadowController.ps1`""; Write-Host "Controller started."; Pause }
        "2" { Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\components\GUI-WPF.ps1`""; Pause }
        "3" { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\ShadowController.ps1`""; Start-Sleep 2; Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\components\GUI-WPF.ps1`""; Pause }
        "4" { Set-Content (Join-Path $root 'stop.flag') -Value 'stop'; Write-Host "Stop signal sent."; Pause }
        "5" { & (Join-Path $root 'components\SystemCalibrator.ps1') -Audit; Pause }
        "6" { & (Join-Path $root 'components\SystemCalibrator.ps1') -Restore; Pause }
        "7" { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\components\GameOptimizer.ps1`" -Apply"; Write-Host "GameOptimizer apply started."; Pause }
        "8" { Start-Process powershell -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$root\components\GameOptimizer.ps1`" -Revert"; Write-Host "GameOptimizer revert started."; Pause }
        "Q" { exit }
        "q" { exit }
        default { Write-Host "Invalid option." -ForegroundColor Red; Start-Sleep 1 }
    }
} while ($true)
