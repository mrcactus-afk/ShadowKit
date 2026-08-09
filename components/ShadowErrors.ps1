# ShadowErrors.ps1 v4.2
. "C:\ShadowKit\components\ShadowAlert.ps1"

function Parse-LogLine {
    param([string]$Line)
    $Line = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    if ($Line.StartsWith("{")) {
        try {
            $j = $Line | ConvertFrom-Json
            return [pscustomobject]@{
                ts = [datetime]::Parse($j.ts)
                level = ($j.level).ToLower()
                module = $j.module
                msg = $j.msg
                data = $j.data
                format = "jsonl"
            }
        } catch { return $null }
    }
    if ($Line -match '^\[(?<ts>[^\]]+)\]\s*\[(?<level>[^\]]+)\]\s*(?<msg>.*)$') {
        $ts = [datetime]::MinValue
        if ([datetime]::TryParse($Matches['ts'], [ref]$ts)) {
            return [pscustomobject]@{
                ts = $ts
                level = ($Matches['level']).ToLower()
                module = "legacy"
                msg = $Matches['msg']
                data = $null
                format = "text"
            }
        }
    }
    return $null
}

function Scan-ShadowKitErrors {
    param(
        [string]$LogDir = "C:\ShadowKit\logs",
        [int]$RecencyMinutes = 60,
        [int]$FutureGraceMinutes = 5,
        [switch]$PublishAlerts
    )
    $now = Get-Date
    $cutoff = $now.AddMinutes(-$RecencyMinutes)
    $futureLimit = $now.AddMinutes($FutureGraceMinutes)
    $errors = New-Object System.Collections.Generic.List[object]
    $files = @(Get-ChildItem $LogDir -Filter "*.log" -ErrorAction SilentlyContinue)
    $files += @(Get-ChildItem $LogDir -Filter "*.jsonl" -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $lines = @(Get-Content $f.FullName -Tail 300 -ErrorAction SilentlyContinue)
        foreach ($line in $lines) {
            $e = Parse-LogLine $line
            if ($null -eq $e) { continue }
            if ($e.level -ne "error") { continue }
            if ($e.ts -lt $cutoff) { continue }
            if ($e.ts -gt $futureLimit) { continue }
            $e | Add-Member -NotePropertyName "source" -NotePropertyValue $f.Name -Force
            $errors.Add($e)
            if ($PublishAlerts) { Publish-ShadowAlert -Level error -Message $e.msg -Component $e.module }
        }
    }
    return ($errors | Sort-Object ts)
}
