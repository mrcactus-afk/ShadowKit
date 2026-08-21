$ErrorActionPreference = 'SilentlyContinue'
$issues = 0
function Check($name, $ok, $detail) {
    if ($ok) { Write-Host "[PASS] $name - $detail" -ForegroundColor Green }
    else { $script:issues++; Write-Host "[FAIL] $name - $detail" -ForegroundColor Red }
}
Write-Host "=== ShadowKit Setup Dry Run ===" -ForegroundColor Cyan
Check "Administrator privileges" ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) "elevated"
Check "PowerShell version" ($PSVersionTable.PSVersion.Major -ge 5) "$($PSVersionTable.PSVersion.ToString())"
Check "Git installed" ([bool](Get-Command git -ErrorAction SilentlyContinue)) "found"
Check "Write access to C:\" ([bool](Test-Path C:\ -PathType Container)) "C:\ accessible"
Check "No existing ShadowKitController task" (-not (Get-ScheduledTask -TaskName 'ShadowKitController' -ErrorAction SilentlyContinue)) "not present"
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*ShadowKit*' })
Check "No running ShadowKit processes" ($procs.Count -eq 0) "count: $($procs.Count)"
Write-Host "`nDry run complete. Issues: $issues" -ForegroundColor Cyan
if ($issues -eq 0) { exit 0 } else { exit 1 }
