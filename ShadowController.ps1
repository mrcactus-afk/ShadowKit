param([switch]$Silent)
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = 'C:\ShadowKit' }
Set-Location $scriptDir

$lockFile = Join-Path $scriptDir 'controller.lock'
if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalSeconds -lt 5) { exit 0 }
    else { Remove-Item $lockFile -Force }
}
New-Item -ItemType File -Path $lockFile -Force | Out-Null
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Remove-Item $lockFile -Force -ErrorAction SilentlyContinue }

function Write-Log {
    param($m,$l='info')
    $logDir = Join-Path $scriptDir 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logFile = Join-Path $logDir 'shadowkit.log'
    "$(Get-Date -Format 'o') [$l] $m" | Out-File -Append $logFile -Encoding UTF8
}
Write-Log "Controller started (v6.9)"

$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path $configPath)) { Write-Log "Config missing" error; exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json

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
    }
}
Write-Log "Discovered $($plugins.Count) plugins"

$processes = @{}
foreach ($p in $plugins) {
    Write-Log "Launching $($p.Name) from $($p.ScriptPath)"
    try {
        $logFile = Join-Path $scriptDir "logs\$($p.Name).log"
        $errFile = Join-Path $scriptDir "logs\$($p.Name).err"
        $proc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($p.ScriptPath)`" -Silent" -WindowStyle Hidden -PassThru -RedirectStandardOutput $logFile -RedirectStandardError $errFile
        $processes[$p.Name] = $proc
        Write-Log "$($p.Name) launched with PID $($proc.Id)"
    } catch {
        Write-Log "Failed to launch $($p.Name): $_" error
    }
}

$stopFile = Join-Path $scriptDir 'stop.flag'
while ($true) {
    if (Test-Path $stopFile) {
        Remove-Item $stopFile -Force
        Write-Log "Stop signal received. Exiting..."
        break
    }
    Start-Sleep -Seconds 5
    foreach ($p in $plugins) {
        $name = $p.Name
        $proc = $processes[$name]
        if (-not $proc -or $proc.HasExited) {
            Write-Log "$name has exited. Restarting..."
            try {
                $logFile = Join-Path $scriptDir "logs\$($name).log"
                $errFile = Join-Path $scriptDir "logs\$($name).err"
                $newProc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($p.ScriptPath)`" -Silent" -WindowStyle Hidden -PassThru -RedirectStandardOutput $logFile -RedirectStandardError $errFile
                $processes[$name] = $newProc
                Write-Log "$name restarted with PID $($newProc.Id)"
            } catch {
                Write-Log "Failed to restart $name : $_" error
            }
        }
    }
}
Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
Write-Log "Controller stopped"
