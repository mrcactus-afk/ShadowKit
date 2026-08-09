$ErrorActionPreference = "Stop"
Import-Module Pester
$results = Invoke-Pester -Path "$PSScriptRoot" -Output Detailed -PassThru
if ($results.FailedCount -gt 0) {
    Write-Host "`n$($results.FailedCount) test(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll $($results.PassedCount) tests passed!" -ForegroundColor Green
    exit 0
}
