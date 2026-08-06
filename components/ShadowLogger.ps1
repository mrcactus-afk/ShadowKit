# ShadowLogger.ps1 - JSONL structured logging foundation for ShadowKit
# Usage in any component:
#   . "$PSScriptRoot\ShadowLogger.ps1"
#   Write-ShadowKitLog -Message "Standby purged" -Level info -Module MemoryCleaner -Data @{ freedMB = 1234 }

$script:ShadowKitLogDir  = "C:\ShadowKit\logs"
$script:ShadowKitLogFile = Join-Path $script:ShadowKitLogDir "shadowkit.jsonl"

function Write-ShadowKitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet("debug","info","warn","error")][string]$Level = "info",
        [string]$Module = "System",
        [hashtable]$Data = @{}
    )

    $entry = [ordered]@{
        ts     = (Get-Date).ToString("o")
        level  = $Level.ToLower()
        module = $Module
        msg    = $Message
    }
    if ($Data -and $Data.Count -gt 0) { $entry["data"] = $Data }

    try {
        $line = $entry | ConvertTo-Json -Compress -Depth 6
        if (-not (Test-Path $script:ShadowKitLogDir)) {
            New-Item -ItemType Directory -Path $script:ShadowKitLogDir -Force | Out-Null
        }
        $fi = Get-Item $script:ShadowKitLogFile -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 5MB) { Move-Item $script:ShadowKitLogFile "$script:ShadowKitLogFile.old" -Force -ErrorAction SilentlyContinue }
        for ($a = 0; $a -lt 3; $a++) {
            try { [System.IO.File]::AppendAllText($script:ShadowKitLogFile, $line + "`n", (New-Object System.Text.UTF8Encoding $true)); break }
            catch { Start-Sleep -Milliseconds 50 }
        }
    } catch {
        # Logging must never break the caller. Fail silently.
    }
}

function Read-ShadowKitLog {
    [CmdletBinding()]
    param(
        [int]$Tail = 200,
        [string]$Level = "",
        [string]$Module = "",
        [switch]$ErrorsOnly
    )

    if (-not (Test-Path $script:ShadowKitLogFile)) { return @() }

    $lines = @(Get-Content -LiteralPath $script:ShadowKitLogFile -Tail $Tail)
    $out = New-Object System.Collections.Generic.List[object]

    foreach ($raw in $lines) {
        $raw = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try { $o = $raw | ConvertFrom-Json } catch { continue }

        if ($ErrorsOnly -and $o.level -ne "error") { continue }
        if ($Level -and $o.level -ne $Level.ToLower()) { continue }
        if ($Module -and $o.module -ne $Module) { continue }
        $out.Add($o)
    }
    return $out
}


