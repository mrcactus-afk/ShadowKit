. "$PSScriptRoot\components\ShadowIPC.ps1"
. "$PSScriptRoot\components\ShadowLogger.ps1"

Set-ShadowStatus -Component "Controller" -Status "Running"
Write-ShadowKitLog "ShadowController starting..." "info" "Controller"

$plugins = Get-ChildItem "$PSScriptRoot\components" -Filter "*.ps1" | Where-Object { $_.Name -notlike "Shadow*" -and $_.Name -ne "WatchdogHelper.ps1" }
$runspaces = @{}; $restartCounts = @{}; $nextRestart = @{}

foreach ($p in $plugins) {
    $name = $p.BaseName
    $restartCounts[$name] = 0; $nextRestart[$name] = [datetime]::MinValue
    $ps = [powershell]::Create().AddScript($p.FullName)
    $runspaces[$name] = @{ PS = $ps; Async = $ps.BeginInvoke() }
    Write-ShadowKitLog "Launched plugin: $name" "info" "Controller"
}

while ($true) {
    Start-Sleep -Seconds 5
    Set-ShadowStatus -Component "Controller" -Status "Running"
    
    foreach ($p in $plugins) {
        $name = $p.BaseName
        $rs = $runspaces[$name]
        
        if ($rs -and $rs.Async -and $rs.Async.IsCompleted) {
            if ($restartCounts[$name] -gt 0 -and $nextRestart[$name] -eq [datetime]::MinValue) { $restartCounts[$name] = 0 }
            if ((Get-Date) -ge $nextRestart[$name]) {
                $restartCounts[$name]++
                $delay = [math]::Min([math]::Pow(2, $restartCounts[$name]), 60)
                $nextRestart[$name] = (Get-Date).AddSeconds($delay)
                Write-ShadowKitLog "Plugin $name died. Restarting in $delay s (Attempt $($restartCounts[$name]))" "warn" "Controller"
                
                $ps = [powershell]::Create().AddScript($p.FullName)
                $runspaces[$name] = @{ PS = $ps; Async = $ps.BeginInvoke() }
                $nextRestart[$name] = [datetime]::MinValue
            }
        }
    }
}
