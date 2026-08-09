# No mutex – uses lock file with stale cleanup
param([switch]$Silent)
$scriptDir = $PSScriptRoot
$lockFile = Join-Path $scriptDir 'controller.lock'

# Check if lock file exists and is stale (older than 5 seconds)
if (Test-Path $lockFile) {
    $lockAge = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($lockAge.TotalSeconds -lt 5) {
        # Lock is fresh – another controller is running
        Write-Host "$(Get-Date) - Lock file present and fresh, exiting." -ForegroundColor Yellow
        exit 0
    } else {
        # Lock is stale – remove it
        Write-Host "$(Get-Date) - Stale lock file found, removing." -ForegroundColor Yellow
        Remove-Item $lockFile -Force
    }
}

# Create lock file
try {
    New-Item -ItemType File -Path $lockFile -Force | Out-Null
} catch {
    Write-Host "$(Get-Date) - Failed to create lock file, exiting." -ForegroundColor Red
    exit 1
}

# Ensure lock file is removed on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }

# Now proceed with controller logic
. (Join-Path $scriptDir 'components\ShadowIPC.ps1')
. (Join-Path $scriptDir 'components\ShadowLogger.ps1')
$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path $configPath)) { Write-ShadowKitLog 'Config missing' error Controller; Remove-Item $lockFile -Force; exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
Write-ShadowKitLog 'Controller started (lock file)' info Controller

$plugins = @()
Get-ChildItem -Path (Join-Path $scriptDir 'components') -Filter 'plugin.json' -Recurse | ForEach-Object {
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
        $plugins += [PSCustomObject]@{ Name = $man.Name; ScriptPath = $scriptPath }
        Write-ShadowKitLog "Plugin enabled: $($man.Name)" info Controller
    }
}
Write-ShadowKitLog "Discovered $($plugins.Count) plugins" info Controller

$runspaces = @{}; $restartCounts = @{}; $nextRestart = @{}
function Start-Plugin {
    param($Plugin)
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    $ps.AddScript({ param($p) & $p -Silent }).AddArgument($Plugin.ScriptPath) | Out-Null
    $async = $ps.BeginInvoke()
    Write-ShadowKitLog "$($Plugin.Name) launched" info Controller
    Set-ShadowStatus -Component $Plugin.Name -Status 'Running'
    return @{ Runspace = $rs; PowerShell = $ps; Async = $async; Plugin = $Plugin }
}
foreach ($p in $plugins) {
    $runspaces[$p.Name] = Start-Plugin $p
    $restartCounts[$p.Name] = 0
    $nextRestart[$p.Name] = [datetime]::MinValue
}
Set-ShadowStatus -Component 'Controller' -Status 'Running' -Data @{ Plugins = $plugins.Count }
$stopFile = Join-Path $scriptDir 'stop.flag'
while ($true) {
    if (Test-Path $stopFile) { Remove-Item $stopFile -Force; break }
    Start-Sleep -Seconds 5
    foreach ($p in $plugins) {
        $name = $p.Name
        $state = $runspaces[$name]
        if (-not $state) { continue }
        if ($state.Async.IsCompleted) {
            $err = $state.PowerShell.Streams.Error | Out-String
            if ($err) { Write-ShadowKitLog "$name crashed: $err" error Controller }
            else { Write-ShadowKitLog "$name exited unexpectedly" warn Controller }
            $state.PowerShell.Dispose(); $state.Runspace.Close(); $state.Runspace.Dispose()
            $runspaces[$name] = $null
            $restartCounts[$name]++
            $delay = [math]::Min(300, [math]::Pow(2, $restartCounts[$name]))
            Write-ShadowKitLog "$name backoff $delay s (restart #$($restartCounts[$name]))" warn Controller
            $nextRestart[$name] = (Get-Date).AddSeconds($delay)
            Set-ShadowStatus -Component $name -Status 'Crashed' -Data @{ Restarts = $restartCounts[$name] }
        }
        elseif ($nextRestart[$name] -ne [datetime]::MinValue -and (Get-Date) -ge $nextRestart[$name]) {
            Write-ShadowKitLog "Restarting $name" info Controller
            $runspaces[$name] = Start-Plugin $p
            $nextRestart[$name] = [datetime]::MinValue
        }
    }
}
