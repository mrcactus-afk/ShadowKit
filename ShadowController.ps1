# ShadowKit Controller v7.0
# - Uses named mutex for singleton (no stale file locks)
# - RunspacePool for in-process component isolation
# - Per-component telemetry: execution time and memory delta
# - No Export-ModuleMember hacks (uses proper module)
param([switch]$Silent)

# Import proper module (ShadowLogger.psm1)
$modulePath = Join-Path $PSScriptRoot 'components\ShadowLogger.psm1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction Stop
} else {
    # Fallback stub if module not found
    function Write-ShadowKitLog { param($Message,$Level='info',$Module='System',$Data=@{}) }
    function Read-ShadowKitLog { param($Tail=200) return @() }
}

# Mutex for singleton (Global\ShadowKitControllerMutex)
$mutexName = 'Global\ShadowKitControllerMutex'
$mutex = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0)) {
    Write-ShadowKitLog -Message "Another controller is running. Exiting." -Level info -Module Controller
    exit 0
}
# Ensure mutex is released on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}

Write-ShadowKitLog -Message "Controller started (v7.0)" -Level info -Module Controller

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

# Create runspace pool (min=2, max=ProcessorCount+2)
$cpu = [Environment]::ProcessorCount
$min = [math]::Min(2, $cpu)
$max = $cpu + 2
$pool = [runspacefactory]::CreateRunspacePool($min, $max)
$pool.ApartmentState = 'MTA'
$pool.Open()
Write-ShadowKitLog -Message "Runspace pool created (min=$min, max=$max)" -Level info -Module Controller

# Helper to run a plugin and collect telemetry
function Invoke-Plugin {
    param($Plugin, $Pool)
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $Pool
    # Capture start time and memory
    $startTime = Get-Date
    $startMem = (Get-Process -Id $PID).WorkingSet64 / 1MB
    # Add the script to run
    $null = $powershell.AddScript({
        param($scriptPath)
        & $scriptPath -Silent
    }).AddArgument($Plugin.ScriptPath)
    # Begin invoke
    $async = $powershell.BeginInvoke()
    # Wait for completion (with timeout: 1 hour max)
    $completed = $async.AsyncWaitHandle.WaitOne(3600000)
    if (-not $completed) {
        $powershell.Stop()
        Write-ShadowKitLog -Message "$($Plugin.Name) timed out after 1 hour" -Level warn -Module Controller
        $powershell.Dispose()
        return $null
    }
    # Collect result
    try {
        $result = $powershell.EndInvoke($async)
    } catch {
        $result = $null
        Write-ShadowKitLog -Message "$($Plugin.Name) threw exception: $_" -Level error -Module Controller
    }
    $endTime = Get-Date
    $endMem = (Get-Process -Id $PID).WorkingSet64 / 1MB
    $duration = ($endTime - $startTime).TotalSeconds
    $memDelta = $endMem - $startMem
    $powershell.Dispose()
    # Log telemetry
    Write-ShadowKitLog -Message "$($Plugin.Name) completed in ${duration}s, memory delta: $([math]::Round($memDelta,2)) MB" -Level info -Module Controller -Data @{
        Plugin = $Plugin.Name
        DurationSec = [math]::Round($duration,2)
        MemoryDeltaMB = [math]::Round($memDelta,2)
        Result = $result
    }
    return $result
}

# Launch each plugin as a job in the pool
$jobs = @{}
foreach ($p in $plugins) {
    Write-ShadowKitLog -Message "Launching $($p.Name)" -Level info -Module Controller
    try {
        $job = [PSCustomObject]@{
            Name = $p.Name
            Async = Invoke-Plugin -Plugin $p -Pool $pool
        }
        $jobs[$p.Name] = $job
    } catch {
        Write-ShadowKitLog -Message "Failed to launch $($p.Name): $_" -Level error -Module Controller
    }
}

# Monitor loop – check for completed jobs and restart if needed
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
        if ($job -and $job.Async -eq $null) {
            # Job completed or failed – restart
            Write-ShadowKitLog -Message "$name has stopped. Restarting..." -Level warn -Module Controller
            try {
                $newJob = Invoke-Plugin -Plugin $p -Pool $pool
                $jobs[$name] = [PSCustomObject]@{ Name = $name; Async = $newJob }
                Write-ShadowKitLog -Message "$name restarted." -Level info -Module Controller
            } catch {
                Write-ShadowKitLog -Message "Failed to restart $name : $_" -Level error -Module Controller
            }
        }
    }
}

# Cleanup
$pool.Close()
$pool.Dispose()
$mutex.ReleaseMutex()
$mutex.Dispose()
Write-ShadowKitLog -Message "Controller stopped" -Level info -Module Controller