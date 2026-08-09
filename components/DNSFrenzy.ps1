param([switch]$Silent)
$configPath = "C:\ShadowKit\config.json"

$logDir = "C:\ShadowKit\logs"
$logFile = Join-Path $logDir "dns.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $configPath)) { Write-Error "Config missing"; exit 1 }
$config = Get-Content $configPath | ConvertFrom-Json
$dnsConfig = $config.dns
$serversFile = if ($dnsConfig.serverListFile) { $dnsConfig.serverListFile } else { "C:\ShadowKit\servers.json" }
$fallbackDNS = $dnsConfig.fallbackDNS
$updateURL = $dnsConfig.updateURL
$interval = $dnsConfig.intervalMinutes
if (-not $interval -or $interval -lt 1) { $interval = 10 }
$dnsMix = if ($dnsConfig.PSObject.Properties.Name -contains 'dnsMix') { $dnsConfig.dnsMix } else { $false }
$cacheFile = "C:\ShadowKit\state\best_dns_cache.json"

function Write-DNSLog { param($m,$l="info") $ts=Get-Date -Format "yyyy-MM-dd HH:mm:ss"; $entry="[$ts] [$l] $m"; $entry|Out-File -Append $logFile; if(-not$Silent){if($l-eq"error"){Write-Host $entry -ForegroundColor Red}else{Write-Host $entry -ForegroundColor Cyan}} }

function Get-Servers {
    $list=$null
    if($updateURL-and$updateURL-ne""){
        try{ $r=Invoke-WebRequest -Uri $updateURL -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop; $new=$r.Content|ConvertFrom-Json; $v=$true; foreach($s in $new){ if(-not($s.PSObject.Properties.Name-contains'name'-and$s.PSObject.Properties.Name-contains'primary'-and$s.PSObject.Properties.Name-contains'secondary')){$v=$false;break}}; if($v){$new|ConvertTo-Json -Depth 3|Out-File $serversFile -Encoding UTF8;$list=$new;Write-DNSLog "Remote update OK"} }catch{Write-DNSLog "Remote update failed: $_" "error"}
    }
    if(-not$list -and (Test-Path $serversFile)){ $list=Get-Content $serversFile|ConvertFrom-Json; Write-DNSLog "Loaded local cache ($($list.Count) entries)" }
    if(-not$list){Write-DNSLog "No server list" "error"; return @()}
    return $list
}

function Test-Latency { param($IP) $ping=Test-Connection -ComputerName $IP -Count 2 -Quiet -ErrorAction SilentlyContinue; if(-not$ping){return $null}; $m=Test-Connection -ComputerName $IP -Count 2 -ErrorAction SilentlyContinue; $avg=($m|Measure-Object -Property ResponseTime -Average).Average; if($null -eq $avg){return $null}; $loss=($m|Where-Object{$_.StatusCode-ne0}).Count/2*100; return @{Latency=$avg;Loss=$loss} }

function Get-ActiveAdapter {
    $connProfile = Get-NetConnectionProfile | Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' } | Select-Object -First 1
    if ($connProfile) {
        $adapter = Get-NetAdapter -Name $connProfile.InterfaceAlias -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Up') {
            Write-DNSLog "Found internet adapter via connection profile: $($adapter.Name)"
            return $adapter
        }
    }
    $adapterName = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "0.0.0.0" } | Select-Object -First 1 -ExpandProperty InterfaceAlias
    if ($adapterName) {
        $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Up') {
            Write-DNSLog "Found adapter via default gateway: $($adapter.Name)"
            return $adapter
        }
    }
    $adapter = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and
        $_.Virtual -ne $true -and
        $_.Name -notmatch "Loopback|Virtual|Bluetooth|VPN|TAP|vEthernet|tun|Tunnel|WireGuard|Nord|ZeroTier|Hamachi" -and
        $_.InterfaceDescription -notmatch "VPN|Virtual|TAP|Loopback|tun|Tunnel|WireGuard|Nord|ZeroTier|Hamachi"
    } | Select-Object -First 1
    if ($adapter) {
        Write-DNSLog "Found adapter via fallback: $($adapter.Name)"
        return $adapter
    }
    for ($w = 0; $w -lt 30; $w++) {
        Write-DNSLog "No active adapter – waiting for network (attempt $($w+1)/30)..." "warn"
        Start-Sleep -Seconds 10
        $a2 = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if ($a2) { return $a2 }
    }
    Write-DNSLog "No active adapter found – check network connection." "error"
    exit 1
}

$bestCache = $null
if(Test-Path $cacheFile){ $bestCache = Get-Content $cacheFile | ConvertFrom-Json }
$currentBest = $bestCache
$lastTest = (Get-Date).AddMinutes(-$interval)
$eventFlagFile = "C:\ShadowKit\network_changed.flag"

# Register CIM event subscription for network adapter status changes
# Unregister any existing event subscription to prevent leaks on restart
Get-EventSubscriber -SourceIdentifier "ShadowKitNetworkWatcher" -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue

try {
    Register-WmiEvent -Query "SELECT * FROM __InstanceModificationEvent WITHIN 5 WHERE TargetInstance ISA 'Win32_NetworkAdapter' AND TargetInstance.NetConnectionStatus != PreviousInstance.NetConnectionStatus" -Action {
        New-Item -ItemType File -Path "C:\ShadowKit\network_changed.flag" -Force | Out-Null
    } -SourceIdentifier "ShadowKitNetworkWatcher" | Out-Null
    Write-DNSLog "Network change event subscription registered"
} catch {
    Write-DNSLog "Failed to register network change event subscription: $_" "warn"
}

Write-DNSLog "DNS Frenzy started (intelligent mode, interval ${interval}min, event-driven enabled)"

while($true){
    # Check for event-driven network change
    if (Test-Path $eventFlagFile) {
        Remove-Item $eventFlagFile -Force -ErrorAction SilentlyContinue
        Write-DNSLog "Network change detected (event-driven), forcing immediate re-test"
        $lastTest = (Get-Date).AddMinutes(-$interval)
    }
    
    $now=Get-Date
    if(($now - $lastTest).TotalMinutes -ge $interval){
        Write-DNSLog "Testing servers..."
        $servers = Get-Servers
        $scored = @()
        if($servers.Count -eq 0){
            $bestPrimary = $fallbackDNS[0]
            $bestSecondary = $fallbackDNS[1]
            $bestName = "Fallback"
        } else {
            foreach($s in $servers){
                $r = Test-Latency -IP $s.primary
                if($r){
                    $score = $r.Latency + ($r.Loss * 5)
                    $scored += [PSCustomObject]@{
                        Name = $s.name
                        Primary = $s.primary
                        Secondary = $s.secondary
                        Score = $score
                        Latency = $r.Latency
                        Loss = $r.Loss
                    }
                } else {
                    Write-DNSLog "Server $($s.name) unreachable" "warn"
                }
            }
            if($scored.Count -eq 0){
                Write-DNSLog "All servers unreachable – using fallback." "error"
                $bestPrimary = $fallbackDNS[0]
                $bestSecondary = $fallbackDNS[1]
                $bestName = "Fallback"
            } else {
                $sorted = $scored | Sort-Object Score
                $best = $sorted[0]
                $bestName = $best.Name

                if($dnsMix -and $sorted.Count -gt 1){
                    $secondBest = $sorted[1]
                    $bestPrimary = $best.Primary
                    $bestSecondary = $secondBest.Secondary
                    Write-DNSLog "DNS mixing enabled: primary from $($best.Name), secondary from $($secondBest.Name)"
                } else {
                    $bestPrimary = $best.Primary
                    $bestSecondary = $best.Secondary
                    Write-DNSLog "Using best server: $($best.Name) (score $($best.Score))"
                }
            }
        }

        $cacheObj = @{ primary = $bestPrimary; secondary = $bestSecondary; name = $bestName }
        $cacheObj | ConvertTo-Json | Out-File $cacheFile -Force
        $currentBest = $cacheObj
        $lastTest = $now

        $adapter = Get-ActiveAdapter
        Write-DNSLog "Selected adapter: $($adapter.Name) (Index $($adapter.InterfaceIndex))"

        $retries = 3
        $delay = 2
        for ($i=0; $i -lt $retries; $i++) {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses @($bestPrimary, $bestSecondary) -ErrorAction Stop
                Write-DNSLog "DNS set to primary: $bestPrimary, secondary: $bestSecondary ($bestName)"
                if (-not $Silent) { Write-Host "DNS set to primary: $bestPrimary, secondary: $bestSecondary" -ForegroundColor Green }
                break
            } catch {
                if ($i -eq $retries - 1) {
                    Write-DNSLog "Failed to set DNS after $retries attempts: $_" "error"
                } else {
                    Write-DNSLog "Retry $($i+1) failed, waiting ${delay}s..." "warn"
                    Start-Sleep -Seconds $delay
                }
            }
        }
    } else {
        Write-DNSLog "Using cached best server: $($currentBest.name) ($($currentBest.primary))"
    }
    Start-Sleep -Seconds 60
}







