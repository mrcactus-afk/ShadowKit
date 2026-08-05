$ErrorActionPreference = "Stop"
$currentPid = $PID

for ($round = 1; $round -le 3; $round++) {
    $targets = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "ShadowKit" -and $_.ProcessId -ne $currentPid }
    if ($targets) { $targets | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
    Start-Sleep -Seconds 2
}

Start-ScheduledTask -TaskName "ShadowKitController"
Start-Sleep -Seconds 10

foreach ($name in @("ShadowController.ps1", "Watchdog.ps1", "DNSFrenzy.ps1", "TimerOptimizer.ps1", "MemoryCleaner.ps1")) {
    $p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$name*" }
    $name + " : " + @($p).Count
}
