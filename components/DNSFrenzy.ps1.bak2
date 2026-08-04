param([switch]$Silent)
$configPath = "C:\\ShadowKit\config.json"
$serversFile = "C:\\ShadowKit\servers.json"
$logDir = "C:\\ShadowKit\logs"
$logFile = Join-Path $logDir "dns.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $configPath)) { Write-Error "Config missing"; exit 1 }
$config = Get-Content $configPath | ConvertFrom-Json
$dnsConfig = $config.dns
$fallbackDNS = $dnsConfig.fallbackDNS
$updateURL = $dnsConfig.updateURL

function Write-DNSLog {
    param($Message, $Level = "info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $entry | Out-File -Append $logFile
    if (-not $Silent) {
        if ($Level -eq "error") { Write-Host $entry -ForegroundColor Red }
        else { Write-Host $entry -ForegroundColor Cyan }
    }
}

# Load servers (local cache + optional remote update)
$servers = $null
if ($updateURL -and $updateURL -ne "") {
    try {
        $resp = Invoke-WebRequest -Uri $updateURL -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $new = $resp.Content | ConvertFrom-Json
        $valid = $true
        foreach ($s in $new) {
            if (-not ($s.PSObject.Properties.Name -contains 'name' -and
                      $s.PSObject.Properties.Name -contains 'primary' -and
                      $s.PSObject.Properties.Name -contains 'secondary')) {
                $valid = $false; break
            }
        }
        if ($valid) {
            $new | ConvertTo-Json -Depth 3 | Out-File -FilePath $serversFile -Encoding UTF8
            $servers = $new
            Write-DNSLog "Remote update succeeded."
        }
    } catch {
        Write-DNSLog "Remote update failed: $_" "error"
    }
}
if (-not $servers) {
    $servers = Get-Content $serversFile -ErrorAction SilentlyContinue | ConvertFrom-Json
    if ($servers) { Write-DNSLog "Loaded local cache ($($servers.Count) servers)." }
}

# Find best server
if (-not $servers -or $servers.Count -eq 0) {
    Write-DNSLog "No servers available, using fallback." "warn"
    $best = @{ name="Fallback"; primary=$fallbackDNS[0]; secondary=$fallbackDNS[1] }
} else {
    $best = $null; $bestScore = [float]::MaxValue
    foreach ($s in $servers) {
        $ping = Test-Connection -ComputerName $s.primary -Count 2 -Quiet -ErrorAction SilentlyContinue
        if ($ping) {
            $measure = Test-Connection -ComputerName $s.primary -Count 2 -ErrorAction SilentlyContinue
            $avg = ($measure | Measure-Object -Property ResponseTime -Average).Average
            $loss = ($measure | Where-Object { $_.StatusCode -ne 0 }).Count / 2 * 100
            $score = $avg + ($loss * 5)
            if ($score -lt $bestScore) {
                $bestScore = $score
                $best = $s
            }
        } else {
            Write-DNSLog "Server $($s.name) unreachable." "warn"
        }
    }
    if (-not $best) {
        Write-DNSLog "All unreachable, using fallback." "error"
        $best = @{ name="Fallback"; primary=$fallbackDNS[0]; secondary=$fallbackDNS[1] }
    }
}

# Apply DNS
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($adapter) {
    try {
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses @($best.primary, $best.secondary) -ErrorAction Stop
        Write-DNSLog "DNS switched to $($best.name) ($($best.primary))"
        if (-not $Silent) { Write-Host "DNS set to $($best.name)" -ForegroundColor Green }
    } catch {
        Write-DNSLog "Failed to set DNS: $_" "error"
    }
} else {
    Write-DNSLog "No active adapter." "error"
}