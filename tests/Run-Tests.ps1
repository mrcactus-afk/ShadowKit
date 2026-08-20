$ErrorActionPreference = 'Stop'
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Pester not installed. Skipping tests." -ForegroundColor Yellow
    exit 0
}
Import-Module Pester
$results = Invoke-Pester -Path (Join-Path $PSScriptRoot 'ShadowKit.Tests.ps1') -Output Detailed -PassThru
if ($results.FailedCount -gt 0) {
    Write-Host "`n$($results.FailedCount) test(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll $($results.PassedCount) tests passed!" -ForegroundColor Green
    exit 0
}
