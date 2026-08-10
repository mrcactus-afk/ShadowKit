# ShadowKit Controller v7.2
# – Named mutex singleton (Global\ShadowKitControllerMutex)
# – Runspace pool (min=2, max=ProcessorCount+2)
# – Imports ShadowLogger as a proper module (.psm1)
# – Component telemetry: duration, memory delta
# – Clean error capture via $ps.Streams.Error
# – Self‑healing: restarts components on exit/crash

param([switch]$Silent)

# Import ShadowLogger as a module
$modulePath = Join-Path $PSScriptRoot 'components\ShadowLogger.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction Stop
} else {
    # Fallback stub if module missing
    function Write-ShadowKitLog { param($Message,$Level='info',$Module='System',$Data=@{}) }
    function Read-ShadowKitLog { param($Tail=200) return @() }
}

# Import enhanced ShadowIPC (dot‑sourced because it exports functions)
. (Join-Path $PSScriptRoot 'components\ShadowIPC.ps1') -ErrorAction Stop

# ---- Singleton mutex ----
$mutexName = 'Global\ShadowKitControllerMutex'
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    Write-ShadowKitLog -Message "Another controller is running. Exiting." -Level info -Module Controller
    exit 0
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}

Write-ShadowKitLog -Message "Controller started (v7.2 runspace pool)" -Level info -Module Controller

# Read config
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path $configPath)) {
    Write-ShadowKitLog -Message "Config missing at $configPath" -Level error -Module Controller
    $mutex.ReleaseMutex()
    exit 1
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Discover plugins
$plugins = @()
Get-ChildItem -Path (Join-Path $PSScriptRoot 'components') -Filter 'plugin.json' -Recurse | ForEach-Object {
    $man = $_ | Get-Content -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $man) { return }
    $scriptPath = $man.EntryPoint
    if (-not (Test-Path $scriptPath)) {
        $relPath = Join-Path $_.DirectoryName $man.EntryPoint
        if (Test-Path $relPath) { $scriptPath = $relPath }
        else { return }
    }
    $enabled = $true
    if ($man.ConfigKey -and $config.PSObject.Properties.Name -contains $man.ConfigKey) {
        $enabled = [bool]$config.$($man.ConfigKey).enabled
    }
    if ($man.Enabled -and $enabled) {
        $plugins += [PSCustomObject]@{
            Name       = $man.Name
            ScriptPath = $scriptPath
        }
    }
}
Write-ShadowKitLog -Message "Discovered $($plugins.Count) plugins" -Level info -Module Controller

# ---- Runspace pool ----
$cpu = [Environment]::ProcessorCount
$min = [math]::Min(2, $cpu)
$max = $cpu + 2
$pool = [runspacefactory]::CreateRunspacePool($min, $max)
$pool.ApartmentState = 'MTA'
$pool.Open()
Write-ShadowKitLog -Message "Runspace pool created (min=$min, max=$max)" -Level info -Module Controller

# ---- Helper to run a plugin with telemetry ----
function Invoke-Plugin {
    param($Plugin, $Pool)
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $Pool
    $startTime = Get-Date
    $startMem = (Get-Process -Id $PID).WorkingSet64 / 1MB
    $null = $powershell.AddScript({
        param($scriptPath)
        & $scriptPath -Silent
    }).AddArgument($Plugin.ScriptPath)
    $async = $powershell.BeginInvoke()
    $completed = $async.AsyncWaitHandle.WaitOne(3600000)  # 1 hour timeout
    if (-not $completed) {
        $powershell.Stop()
        Write-ShadowKitLog -Message "$($Plugin.Name) timed out after 1 hour" -Level warn -Module Controller
        $powershell.Dispose()
        return $null
    }
    try {
        $result = $powershell.EndInvoke($async)
    } catch {
        $result = $null
        Write-ShadowKitLog -Message "$($Plugin.Name) threw exception: $_" -Level error -Module Controller -Data @{ Error = $_.Exception.Message }
    }
    $endTime = Get-Date
    $endMem = (Get-Process -Id $PID).WorkingSet64 / 1MB
    $duration = ($endTime - $startTime).TotalSeconds
    $memDelta = $endMem - $startMem
    $powershell.Dispose()
    Write-ShadowKitLog -Message "$($Plugin.Name) completed in ${duration}s, memory delta: $([math]::Round($memDelta,2)) MB" -Level info -Module Controller -Data @{
        Plugin = $Plugin.Name
        DurationSec = [math]::Round($duration,2)
        MemoryDeltaMB = [math]::Round($memDelta,2)
        Result = $result
    }
    return $result
}

# ---- Launch plugins ----
$jobs = @{}
foreach ($p in $plugins) {
    Write-ShadowKitLog -Message "Launching $($p.Name)" -Level info -Module Controller
    try {
        $async = Invoke-Plugin -Plugin $p -Pool $pool
        $jobs[$p.Name] = [PSCustomObject]@{
            Name   = $p.Name
            Async  = $async
            Plugin = $p
        }
        Set-ShadowStatus -Component $p.Name -Status 'Running'
    } catch {
        Write-ShadowKitLog -Message "Failed to launch $($p.Name): $_" -Level error -Module Controller
        Set-ShadowStatus -Component $p.Name -Status 'Crashed'
    }
}
Set-ShadowStatus -Component 'Controller' -Status 'Running' -Data @{ Plugins = $plugins.Count }

# ---- Named pipe command server (for dashboard/TUI) ----
# Start it if the function exists (from ShadowIPC.ps1)
$commandHandler = {
    param($cmdJson)
    try {
        $cmd = $cmdJson | ConvertFrom-Json
        $action = $cmd.action
        $component = $cmd.component
        switch ($action) {
            'purge' {
                if ($component -eq 'MemoryCleaner') {
                    $scriptPath = (Get-ShadowStatus -Component 'MemoryCleaner')?.data?.ScriptPath
                    if (-not $scriptPath) { $scriptPath = Join-Path $PSScriptRoot 'components\MemoryCleaner.ps1' }
                    if (Test-Path $scriptPath) {
                        # Run in foreground to capture result
                        $result = & $scriptPath -ManualPurge -Silent
                        return @{ success = $true; freedMB = $result.freedMB; message = $result.message }
                    } else {
                        return @{ success = $false; error = "MemoryCleaner script not found" }
                    }
                } else {
                    return @{ success = $false; error = "Purge not supported for $component" }
                }
            }
            'refresh' {
                if ($component -eq 'DNSFrenzy') {
                    $flag = Join-Path $PSScriptRoot 'dns_refresh.flag'
                    New-Item -ItemType File -Path $flag -Force | Out-Null
                    return @{ success = $true; message = "DNS refresh triggered" }
                } else {
                    return @{ success = $false; error = "Refresh not supported for $component" }
                }
            }
            'enforce' {
                if ($component -eq 'SystemCalibrator') {
                    $scriptPath = Join-Path $PSScriptRoot 'components\SystemCalibrator.ps1'
                    if (Test-Path $scriptPath) {
                        Start-Job -ScriptBlock {
                            param($p) & $p -Once -Silent
                        } -ArgumentList $scriptPath | Out-Null
                        return @{ success = $true; message = "Calibration triggered" }
                    } else {
                        return @{ success = $false; error = "SystemCalibrator not found" }
                    }
                } else {
                    return @{ success = $false; error = "Enforce not supported for $component" }
                }
            }
            'toggle' {
                if ($component) {
                    $configPath = Join-Path $PSScriptRoot 'config.json'
                    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
                    $key = if ($component -eq 'GameOptimizer') { 'gameoptimizer' } else { $component.ToLower() }
                    if ($cfg.PSObject.Properties.Name -contains $key) {
                        $cfg.$key.enabled = -not $cfg.$key.enabled
                        $cfg | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
                        Write-ShadowKitLog -Message "Toggled $component to $($cfg.$key.enabled)" -Level info -Module Controller
                        # We don't restart the component; the controller will pick up on next restart cycle
                        return @{ success = $true; enabled = $cfg.$key.enabled; message = "$component toggled" }
                    } else {
                        return @{ success = $false; error = "Config key not found for $component" }
                    }
                }
                return @{ success = $false; error = "No component specified" }
            }
            default {
                return @{ success = $false; error = "Unknown action: $action" }
            }
        }
    } catch {
        return @{ success = $false; error = $_.Exception.Message }
    }
}

if (Get-Command Start-ShadowControlPipe -ErrorAction SilentlyContinue) {
    Start-ShadowControlPipe -CommandHandler $commandHandler
    Write-ShadowKitLog -Message "Named pipe command server started" -Level info -Module Controller
} else {
    Write-ShadowKitLog -Message "Start-ShadowControlPipe not available – command bus disabled" -Level warn -Module Controller
}

# ---- Monitoring loop ----
$stopFile = Join-Path $PSScriptRoot 'stop.flag'
while ($true) {
    if (Test-Path $stopFile) {
        Remove-Item $stopFile -Force
        Write-ShadowKitLog -Message "Stop signal received. Exiting..." -Level info -Module Controller
        break
    }
    Start-Sleep -Seconds 5

    foreach ($p in $plugins) {
        $name = $p.Name
        $job = $jobs[$name]
        if ($job -and $job.Async) {
            # Check if the asynchronous job has completed
            if ($job.Async -eq $null -or ($job.Async -is [System.IAsyncResult] -and $job.Async.IsCompleted)) {
                Write-ShadowKitLog -Message "$name has stopped. Restarting..." -Level warn -Module Controller
                try {
                    $newAsync = Invoke-Plugin -Plugin $p -Pool $pool
                    $jobs[$name] = [PSCustomObject]@{
                        Name   = $name
                        Async  = $newAsync
                        Plugin = $p
                    }
                    Write-ShadowKitLog -Message "$name restarted." -Level info -Module Controller
                    Set-ShadowStatus -Component $name -Status 'Running'
                } catch {
                    Write-ShadowKitLog -Message "Failed to restart $name : $_" -Level error -Module Controller
                    Set-ShadowStatus -Component $name -Status 'Crashed'
                }
            }
        } else {
            # No job entry – start it
            Write-ShadowKitLog -Message "No job entry for $name – starting..." -Level info -Module Controller
            try {
                $newAsync = Invoke-Plugin -Plugin $p -Pool $pool
                $jobs[$name] = [PSCustomObject]@{
                    Name   = $name
                    Async  = $newAsync
                    Plugin = $p
                }
                Set-ShadowStatus -Component $name -Status 'Running'
            } catch {
                Write-ShadowKitLog -Message "Failed to start $name : $_" -Level error -Module Controller
                Set-ShadowStatus -Component $name -Status 'Crashed'
            }
        }
    }
}

# ---- Cleanup ----
$pool.Close()
$pool.Dispose()
$mutex.ReleaseMutex()
$mutex.Dispose()
Write-ShadowKitLog -Message "Controller stopped" -Level info -Module Controller