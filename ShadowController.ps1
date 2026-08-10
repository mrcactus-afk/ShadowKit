param([switch]$Silent)

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = 'C:\ShadowKit' }
Set-Location $scriptDir

# Load IPC and Logger (fallback if missing)
. (Join-Path $scriptDir 'components\ShadowIPC.ps1') -ErrorAction SilentlyContinue
. (Join-Path $scriptDir 'components\ShadowLogger.ps1') -ErrorAction SilentlyContinue

# Fallback logger if missing
if (-not (Get-Command Write-ShadowKitLog -ErrorAction SilentlyContinue)) {
    function Write-ShadowKitLog {
        param($Message, $Level='info', $Module='Controller', $Data=@{})
        $logDir = Join-Path $scriptDir 'logs'
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logFile = Join-Path $logDir 'shadowkit.log'
        "$(Get-Date -Format 'o') [$Level] [$Module] $Message" | Out-File -Append $logFile -Encoding UTF8
    }
}

# Singleton lock file
$lockFile = Join-Path $scriptDir 'controller.lock'
if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalSeconds -lt 5) {
        Write-ShadowKitLog "Another controller is running (lock fresh)" -Level info
        exit 0
    } else {
        Remove-Item $lockFile -Force
        Write-ShadowKitLog "Stale lock removed" -Level info
    }
}
New-Item -ItemType File -Path $lockFile -Force | Out-Null
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

Write-ShadowKitLog "Controller started (simple process‑based)" -Level info

# Read config
$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path $configPath)) {
    Write-ShadowKitLog "Config missing at $configPath" -Level error
    exit 1
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Discover plugins
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
        $plugins += [PSCustomObject]@{
            Name       = $man.Name
            ScriptPath = $scriptPath
        }
    }
}
Write-ShadowKitLog "Discovered $($plugins.Count) plugins" -Level info

# Launch each plugin as a separate process and store handles
$processes = @{}
foreach ($p in $plugins) {
    Write-ShadowKitLog "Launching $($p.Name) from $($p.ScriptPath)" -Level info
    try {
        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($p.ScriptPath)`" -Silent" -WindowStyle Hidden -PassThru
        $processes[$p.Name] = $proc
        Write-ShadowKitLog "$($p.Name) launched with PID $($proc.Id)" -Level info
        Set-ShadowStatus -Component $p.Name -Status 'Running' -Data @{ ScriptPath = $p.ScriptPath }
    } catch {
        Write-ShadowKitLog "Failed to launch $($p.Name): $_" -Level error
        Set-ShadowStatus -Component $p.Name -Status 'Crashed'
    }
}
Set-ShadowStatus -Component 'Controller' -Status 'Running' -Data @{ Plugins = $plugins.Count }

# Monitor loop
$stopFile = Join-Path $scriptDir 'stop.flag'
while ($true) {
    if (Test-Path $stopFile) {
        Remove-Item $stopFile -Force
        Write-ShadowKitLog "Stop signal received. Exiting..." -Level info
        break
    }
    Start-Sleep -Seconds 10

    foreach ($p in $plugins) {
        $name = $p.Name
        $proc = $processes[$name]
        if (-not $proc -or $proc.HasExited) {
            Write-ShadowKitLog "$name has exited. Restarting..." -Level warn
            try {
                $newProc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($p.ScriptPath)`" -Silent" -WindowStyle Hidden -PassThru
                $processes[$name] = $newProc
                Write-ShadowKitLog "$name restarted with PID $($newProc.Id)" -Level info
                Set-ShadowStatus -Component $name -Status 'Running'
            } catch {
                Write-ShadowKitLog "Failed to restart $name : $_" -Level error
                Set-ShadowStatus -Component $name -Status 'Crashed'
            }
        }
    }
}

Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
Write-ShadowKitLog "Controller stopped" -Level info
