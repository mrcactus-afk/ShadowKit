. 'C:\ShadowKit\components\ShadowIPC.ps1' -ErrorAction SilentlyContinue
Set-ShadowStatus -Component 'DNSFrenzy' -Status 'Running' -Data @{}
. "$PSScriptRoot\ShadowIPC.ps1"
. "$PSScriptRoot\ShadowLogger.ps1"

Get-EventSubscriber -SourceIdentifier "ShadowKitNetworkWatcher" -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue

try {
    Register-WmiEvent -Query "SELECT * FROM __InstanceModificationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_NetworkAdapter' AND TargetInstance.NetConnectionStatus != PreviousInstance.NetConnectionStatus" -Action {
        New-Item -ItemType File -Path "C:\ShadowKit\network_changed.flag" -Force | Out-Null
    } -SourceIdentifier "ShadowKitNetworkWatcher" | Out-Null
} catch { Write-ShadowKitLog "WMI Event Registration failed: $_" "warn" "DNSFrenzy" }

while ($true) {
    Set-ShadowStatus -Component "DNSFrenzy" -Status "Running"
    if (Test-Path "C:\ShadowKit\network_changed.flag") {
        Remove-Item "C:\ShadowKit\network_changed.flag" -Force -ErrorAction SilentlyContinue
        Write-ShadowKitLog "Network adapter change detected, re-evaluating DNS" "info" "DNSFrenzy"
    }
    Start-Sleep -Seconds 30
}

