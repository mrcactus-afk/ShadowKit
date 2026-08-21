param([switch]$Apply, [switch]$Revert, [switch]$Monitor, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$logFile = Join-Path $baseDir 'logs\thermalundervolt.log'
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
function Write-TuLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

$tools = @(
    @{ Name = 'ThrottleStop'; Process = 'ThrottleStop'; Paths = @("$env:ProgramFiles\ThrottleStop\ThrottleStop.exe", "$env:ProgramFiles(x86)\ThrottleStop\ThrottleStop.exe") },
    @{ Name = 'IntelXTU'; Process = 'XtuUi'; Paths = @("$env:ProgramFiles\Intel\Intel(R) Extreme Tuning Utility\XtuUi.exe", "$env:ProgramFiles(x86)\Intel\Intel(R) Extreme Tuning Utility\XtuUi.exe") },
    @{ Name = 'FanControl'; Process = 'FanControl'; Paths = @("$env:ProgramFiles\FanControl\FanControl.exe", "$env:ProgramFiles(x86)\FanControl\FanControl.exe") }
)

function Get-ToolPath {
    param($tool)
    foreach ($p in $tool.Paths) { if (Test-Path $p) { return $p } }
    # Fallback: search PATH
    $cmd = Get-Command $tool.Process -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

if ($Revert) {
    foreach ($tool in $tools) {
        $proc = Get-Process -Name $tool.Process -ErrorAction SilentlyContinue
        if ($proc) { Stop-Process -Name $tool.Process -Force -ErrorAction SilentlyContinue; Write-TuLog "Stopped $($tool.Name)" }
    }
    Set-ShadowStatus -Component 'ThermalUndervolt' -Status 'Reverted'
    Write-TuLog 'ThermalUndervolt revert complete'
    exit 0
}

if ($Apply) {
    $launched = @()
    foreach ($tool in $tools) {
        $path = Get-ToolPath -tool $tool
        if ($path) {
            Start-Process -FilePath $path -WindowStyle Hidden -ErrorAction SilentlyContinue
            $launched += $tool.Name
            Write-TuLog "Launched $($tool.Name) from $path"
        } else {
            Write-TuLog "$($tool.Name) not installed - skipping" warn
        }
    }
    if ($launched.Count -gt 0) {
        Set-ShadowStatus -Component 'ThermalUndervolt' -Status 'Applied' -Data @{ Launched = $launched }
    } else {
        Set-ShadowStatus -Component 'ThermalUndervolt' -Status 'Skipped' -Data @{ Reason = 'No supported tools found' }
    }
    Write-TuLog 'ThermalUndervolt apply complete'
    exit 0
}

if ($Monitor) {
    # Log temperatures every 30 seconds indefinitely
    Write-TuLog 'Temperature monitor started'
    while ($true) {
        try {
            $temp = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($temp) {
                $celsius = ($temp.CurrentTemperature - 2732) / 10.0
                Write-TuLog "CPU Temp: $celsius C"
                Set-ShadowStatus -Component 'ThermalUndervolt' -Status 'Monitoring' -Data @{ TempC = $celsius }
            }
        } catch { Write-TuLog "Temp read failed: $_" error }
        Start-Sleep -Seconds 30
    }
}

Write-Host "Usage: ThermalUndervolt.ps1 -Apply | -Revert | -Monitor"
