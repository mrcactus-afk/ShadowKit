# ShadowController.ps1 - Supervisor with log rotation
param([switch]$Silent)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\ShadowKit' }
Set-Location $scriptDir
$baseDir = 'C:\ShadowKit'
$stateDir = Join-Path $baseDir 'state'
$logDir = Join-Path $baseDir 'logs'
New-Item -ItemType Directory -Path $stateDir, $logDir -Force | Out-Null

function Write-CtlLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File (Join-Path $logDir 'controller.log') -Append -Encoding UTF8 }

$mutexName = 'Global\ShadowKitControllerMutex'
try {
    $existing = [System.Threading.Mutex]::OpenExisting($mutexName)
    Write-CtlLog 'Another controller running. Exiting.' warn
    exit 0
} catch {
    $mtx = New-Object System.Threading.Mutex($false, $mutexName)
    try {
        if (-not $mtx.WaitOne(0)) { Write-CtlLog 'Mutex contention. Exiting.' warn; exit 0 }
    } catch {
        Write-CtlLog "Mutex error: $_" error
        exit 1
    }
}

Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

$components = @(
    @{ Name = 'SystemCalibrator'; Script = 'components\SystemCalibrator.ps1'; Args = @() },
    @{ Name = 'MemoryCleaner';    Script = 'components\MemoryCleaner.ps1';    Args = @() },
    @{ Name = 'DNSFrenzy';        Script = 'components\DNSFrenzy.ps1';        Args = @() },
    @{ Name = 'TimerOptimizer';   Script = 'components\TimerOptimizer.ps1';   Args = @() }
)

$procTable = @{}
$restartCounts = @{}

function Start-ComponentProc {
    param($Comp)
    $fullPath = Join-Path $baseDir $Comp.Script
    if (-not (Test-Path $fullPath)) {
        Write-CtlLog "Component script not found: $fullPath" error
        Set-ShadowStatus -Component $Comp.Name -Status 'Failed' -Data @{ error = 'Script not found' }
        return
    }
    $argString = $Comp.Args -join ' '
    $proc = Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$fullPath`" $argString" -PassThru
    $procTable[$Comp.Name] = $proc.Id
    $restartCounts[$Comp.Name] = 0
    Set-ShadowStatus -Component $Comp.Name -Status 'Running' -Data @{ pid = $proc.Id; startTime = (Get-Date).ToString('o') }
    Write-CtlLog "Started $($Comp.Name) PID $($proc.Id)"
}

foreach ($comp in $components) { Start-ComponentProc $comp }

Set-ShadowStatus -Component 'Controller' -Status 'Running' -Data @{ components = $components.Count; pid = $PID }

$stopFile = Join-Path $baseDir 'stop.flag'
$lastLogRotate = Get-Date
while ($true) {
    if (Test-Path $stopFile) {
        Remove-Item $stopFile -Force
        Write-CtlLog 'Stop signal received'
        foreach ($name in $procTable.Keys) {
            $pidToKill = $procTable[$name]
            Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue
        }
        break
    }

    foreach ($comp in $components) {
        $name = $comp.Name
        $oldPid = $procTable[$name]
        $proc = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
        if (-not $proc) {
            Set-ShadowStatus -Component $name -Status 'Crashed'
            Write-CtlLog "$name (PID $oldPid) died"
            $count = $restartCounts[$name]
            $delay = [math]::Min(300, [math]::Pow(2, $count))
            Write-CtlLog "Restarting $name in $delay seconds (attempt $($count+1))"
            Start-Sleep -Seconds $delay
            $restartCounts[$name]++
            Start-ComponentProc $comp
        }
    }

    $cmdFile = Join-Path $stateDir 'command.json'
    if (Test-Path $cmdFile) {
        $mtxCmd = New-Object System.Threading.Mutex($false, 'Global\ShadowKitCommandMutex')
        try {
            if ($mtxCmd.WaitOne(1000)) {
                $cmd = Get-Content $cmdFile -Raw | ConvertFrom-Json
                $response = @{
                    requestId = $cmd.requestId
                    success   = $true
                    result    = "Handled action: $($cmd.action)"
                    timestamp = (Get-Date).ToString('o')
                }
                switch ($cmd.action) {
                    'stop' {
                        $response.result = "Stopping controller"
                        Set-Content (Join-Path $stateDir 'stop.flag') -Value 'stop'
                    }
                    'purge' {
                        $script = Join-Path $baseDir 'components\MemoryCleaner.ps1'
                        $out = & $script -ManualPurge -Silent
                        $response.result = "Memory purge executed"
                        if ($out) { $response.data = $out }
                    }
                    'refresh' {
                        $script = Join-Path $baseDir 'components\DNSFrenzy.ps1'
                        $out = & $script -Once -Silent
                        $response.result = "DNS refresh executed"
                        if ($out) { $response.data = $out }
                    }
                    'enforce' {
                        $script = Join-Path $baseDir 'components\SystemCalibrator.ps1'
                        $out = & $script -Enforce -Silent
                        $response.result = "Calibration enforcement executed"
                        if ($out) { $response.data = $out }
                    }
                    default {
                        $response.result = "Action '$($cmd.action)' acknowledged"
                    }
                }
                $response | ConvertTo-Json -Compress | Set-Content (Join-Path $stateDir 'command_response.json') -Encoding UTF8
                Remove-Item $cmdFile -Force
            }
        } finally {
            try { $mtxCmd.ReleaseMutex() } catch {}
            $mtxCmd.Dispose()
        }
    }

    # Log rotation (hourly)
    if (((Get-Date) - $lastLogRotate).TotalHours -ge 1) {
        $archiveDir = Join-Path $logDir 'archive'
        if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }
        Get-ChildItem $logDir -Filter '*.log' | Where-Object { $_.Length -gt 5MB } | ForEach-Object {
            $newName = $_.BaseName + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'
            Move-Item $_.FullName (Join-Path $archiveDir $newName) -Force
            Write-CtlLog "Rotated $($_.Name)"
        }
        $lastLogRotate = Get-Date
    }

    Start-Sleep -Seconds 3
}

if ($mtx) { $mtx.ReleaseMutex(); $mtx.Dispose() }
Write-CtlLog 'Controller stopped'
