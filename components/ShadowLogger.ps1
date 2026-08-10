# ShadowLogger.psm1 – Module-based logger
# Exports Write-ShadowKitLog and Read-ShadowKitLog

$script:LogDir = 'C:\ShadowKit\logs'
$script:LogFile = Join-Path $script:LogDir 'shadowkit.jsonl'

function Write-ShadowKitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('debug','info','warn','error')][string]$Level = 'info',
        [string]$Module = 'System',
        [hashtable]$Data = @{}
    )
    try {
        if (-not (Test-Path $script:LogDir)) {
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
        }
        $entry = [ordered]@{
            ts = (Get-Date).ToString('o')
            level = $Level.ToLower()
            module = $Module
            msg = $Message
        }
        if ($Data.Count -gt 0) { $entry['data'] = $Data }
        $line = $entry | ConvertTo-Json -Compress -Depth 6
        # Rotate if >5MB
        $fi = Get-Item $script:LogFile -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 5MB) {
            $backup = "$($script:LogFile).old"
            Move-Item $script:LogFile $backup -Force -ErrorAction SilentlyContinue
        }
        [System.IO.File]::AppendAllText($script:LogFile, $line + "`n", (New-Object System.Text.UTF8Encoding $true))
    } catch {
        # Fallback to a text file
        $fallback = Join-Path $script:LogDir 'logger_fallback.log'
        "$(Get-Date -Format 'o') [$Level] [$Module] $Message" | Out-File -Append $fallback -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

function Read-ShadowKitLog {
    [CmdletBinding()]
    param(
        [int]$Tail = 200,
        [string]$Level = '',
        [string]$Module = '',
        [switch]$ErrorsOnly
    )
    if (-not (Test-Path $script:LogFile)) { return @() }
    $lines = Get-Content $script:LogFile -Tail $Tail -ErrorAction SilentlyContinue
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($raw in $lines) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try { $o = $raw | ConvertFrom-Json } catch { continue }
        if ($ErrorsOnly -and $o.level -ne 'error') { continue }
        if ($Level -and $o.level -ne $Level.ToLower()) { continue }
        if ($Module -and $o.module -ne $Module) { continue }
        $out.Add($o)
    }
    return $out
}

Export-ModuleMember -Function Write-ShadowKitLog, Read-ShadowKitLog