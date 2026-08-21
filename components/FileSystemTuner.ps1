param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\filesystemtuner.state.json'
$logFile = Join-Path $baseDir 'logs\filesystem.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-FsLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

function Get-FsUtilValue {
    param($query)
    $out = fsutil behavior query $query
    if ($out -match '=\s*(\d)') { return [int]$Matches[1] } else { return $null }
}

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-FsLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    fsutil behavior set disablelastaccess $state.disablelastaccess | Out-Null
    fsutil behavior set disable8dot3 $state.disable8dot3 | Out-Null
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'FileSystemTuner' -Status 'Reverted'
    Write-FsLog 'FileSystemTuner revert complete'
    exit 0
}

if ($Apply) {
    $state = @{
        disablelastaccess = Get-FsUtilValue 'disablelastaccess'
        disable8dot3 = Get-FsUtilValue 'disable8dot3'
    }
    fsutil behavior set disablelastaccess 1 | Out-Null
    fsutil behavior set disable8dot3 1 | Out-Null
    fsutil behavior set disabledeletenotify 0 | Out-Null
    $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'FileSystemTuner' -Status 'Applied'
    Write-FsLog 'FileSystemTuner apply complete'
    exit 0
}
Write-Host "Usage: FileSystemTuner.ps1 -Apply   or   -Revert"
