<#
.SYNOPSIS
    Forces a remote update of the DNS server list.
.DESCRIPTION
    Reads the updateURL from config.json, fetches the JSON, validates it,
    and overwrites servers.json with the new list. Useful for scheduled
    refreshes or manual intervention.
#>

$configPath = "C:\\ShadowKit\config.json"
$serversFile = "C:\\ShadowKit\servers.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Config not found at $configPath" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath | ConvertFrom-Json
$updateURL = $config.dns.updateURL

if (-not $updateURL -or $updateURL -eq "") {
    Write-Host "No updateURL defined in config – nothing to do." -ForegroundColor Yellow
    exit 1
}

Write-Host "Fetching DNS list from $updateURL ..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri $updateURL -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $newList = $response.Content | ConvertFrom-Json

    # Validate the structure
    $valid = $true
    foreach ($entry in $newList) {
        if (-not ($entry.PSObject.Properties.Name -contains 'name' -and
                  $entry.PSObject.Properties.Name -contains 'primary' -and
                  $entry.PSObject.Properties.Name -contains 'secondary')) {
            $valid = $false
            break
        }
    }

    if ($valid) {
        $newList | ConvertTo-Json -Depth 3 | Out-File -FilePath $serversFile -Encoding UTF8
        Write-Host "Server list updated successfully." -ForegroundColor Green
    } else {
        Write-Host "Invalid format from URL – expected 'name', 'primary', 'secondary'." -ForegroundColor Red
    }
} catch {
    Write-Host "Update failed: $_" -ForegroundColor Red
}