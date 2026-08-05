param([switch]$Silent)

$scriptDir = "C:\ShadowKit"
$configPath = Join-Path $scriptDir "config.json"
$logDir = Join-Path $scriptDir "logs"
$componentsDir = Join-Path $scriptDir "components"
$archiveDir = Join-Path $scriptDir "archive"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$mutex = New-Object System.Threading.Mutex -ArgumentList $false, "Global\ShadowKitController"

$acquired = $false
try {
    $acquired = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
}

if (-not $acquired) {
    exit 0
}

if (-not (Test-Path $configPath)) {
    exit 1
}

try {
    $config = Get-Content $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
} catch {
    exit 1
}

function Write-MasterLog {
    param($Message, $Level = "info")

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[" + $ts + "] [" + $Level + "] " + $Message + [Environment]::NewLine
    $file = Join-Path $logDir ("master_" + (Get-Date -Format "yyyy-MM-dd") + ".log")

    try {
        [System.IO.File]::AppendAllText($file, $entry, [System.Text.Encoding]::Unicode)
    } catch {}

    if (-not $Silent) {
        if ($Level -eq "error") {
            Write-Host $entry -ForegroundColor Red
        } else {
            Write-Host $entry -ForegroundColor Cyan
        }
    }
}

Write-MasterLog "Controller initializing..."

$components = @()

if ($config.watchdog.enabled) {
    $components += @{ Name = "Watchdog"; Script = Join-Path $componentsDir "Watchdog.ps1" }
}

if ($config.dns.enabled) {
    $components += @{ Name = "DNSFrenzy"; Script = Join-Path $componentsDir "DNSFrenzy.ps1" }
}

if ($config.timer.enabled) {
    $components += @{ Name = "TimerOptimizer"; Script = Join-Path $componentsDir "TimerOptimizer.ps1" }
}

if ($config.memory.enabled) {
    $components += @{ Name = "MemoryCleaner"; Script = Join-Path $archiveDir "MemoryCleaner.ps1" }
}

if ($config.calibrator.enabled) {
    $components += @{ Name = "SystemCalibrator"; Script = Join-Path $componentsDir "SystemCalibrator.ps1" }
}

if ($components.Count -eq 0) {
    Write-MasterLog "No components enabled. Exiting." "error"
    exit 1
}

Write-MasterLog "Master Controller started - launching components as background processes."

$processes = @{}
$restartCounts = @{}
$restartTimes = @{}
$maxRestarts = 3
$restartWindowMinutes = 5

function Start-ComponentProcess {
    param($ScriptPath, $Name)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"

    $quoted = '"' + $ScriptPath + '"'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " + $quoted + " -Silent"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Write-MasterLog ($Name + " started (PID " + $proc.Id + ").")
        return $proc
    } catch {
        Write-MasterLog ("Failed to start " + $Name + ": " + $_) "error"
        return $null
    }
}

foreach ($comp in $components) {
    Write-MasterLog ("Launching " + $comp.Name + " ...")

    $proc = Start-ComponentProcess -ScriptPath $comp.Script -Name $comp.Name

    if ($proc) {
        $processes[$comp.Name] = $proc
        $restartCounts[$comp.Name] = 0
        $restartTimes[$comp.Name] = Get-Date
    }
}

Write-MasterLog "All components launched. Entering monitoring loop."

while ($true) {
    Start-Sleep -Seconds 30

    foreach ($comp in $components) {
        $name = $comp.Name
        $proc = $processes[$name]
        $now = Get-Date

        if ($null -ne $proc -and -not $proc.HasExited) {
            if ($restartTimes.ContainsKey($name) -and ($now - $restartTimes[$name]).TotalMinutes -gt $restartWindowMinutes) {
                $restartCounts[$name] = 0
            }
            continue
        }

        if ($null -ne $proc) {
            $exitCode = $proc.ExitCode
            $proc.Dispose()
            $processes[$name] = $null
            Write-MasterLog ($name + " process died (Exit Code: " + $exitCode + "). Restarting...") "warn"
        } else {
            Write-MasterLog ($name + " process missing. Starting...") "warn"
        }

        if ($restartTimes.ContainsKey($name) -and ($now - $restartTimes[$name]).TotalMinutes -gt $restartWindowMinutes) {
            $restartCounts[$name] = 0
        }

        if ($restartCounts[$name] -ge $maxRestarts) {
            if ($restartTimes.ContainsKey($name) -and ($now - $restartTimes[$name]).TotalSeconds -lt 60) {
                continue
            }
            $restartCounts[$name] = 0
        }

        $newProc = Start-ComponentProcess -ScriptPath $comp.Script -Name $name

        if ($newProc) {
            $processes[$name] = $newProc
            $restartCounts[$name]++
            $restartTimes[$name] = $now
        }
    }
}



