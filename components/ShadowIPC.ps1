$script:ShadowStatusFile = "$PSScriptRoot\..\state\status.json"
function Get-ShadowMutex { [System.Threading.Mutex]::new($false, "Global\ShadowKitStatusMutex") }

function Set-ShadowStatus {
    param([string]$Component, [string]$Status, [hashtable]$Data = @{})
    $m = Get-ShadowMutex
    try {
        if ($m.WaitOne(3000)) {
            $parent = Split-Path $script:ShadowStatusFile
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $dict = @{}
            if (Test-Path $script:ShadowStatusFile) {
                $raw = Get-Content $script:ShadowStatusFile -Raw
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $jsonObj = $raw | ConvertFrom-Json
                    if ($jsonObj) {
                        foreach ($prop in $jsonObj.psobject.properties) { $dict[$prop.Name] = $prop.Value }
                    }
                }
            }
            $dict[$Component] = @{ status = $Status; pid = $PID; updated = (Get-Date -Format "o"); data = $Data }
            $tmp = "$script:ShadowStatusFile.tmp"
            $dict | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $script:ShadowStatusFile -Force
        }
    } finally { $m.ReleaseMutex(); $m.Dispose() }
}

function Get-ShadowStatus {
    param([string]$Component)
    if (-not (Test-Path $script:ShadowStatusFile)) { return $null }
    $raw = Get-Content $script:ShadowStatusFile -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $jsonObj = $raw | ConvertFrom-Json
    if (-not $jsonObj) { return $null }
    if ($Component) { return $jsonObj.$Component } else { return $jsonObj }
}


