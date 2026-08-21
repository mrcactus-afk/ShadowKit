param([string]$SourceZip = "")
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -SourceZip `"$SourceZip`"" -Wait
    exit
}
if (-not $SourceZip) { $SourceZip = Read-Host 'Enter path to ShadowKit release zip' }
if (-not (Test-Path $SourceZip)) { Write-Host 'Zip not found' -ForegroundColor Red; exit 1 }
$extractDir = Join-Path $env:TEMP ('ShadowKitInstall_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
try {
    Expand-Archive -Path $SourceZip -DestinationPath $extractDir -Force
    $setup = Join-Path $extractDir 'Setup-ShadowKit.ps1'
    if (-not (Test-Path $setup)) { Write-Host 'Setup-ShadowKit.ps1 not found in zip' -ForegroundColor Red; exit 1 }
    & $setup
} finally {
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
}
