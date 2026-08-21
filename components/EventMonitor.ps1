param([switch]$Once, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$logFile = Join-Path $baseDir 'logs\events.log'
$stateFile = Join-Path $baseDir 'state\eventmonitor.state.json'
New-Item -ItemType Directory -Path (Split-Path $logFile), (Split-Path $stateFile) -Force | Out-Null
function Write-EventLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

# Load previous state
$prevState = @{}
if (Test-Path $stateFile) { try { $prevState = Get-Content $stateFile -Raw | ConvertFrom-Json } catch {} }

# Map component names from status.json
$criticalComponents = @('Controller','MemoryCleaner','DNSFrenzy','TimerOptimizer','SystemCalibrator')
$tier1Components = @('NetworkOptimizer','FileSystemTuner','PowerTuner','DebloatEnforcer','GPUTuner','SecurityTweaker')

function Check-StatusChanges {
    $status = Get-ShadowStatus
    if (-not $status) { return }
    $currentState = @{}
    foreach ($comp in $criticalComponents) {
        $s = $status.$comp.status
        $currentState[$comp] = $s
        if ($prevState.$comp -and $prevState.$comp -ne $s) {
            if ($s -eq 'Crashed' -or $s -eq 'Failed') {
                Write-EventLog "$comp status changed to $s" error
            } else {
                Write-EventLog "$comp status changed from $($prevState.$comp) to $s"
            }
        }
    }
    foreach ($comp in $tier1Components) {
        if ($status.$comp) {
            $s = $status.$comp.status
            $currentState[$comp] = $s
            if ($prevState.$comp -and $prevState.$comp -ne $s) {
                Write-EventLog "$comp status changed from $($prevState.$comp) to $s"
            }
        }
    }
    # Thermal checks
    if ($status.ThermalManager -and $status.ThermalManager.data -and $status.ThermalManager.data.TempC) {
        $temp = $status.ThermalManager.data.TempC
        $currentState.TempC = $temp
        if ($temp -ge 90 -and $prevState.TempC -lt 90) {
            Write-EventLog "High temperature detected: $temp C" warn
        }
        if ($temp -le 70 -and $prevState.TempC -gt 70) {
            Write-EventLog "Temperature returned to normal: $temp C"
        }
    }
    # Save current state
    $currentState | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    $prevState = $currentState
}

if ($Once) {
    Check-StatusChanges
    Set-ShadowStatus -Component 'EventMonitor' -Status 'Running'
    Write-EventLog "EventMonitor one-shot check completed"
    exit 0
}

# Long-running loop
Write-EventLog "EventMonitor started"
Set-ShadowStatus -Component 'EventMonitor' -Status 'Running'
while ($true) {
    Check-StatusChanges
    Start-Sleep -Seconds 10
}
