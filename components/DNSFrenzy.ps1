param([switch]$Silent, [switch]$Once)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

$serversFile = Join-Path $baseDir 'servers.json'
$configPath = Join-Path $baseDir 'config.json'
$cacheFile = Join-Path $baseDir 'state\best_dns_cache.json'

function Write-DnsLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File (Join-Path $baseDir 'logs\dns.log') -Append -Encoding UTF8 }

# Load config for mixing and update
$config = @{}
if (Test-Path $configPath) { $config = Get-Content $configPath -Raw | ConvertFrom-Json }

# Update server list if updateURL provided
if ($config.dns.updateURL) {
    try {
        $newList = Invoke-WebRequest -Uri $config.dns.updateURL -UseBasicParsing -TimeoutSec 10 | Select-Object -ExpandProperty Content | ConvertFrom-Json
        $newList | ConvertTo-Json -Depth 3 | Set-Content $serversFile -Encoding UTF8
        Write-DnsLog "Updated server list from $($config.dns.updateURL)"
    } catch { Write-DnsLog "Update failed: $_" warn }
}

$servers = @()
if (Test-Path $serversFile) { $servers = Get-Content $serversFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue }
if (-not $servers) {
    $servers = @(@{name='Cloudflare';primary='1.1.1.1';secondary='1.0.0.1'}, @{name='Google';primary='8.8.8.8';secondary='8.8.4.4'})
}

function Is-PrivateIP {
    param([string]$ip)
    return $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
}

$publicServers = @($servers | Where-Object { -not (Is-PrivateIP $_.primary) })
if ($publicServers.Count -eq 0) { $publicServers = @($servers) }

$results = @()
foreach ($s in $publicServers) {
    $ping = Test-Connection -ComputerName $s.primary -Count 2 -ErrorAction SilentlyContinue
    if ($ping) {
        $avg = ($ping | Measure-Object -Property ResponseTime -Average).Average
        $results += [pscustomobject]@{ Name=$s.name; Primary=$s.primary; Secondary=$s.secondary; Latency=$avg }
    }
}

if ($results.Count -eq 0) {
    if (Test-Path $cacheFile) {
        $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
        $best = [pscustomobject]@{ Name=$cached.name; Primary=$cached.primary; Secondary=$cached.secondary; Latency=9999 }
    } else {
        $best = [pscustomobject]@{ Name='Fallback'; Primary='1.1.1.1'; Secondary='1.0.0.1'; Latency=9999 }
    }
} else {
    $best = $results | Sort-Object Latency | Select-Object -First 1
}

# DNS mixing: if enabled, use two different providers
if ($config.dns.dnsMix -and $results.Count -ge 2) {
    $secondBest = $results | Where-Object { $_.Name -ne $best.Name } | Sort-Object Latency | Select-Object -First 1
    if ($secondBest) {
        $best.Secondary = $secondBest.Primary
        Write-DnsLog "DNS mixing enabled: primary $($best.Primary) from $($best.Name), secondary $($best.Secondary) from $($secondBest.Name)"
    }
}

$best | Select-Object Name, Primary, Secondary | ConvertTo-Json | Set-Content $cacheFile -Encoding UTF8

$adapter = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1
if ($adapter) {
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses @($best.Primary, $best.Secondary) -ErrorAction SilentlyContinue
}

Set-ShadowStatus -Component 'DNSFrenzy' -Status 'Running' -Data @{ primary=$best.Primary; secondary=$best.Secondary; name=$best.Name; latency=$best.Latency }
Write-DnsLog "DNS set to primary $($best.Primary) ($($best.Name)), secondary $($best.Secondary)"

if ($Once) { exit 0 }
while ($true) { Start-Sleep -Seconds 600 }
