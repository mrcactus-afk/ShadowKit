param([switch]$Silent)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

. "C:\ShadowKit\components\ShadowIPC.ps1"
. "C:\ShadowKit\components\ShadowLogger.ps1"

$scriptDir = "C:\ShadowKit"
$configPath = Join-Path $scriptDir "config.json"
$componentsDir = Join-Path $scriptDir "components"

$mutex = New-Object System.Threading.Mutex($false, "ShadowKitController")
$acquired = $false
try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
if (-not $acquired) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
Write-ShadowKitLog -Message "Controller v4 initializing (Runspace Plugin Loader)..." -Level info -Module Controller
Set-ShadowStatus -Component "Controller" -Status "Starting"

$plugins = @()
$manifests = Get-ChildItem -Path $componentsDir -Filter "plugin.json" -Recurse -ErrorAction SilentlyContinue
foreach ($m in $manifests) {
    $man = $null
    try { $man = Get-Content $m.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Write-ShadowKitLog -Message "Bad manifest $($m.FullName): $($_.Exception.Message)" -Level warn -Module Controller; continue }
    $scriptPath = Join-Path $m.DirectoryName $man.EntryPoint
    if (-not (Test-Path $scriptPath)) { Write-ShadowKitLog -Message "Manifest $($man.Name) points to missing script: $scriptPath - skipped." -Level warn -Module Controller; continue }
    $configKey = $man.ConfigKey
    $enabled = $true
    if ($configKey -and $config.PSObject.Properties.Name -contains $configKey) { $enabled = [bool]$config.$configKey.enabled }
    if ($man.Enabled -and $enabled) { $plugins += [PSCustomObject]@{ Name = $man.Name; ScriptPath = $scriptPath } }
}

Write-ShadowKitLog -Message "Discovered $($plugins.Count) enabled plugins." -Level info -Module Controller
$runspaces = @{}; $restartCounts = @{}; $nextRestart = @{}

function Start-Plugin {
    param($Plugin)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "STA"; $rs.ThreadOptions = "ReuseThread"; $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({ param($path) & $path -Silent }) | Out-Null
    $ps.AddArgument($Plugin.ScriptPath) | Out-Null
    $async = $ps.BeginInvoke()
    Write-ShadowKitLog -Message "$($Plugin.Name) launched in isolated runspace." -Level info -Module Controller
    Set-ShadowStatus -Component $Plugin.Name -Status "Running"
    return @{ Runspace = $rs; PowerShell = $ps; Async = $async; Plugin = $Plugin }
}

foreach ($p in $plugins) {
    $runspaces[$p.Name] = Start-Plugin -Plugin $p
    $restartCounts[$p.Name] = 0
    $nextRestart[$p.Name] = [datetime]::MinValue
}

Write-ShadowKitLog -Message "Entering monitoring loop." -Level info -Module Controller
Set-ShadowStatus -Component "Controller" -Status "Running" -Data @{ Plugins = $plugins.Count }

while ($true) {
    Start-Sleep -Seconds 5
    foreach ($p in $plugins) {
        $name = $p.Name
        if ($runspaces[$name] -and $runspaces[$name].Async -and -not $runspaces[$name].Async.IsCompleted) {
            if ($restartCounts[$name] -gt 0 -and $nextRestart[$name] -eq [datetime]::MinValue) {
                $restartCounts[$name] = 0
            }
        }
    }
    foreach ($p in $plugins) {
        $name = $p.Name; $state = $runspaces[$name]
        if (-not $state) { continue }
        if ($state.Async.IsCompleted) {
            $err = $state.PowerShell.Streams.Error | Out-String
            if ($err) { Write-ShadowKitLog -Message "$name crashed: $err" -Level error -Module Controller }
            else { Write-ShadowKitLog -Message "$name exited unexpectedly." -Level warn -Module Controller }
            $state.PowerShell.Dispose(); $state.Runspace.Close(); $state.Runspace.Dispose()
            $runspaces[$name] = $null
            $restartCounts[$name]++
            $delay = [math]::Min(300, [math]::Pow(2, $restartCounts[$name]))
            Write-ShadowKitLog -Message "$name backoff: $delay seconds (restart #$($restartCounts[$name]))" -Level warn -Module Controller
            $nextRestart[$name] = (Get-Date).AddSeconds($delay)
            Set-ShadowStatus -Component $name -Status "Crashed" -Data @{ Restarts = $restartCounts[$name] }
        }
        elseif ($nextRestart[$name] -ne [datetime]::MinValue -and (Get-Date) -ge $nextRestart[$name]) {
            Write-ShadowKitLog -Message "Restarting $name after backoff." -Level info -Module Controller
            $runspaces[$name] = Start-Plugin -Plugin $p
            $nextRestart[$name] = [datetime]::MinValue
        }
    }
}

