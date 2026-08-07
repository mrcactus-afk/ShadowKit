# ============================================================
# ShadowIPC.ps1 - atomic cross-component status bus (zero deps)
# Writers: mutex-guarded read-modify-write + Move-Item -Force
# Readers: FileShare.ReadWrite -> zero lock exceptions
# ============================================================

$script:ShadowStatusFile = "C:\ShadowKit\state\status.json"

function Get-ShadowStatus {
    param([string]$Component)
    if (-not (Test-Path $script:ShadowStatusFile)) { return $null }
    try {
        $fs = [System.IO.FileStream]::new($script:ShadowStatusFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        $raw = $sr.ReadToEnd()
        $sr.Dispose(); $fs.Dispose()
        if (-not $raw) { return $null }
        $obj = $raw | ConvertFrom-Json
        if ($Component) { return $obj.$Component }
        return $obj
    } catch { return $null }
}

function Set-ShadowStatus {
    param(
        [Parameter(Mandatory)][string]$Component,
        [string]$Status = "Running",
        [hashtable]$Data = @{}
    )
    $dir = Split-Path $script:ShadowStatusFile -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $mtx = New-Object System.Threading.Mutex($false, "Global\ShadowKitStatusMutex")
    $owned = $false
    try { $owned = $mtx.WaitOne(3000) } catch { $owned = $false }
    try {
        $all = @{}
        if (Test-Path $script:ShadowStatusFile) {
            try {
                $existing = (Get-Content $script:ShadowStatusFile -Raw | ConvertFrom-Json)
                foreach ($p in $existing.PSObject.Properties) { $all[$p.Name] = $p.Value }
            } catch { $all = @{} }
        }
        $all[$Component] = [ordered]@{
            status  = $Status
            pid     = $PID
            updated = (Get-Date).ToString("o")
            data    = $Data
        }
        $json = $all | ConvertTo-Json -Depth 8
        $tmp  = "$($script:ShadowStatusFile).tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
        # Move-Item -Force is atomic enough for our mutex-guarded writer + FileShare.ReadWrite reader
        Move-Item -Path $tmp -Destination $script:ShadowStatusFile -Force
    }
    finally {
        if ($owned) { try { $mtx.ReleaseMutex() } catch {} }
        $mtx.Dispose()
    }
}

function Test-ShadowComponentAlive {
    param([Parameter(Mandatory)][string]$Component, [int]$MaxAgeMinutes = 10)
    $e = Get-ShadowStatus -Component $Component
    if (-not $e -or -not $e.updated) { return $false }
    try { $ts = [datetime]::Parse($e.updated, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $false }
    return ((Get-Date) - $ts).TotalMinutes -le $MaxAgeMinutes
}
