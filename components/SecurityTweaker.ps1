param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\securitytweaker.state.json'
$logFile = Join-Path $baseDir 'logs\security.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-SecLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

$exclusionPaths = @("C:\Games", "C:\Program Files\Steam\steamapps", "C:\Program Files (x86)\Steam\steamapps")

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-SecLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    try {
        if ($state.hvci -ne $null) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Value $state.hvci -Type DWord -Force
        } else {
            Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Force -ErrorAction SilentlyContinue
        }
        if ($state.credentialGuard -ne $null) {
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' -Name 'Enabled' -Value $state.credentialGuard -Type DWord -Force
        } else {
            Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard' -Name 'Enabled' -Force -ErrorAction SilentlyContinue
        }
        Write-SecLog 'Restored VBS/HVCI settings'
    } catch { Write-SecLog "VBS restore failed: $_" error }
    try {
        foreach ($path in $exclusionPaths) {
            Remove-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
            Write-SecLog "Removed Defender exclusion: $path"
        }
    } catch { Write-SecLog "Defender exclusion revert failed: $_" error }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'SecurityTweaker' -Status 'Reverted'
    Write-SecLog 'SecurityTweaker revert complete'
    exit 0
}

if ($Apply) {
    $state = @{}
    $hvciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
    $credPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard'
    try { $state.hvci = (Get-ItemProperty -Path $hvciPath -Name 'Enabled' -ErrorAction Stop).Enabled } catch { $state.hvci = $null }
    try { $state.credentialGuard = (Get-ItemProperty -Path $credPath -Name 'Enabled' -ErrorAction Stop).Enabled } catch { $state.credentialGuard = $null }
    try {
        New-Item -Path $hvciPath -Force | Out-Null
        Set-ItemProperty -Path $hvciPath -Name 'Enabled' -Value 0 -Type DWord -Force
        New-Item -Path $credPath -Force | Out-Null
        Set-ItemProperty -Path $credPath -Name 'Enabled' -Value 0 -Type DWord -Force
        Write-SecLog 'VBS/HVCI disabled. Reboot required for full effect.'
    } catch { Write-SecLog "VBS disable failed: $_" error }
    try {
        foreach ($path in $exclusionPaths) {
            Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
            Write-SecLog "Added Defender exclusion: $path"
        }
    } catch { Write-SecLog "Defender exclusion apply failed: $_" error }
    $state | ConvertTo-Json -Depth 3 | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'SecurityTweaker' -Status 'Applied' -Data @{ RebootRequired = $true }
    Write-SecLog 'SecurityTweaker apply complete. Warning: lowers kernel security posture.' warn
    exit 0
}
Write-Host "Usage: SecurityTweaker.ps1 -Apply   or   -Revert"
