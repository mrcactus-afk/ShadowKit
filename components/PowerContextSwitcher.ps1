param([switch]$Once, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$logFile = Join-Path $baseDir 'logs\powercontext.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
function Write-PcLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

$ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'

function Get-BatteryState {
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if (-not $battery) { return 'Unknown' }
    $plugged = (Get-CimInstance Win32_ComputerSystem).PowerState -eq 0
    if ($plugged) { return 'AC' } else { return 'Battery' }
}

$state = Get-BatteryState
Write-PcLog "Power context detected: $state"

if ($state -eq 'AC') {
    $current = (powercfg /getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
    if ($current -ne $ultimate) {
        powercfg /setactive $ultimate | Out-Null
        Write-PcLog "Switched to Ultimate Performance"
    } else {
        Write-PcLog "Already on Ultimate Performance"
    }
} elseif ($state -eq 'Battery') {
    $current = (powercfg /getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
    if ($current -ne $balanced) {
        powercfg /setactive $balanced | Out-Null
        Write-PcLog "Switched to Balanced"
    } else {
        Write-PcLog "Already on Balanced"
    }
} else {
    Write-PcLog "Battery state unknown, no change" warn
}

if ($Once) {
    Set-ShadowStatus -Component 'PowerContextSwitcher' -Status 'Switched' -Data @{ state = $state }
    exit 0
}

# Long-running loop for background operation
while ($true) {
    Start-Sleep -Seconds 30
    $newState = Get-BatteryState
    if ($newState -ne $state) {
        Write-PcLog "Power context changed: $state -> $newState"
        $state = $newState
        if ($state -eq 'AC') {
            powercfg /setactive $ultimate | Out-Null
            Write-PcLog "Switched to Ultimate Performance"
        } elseif ($state -eq 'Battery') {
            powercfg /setactive $balanced | Out-Null
            Write-PcLog "Switched to Balanced"
        }
    }
}
