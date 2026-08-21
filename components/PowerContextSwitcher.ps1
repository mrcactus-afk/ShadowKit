param([switch]$Once, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$logFile = Join-Path $baseDir 'logs\powercontext.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
function Write-PcLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

function Get-BatteryState {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $battery) { return 'Unknown' }
    $plugged = (Get-CimInstance Win32_ComputerSystem).PowerState -eq 0
    if ($plugged) { return 'AC' } else { return 'Battery' }
}

$state = Get-BatteryState
Write-PcLog "Power context detected: $state"
if ($state -eq 'AC') {
    & (Join-Path $baseDir 'components\PowerTuner.ps1') -Apply
    Write-PcLog "Applied tuned power plan for AC"
} elseif ($state -eq 'Battery') {
    & (Join-Path $baseDir 'components\PowerTuner.ps1') -Revert
    Write-PcLog "Reverted to Balanced for battery"
} else {
    Write-PcLog "Battery state unknown, no change" warn
}
if ($Once) {
    Set-ShadowStatus -Component 'PowerContextSwitcher' -Status 'Switched' -Data @{ state = $state }
    exit 0
}
while ($true) {
    Start-Sleep -Seconds 30
    $newState = Get-BatteryState
    if ($newState -ne $state) {
        Write-PcLog "Power context changed: $state -> $newState"
        $state = $newState
        if ($state -eq 'AC') {
            & (Join-Path $baseDir 'components\PowerTuner.ps1') -Apply
            Write-PcLog "Applied tuned power plan for AC"
        } elseif ($state -eq 'Battery') {
            & (Join-Path $baseDir 'components\PowerTuner.ps1') -Revert
            Write-PcLog "Reverted to Balanced for battery"
        }
    }
}
