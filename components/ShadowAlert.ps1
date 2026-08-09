# ShadowKit ErrorAlert Module v4.2
$script:AlertFile = "C:\ShadowKit\state\alerts.json"

function Publish-ShadowAlert {
    param(
        [Parameter(Mandatory)][ValidateSet("info","warn","error")][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = "System",
        [int]$MaxAlerts = 50
    )
    $alert = [ordered]@{
        id = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
        ts = (Get-Date).ToString("o")
        level = $Level
        component = $Component
        message = $Message
        acknowledged = $false
    }
    $alerts = @()
    if (Test-Path $script:AlertFile) {
        try { $alerts = Get-Content $script:AlertFile -Raw | ConvertFrom-Json } catch { $alerts = @() }
        if ($alerts -isnot [array]) { $alerts = @($alerts) }
    }
    $alerts += $alert
    if ($alerts.Count -gt $MaxAlerts) { $alerts = $alerts | Select-Object -Last $MaxAlerts }
    $alerts | ConvertTo-Json -Depth 3 | Set-Content $script:AlertFile -Encoding UTF8
}

function Get-ShadowAlerts {
    param([switch]$UnacknowledgedOnly, [int]$Limit = 20)
    if (-not (Test-Path $script:AlertFile)) { return @() }
    $alerts = @()
    try { $alerts = Get-Content $script:AlertFile -Raw | ConvertFrom-Json } catch { return @() }
    if ($alerts -isnot [array]) { $alerts = @($alerts) }
    if ($UnacknowledgedOnly) { $alerts = $alerts | Where-Object { -not $_.acknowledged } }
    return $alerts | Select-Object -Last $Limit
}

function Clear-ShadowAlert {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path $script:AlertFile)) { return }
    $alerts = @()
    try { $alerts = Get-Content $script:AlertFile -Raw | ConvertFrom-Json } catch { return }
    if ($alerts -isnot [array]) { $alerts = @($alerts) }
    $alerts = $alerts | Where-Object { $_.id -ne $Id }
    $alerts | ConvertTo-Json -Depth 3 | Set-Content $script:AlertFile -Encoding UTF8
}

function Acknowledge-ShadowAlert {
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path $script:AlertFile)) { return }
    $alerts = @()
    try { $alerts = Get-Content $script:AlertFile -Raw | ConvertFrom-Json } catch { return }
    if ($alerts -isnot [array]) { $alerts = @($alerts) }
    foreach ($a in $alerts) { if ($a.id -eq $Id) { $a.acknowledged = $true } }
    $alerts | ConvertTo-Json -Depth 3 | Set-Content $script:AlertFile -Encoding UTF8
}
