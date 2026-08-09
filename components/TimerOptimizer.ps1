. "$PSScriptRoot\ShadowIPC.ps1"
. "$PSScriptRoot\ShadowLogger.ps1"

$member = '[DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint DesiredResolution, bool SetResolution, out uint CurrentResolution);'
$type = Add-Type -MemberDefinition $member -Name "NtTimer" -Namespace "Win32" -PassThru

Set-ShadowStatus -Component "TimerOptimizer" -Status "Running"
Write-ShadowKitLog "TimerOptimizer requested 0.5ms resolution" "info" "TimerOptimizer"

$cur = 0
$type::NtSetTimerResolution(5000, $true, [ref]$cur) | Out-Null

while ($true) {
    Set-ShadowStatus -Component "TimerOptimizer" -Status "Running" -Data @{ resolutionNs = $cur }
    Start-Sleep -Seconds 30
}

# Keep alive for controller
while ($true) { Start-Sleep -Seconds 3600 }
