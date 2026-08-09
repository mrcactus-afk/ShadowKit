$script:ShadowStatusFile = "$PSScriptRoot\..\state\status.json"
function Get-ShadowMutex { [System.Threading.Mutex]::new($false, "Global\ShadowKitStatusMutex") }

function Set-ShadowStatus {
    param([string]$Component, [string]$Status, [hashtable]$Data = @{})
    $m = Get-ShadowMutex
    try {
        if ($m.WaitOne(3000)) {
            $parent = Split-Path $script:ShadowStatusFile
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $dict = if (Test-Path $script:ShadowStatusFile) { (Get-Content $script:ShadowStatusFile -Raw | ConvertFrom-Json -AsHashtable) } else { @{} }
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
    $dict = Get-Content $script:ShadowStatusFile -Raw | ConvertFrom-Json -AsHashtable
    if ($Component) { return $dict[$Component] } else { return $dict }
}
