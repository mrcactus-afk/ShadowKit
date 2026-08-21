param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\debloatenforcer.state.json'
$logFile = Join-Path $baseDir 'logs\debloat.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-DebLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }
$services = @('SysMain','DiagTrack','WSearch','XblAuthManager','XblGameSave')

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-DebLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($svc in $services) {
        $startup = $state.$svc
        if ($startup) { Set-Service -Name $svc -StartupType $startup -ErrorAction SilentlyContinue; Write-DebLog "Restored $svc to $startup" }
    }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'DebloatEnforcer' -Status 'Reverted'
    Write-DebLog 'DebloatEnforcer revert complete'
    exit 0
}

if ($Apply) {
    $state = @{}
    foreach ($svc in $services) {
        $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($svcObj) {
            $state[$svc] = $svcObj.StartType
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc -StartupType Disabled
            Write-DebLog "Disabled $svc"
        }
    }
    $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'DebloatEnforcer' -Status 'Applied'
    Write-DebLog 'DebloatEnforcer apply complete'
    exit 0
}
Write-Host "Usage: DebloatEnforcer.ps1 -Apply   or   -Revert"
