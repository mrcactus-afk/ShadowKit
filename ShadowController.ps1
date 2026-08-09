param([switch]$Silent)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}
. (Join-Path $PSScriptRoot 'components\ShadowIPC.ps1')
. (Join-Path $PSScriptRoot 'components\ShadowLogger.ps1')
$scriptDir = $PSScriptRoot
$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path $configPath)) { Write-ShadowKitLog 'Config missing' error Controller; exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$mutex = New-Object System.Threading.Mutex($false, 'ShadowKitController')
if (-not $mutex.WaitOne(0)) { Write-ShadowKitLog 'Another controller running' info Controller; exit 0 }
Write-ShadowKitLog 'Controller started' info Controller

$plugins = @()
Get-ChildItem -Path (Join-Path $scriptDir 'components') -Filter 'plugin.json' -Recurse | ForEach-Object {
    $man = $_ | Get-Content -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $man) { return }
    $scriptPath = $man.EntryPoint
    if (-not (Test-Path $scriptPath)) { 
        # If the path is relative, try to resolve it from the manifest directory
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
