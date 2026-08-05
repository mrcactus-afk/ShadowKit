$ErrorActionPreference = "SilentlyContinue"
$Root = "C:\ShadowKit"
$LogDir = Join-Path $Root "logs"
$script:failCount = 0
$results = New-Object System.Collections.Generic.List[string]

function Add-Check {
    param($Name, $Ok, $Detail)
    if ($Ok) { $results.Add("[PASS] " + $Name + " - " + $Detail) }
    else { $script:failCount++; $results.Add("[FAIL] " + $Name + " - " + $Detail) }
}

function Count-Component {
    param($Name)
    for ($a = 1; $a -le 2; $a++) {
        $p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$Name*" }
        $c = @($p).Count
        if ($c -gt 0) { return $c }
        Start-Sleep -Seconds 2
    }
    return 0
}

function Test-LogFresh { param($Path, $Minutes) return ((Test-Path $Path) -and ((Get-Item $Path).LastWriteTime -gt (Get-Date).AddMinutes(-$Minutes))) }
function Test-LogTail { param($Path, $Pattern) if (-not (Test-Path $Path)) { return $false }; $tail = @(Get-Content $Path -Tail 30); return (($tail | Where-Object { $_ -match $Pattern }).Count -gt 0) }

foreach ($name in @("ShadowController.ps1", "Watchdog.ps1", "DNSFrenzy.ps1", "TimerOptimizer.ps1", "MemoryCleaner.ps1")) {
    Add-Check $name ((Count-Component $name) -eq 1) ("instances: " + (Count-Component $name))
}

$task = Get-ScheduledTask -TaskName "ShadowKitController"
Add-Check "ScheduledTask" ($task.State -eq "Running") ("state: " + $task.State)

$cfg = Get-Content (Join-Path $Root "config.json") -Raw | ConvertFrom-Json
Add-Check "Config" ($cfg.watchdog.enabled -and $cfg.dns.enabled -and $cfg.timer.enabled -and $cfg.memory.enabled) "all modules enabled"

$master = Get-ChildItem (Join-Path $LogDir "master_*.log") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Add-Check "MasterLog" ((Test-LogTail $master.FullName "Entering monitoring loop") -and -not (Test-LogTail $master.FullName "process died|process missing|Failed to start")) "tail clean"

Add-Check "WatchdogLog" ((Test-LogFresh (Join-Path $LogDir "watchdog.log") 10) -and (Test-LogTail (Join-Path $LogDir "watchdog.log") "System integrity OK")) "check cycle active"

& (Join-Path $Root "components\WatchdogHelper.ps1") -Check | Out-Null
Add-Check "HelperIntegrity" ($LASTEXITCODE -eq 0) ("exit code: " + $LASTEXITCODE)

Add-Check "DNSLog" ((Test-LogFresh (Join-Path $LogDir "dns.log") 15) -and (Test-LogTail (Join-Path $LogDir "dns.log") "DNS set to|Using cached best server")) "cycle active"

$timerCs = @"
using System;
using System.Runtime.InteropServices;
public class TimerQuery {
    [DllImport("ntdll.dll")]
    public static extern int NtQueryTimerResolution(out uint Min, out uint Max, out uint Cur);
}
"@
try { Add-Type -TypeDefinition $timerCs } catch {}
$tMin = [uint32]0; $tMax = [uint32]0; $tCur = [uint32]0
[TimerQuery]::NtQueryTimerResolution([ref]$tMin, [ref]$tMax, [ref]$tCur) | Out-Null
Add-Check "TimerResolution" ($tCur -le 5000) ("current: " + ($tCur / 10000.0) + " ms")

Add-Check "MemoryLog" ((Test-LogFresh (Join-Path $LogDir "memory.log") 10) -and (Test-LogTail (Join-Path $LogDir "memory.log") "Standby:")) "cycle active"
Add-Check "MemoryPurge" (-not (Test-LogTail (Join-Path $LogDir "memory.log") "All purge methods failed")) "no purge failures"

$now = Get-Date
$freshErrors = New-Object System.Collections.Generic.List[string]
Get-ChildItem $LogDir -Filter "*.log" | Where-Object { $_.Name -ne "popup.log" } | ForEach-Object {
    $logName = $_.Name
    foreach ($line in @(Get-Content $_.FullName -Tail 200)) {
        if ($line -match '^\[(?<ts>[^\]]+)\]\s*\[error\]\s*(?<msg>.*)$') {
            $ts = [datetime]::MinValue
            if ([datetime]::TryParse($Matches['ts'], [ref]$ts)) {
                if ($ts -gt $now.AddMinutes(-60) -and $ts -le $now.AddMinutes(5)) { $freshErrors.Add("[" + $logName + "] " + $Matches['msg']) }
            }
        }
    }
}
Add-Check "FreshErrors" ($freshErrors.Count -eq 0) ("count in last 60 min: " + $freshErrors.Count)

$results
""
if ($script:failCount -eq 0) { "OVERALL: ALL CHECKS PASSED" } else { "OVERALL: " + $script:failCount + " CHECK(S) FAILED" }
