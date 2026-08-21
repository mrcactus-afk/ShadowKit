param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\networkoptimizer.state.json'
$logFile = Join-Path $baseDir 'logs\network.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-NetLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-NetLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($adapter in $state.PSObject.Properties) {
        $name = $adapter.Name
        $data = $adapter.Value
        try {
            if ($data.powerMgmt -eq 'Enabled') { Enable-NetAdapterPowerManagement -Name $name -ErrorAction SilentlyContinue }
            else { Disable-NetAdapterPowerManagement -Name $name -ErrorAction SilentlyContinue }
            Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation' -DisplayValue $data.interruptModeration -ErrorAction SilentlyContinue
            Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Energy Efficient Ethernet' -DisplayValue $data.eee -ErrorAction SilentlyContinue
            if ($data.rssEnabled) { Enable-NetAdapterRss -Name $name -ErrorAction SilentlyContinue }
            else { Disable-NetAdapterRss -Name $name -ErrorAction SilentlyContinue }
            Write-NetLog "Restored $name"
        } catch { Write-NetLog "Failed to restore $name : $_" error }
    }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'NetworkOptimizer' -Status 'Reverted'
    Write-NetLog 'NetworkOptimizer revert complete'
    exit 0
}

if ($Apply) {
    $state = @{}
    $adapters = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
    foreach ($a in $adapters) {
        $name = $a.Name
        $pm = (Get-NetAdapterPowerManagement -Name $name -ErrorAction SilentlyContinue).Enabled
        $intMod = (Get-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation' -ErrorAction SilentlyContinue).DisplayValue
        $eee = (Get-NetAdapterAdvancedProperty -Name $name -DisplayName 'Energy Efficient Ethernet' -ErrorAction SilentlyContinue).DisplayValue
        $rss = (Get-NetAdapterRss -Name $name -ErrorAction SilentlyContinue).Enabled
        $state[$name] = @{ powerMgmt = if ($pm) { 'Enabled' } else { 'Disabled' }; interruptModeration = $intMod; eee = $eee; rssEnabled = $rss }
        Disable-NetAdapterPowerManagement -Name $name -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Interrupt Moderation' -DisplayValue 'Disabled' -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $name -DisplayName 'Energy Efficient Ethernet' -DisplayValue 'Disabled' -ErrorAction SilentlyContinue
        Enable-NetAdapterRss -Name $name -ErrorAction SilentlyContinue
        Write-NetLog "Optimized $name"
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'NetworkOptimizer' -Status 'Applied'
    Write-NetLog 'NetworkOptimizer apply complete'
    exit 0
}
Write-Host "Usage: NetworkOptimizer.ps1 -Apply   or   -Revert"
