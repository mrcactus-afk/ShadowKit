param([switch]$Monitor, [switch]$Once, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$logFile = Join-Path $baseDir 'logs\thermalmanager.log'
$configFile = Join-Path $baseDir 'config\thermalmanager.json'
New-Item -ItemType Directory -Path (Split-Path $logFile), (Split-Path $configFile) -Force | Out-Null
function Write-TmLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

# Default config if missing
$defaultConfig = @{
    HighTemp = 90
    LowTemp = 70
    CooldownSamples = 3
    PollIntervalSec = 5
    CoolingPlan = '381b4222-f694-41f0-9685-ff5bb260df2e'  # Balanced
    PerformancePlan = 'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Ultimate
    FanControlMaxConfig = $null
    ThrottleStopCoolingINI = $null
    ThrottleStopPerformanceINI = $null
} | ConvertTo-Json
if (-not (Test-Path $configFile)) { $defaultConfig | Set-Content $configFile -Encoding UTF8 }
$config = Get-Content $configFile -Raw | ConvertFrom-Json

# Temperature reading via LHM WMI with fallback
function Get-ShadowCPUTemp {
    try {
        $sensor = Get-CimInstance -Namespace "root\LibreHardwareMonitor" -ClassName Sensor -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU Package' }
        if ($sensor) { return [math]::Round($sensor.Value, 1) }
    } catch {}
    try {
        $fallback = Get-CimInstance -Namespace "root\wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
        if ($fallback) { return [math]::Round(($fallback.CurrentTemperature - 2732) / 10, 1) }
    } catch {}
    return $null
}

function Set-ActivePowerPlan([string]$guid) {
    if (-not $guid) { return }
    $current = (powercfg /getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
    if ($current -ne $guid) { powercfg /setactive $guid | Out-Null; Write-TmLog "Switched power plan to $guid" }
}

function Invoke-CoolingActions {
    Write-TmLog "Entering cooling mode: temp high"
    Set-ActivePowerPlan -guid $config.CoolingPlan
    # If FanControl max config specified and exists, launch it
    if ($config.FanControlMaxConfig -and (Test-Path $config.FanControlMaxConfig)) {
        Stop-Process -Name "FanControl" -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath "C:\Program Files\FanControl\FanControl.exe" -ArgumentList "-config `"$($config.FanControlMaxConfig)`"" -ErrorAction SilentlyContinue
        Write-TmLog "Launched FanControl with max config"
    }
    # If ThrottleStop cooling INI specified, swap it
    if ($config.ThrottleStopCoolingINI -and (Test-Path $config.ThrottleStopCoolingINI)) {
        $tsDir = Split-Path $config.ThrottleStopCoolingINI
        $tsMain = Join-Path $tsDir "ThrottleStop.ini"
        Copy-Item $config.ThrottleStopCoolingINI $tsMain -Force
        Write-TmLog "Swapped ThrottleStop INI to cooling profile"
    }
}

function Invoke-PerformanceActions {
    Write-TmLog "Returning to performance mode: temp normal"
    Set-ActivePowerPlan -guid $config.PerformancePlan
    if ($config.FanControlMaxConfig -and (Test-Path $config.FanControlMaxConfig)) {
        # Optionally launch default profile if defined; else just leave current
    }
    if ($config.ThrottleStopPerformanceINI -and (Test-Path $config.ThrottleStopPerformanceINI)) {
        $tsDir = Split-Path $config.ThrottleStopPerformanceINI
        $tsMain = Join-Path $tsDir "ThrottleStop.ini"
        Copy-Item $config.ThrottleStopPerformanceINI $tsMain -Force
        Write-TmLog "Swapped ThrottleStop INI to performance profile"
    }
}

if ($Once) {
    $temp = Get-ShadowCPUTemp
    if ($temp) { Set-ShadowStatus -Component 'ThermalManager' -Status 'Running' -Data @{ TempC = $temp } }
    else { Set-ShadowStatus -Component 'ThermalManager' -Status 'Running' -Data @{ TempC = 'Unknown' } }
    Write-TmLog "ThermalManager once check - temp: $temp"
    exit 0
}

if ($Monitor) {
    Write-TmLog "ThermalManager monitor started. HighTemp=$($config.HighTemp) LowTemp=$($config.LowTemp)"
    $highCount = 0
    $cooling = $false
    $initialPlan = (powercfg /getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
    while ($true) {
        $temp = Get-ShadowCPUTemp
        if ($temp -ne $null) {
            Set-ShadowStatus -Component 'ThermalManager' -Status 'Running' -Data @{ TempC = $temp; Cooling = $cooling }
            if ($temp -ge $config.HighTemp) {
                $highCount++
                if ($highCount -ge $config.CooldownSamples -and -not $cooling) {
                    Invoke-CoolingActions
                    $cooling = $true
                }
            } elseif ($temp -le $config.LowTemp) {
                if ($cooling) {
                    Invoke-PerformanceActions
                    $cooling = $false
                }
                $highCount = 0
            } else {
                $highCount = [math]::Max(0, $highCount - 1)
            }
            Write-TmLog "Temp: $temp C, Cooling: $cooling"
        } else {
            Write-TmLog "Temp unavailable" warn
        }
        Start-Sleep -Seconds $config.PollIntervalSec
    }
}

Write-Host "Usage: ThermalManager.ps1 -Monitor | -Once"
