param([switch]$Force)

Add-Type -AssemblyName System.Windows.Forms

$logDir = "C:\ShadowKit\logs"
$popupLog = Join-Path $logDir "popup.log"
$lastCheckFile = "$env:TEMP\ShadowKit_LastCheck.txt"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-PopupLog {
    param($Message, $Level = "info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$ts] [$Level] $Message" | Out-File -Append $popupLog
}

try {
    $lastRun = [datetime]::MinValue

    if (-not $Force -and (Test-Path $lastCheckFile)) {
        $raw = Get-Content $lastCheckFile -TotalCount 1 -ErrorAction SilentlyContinue
        if ($raw) {
            $raw = $raw.Trim()
            [datetime]::TryParse($raw, [ref]$lastRun) | Out-Null
        }
    }

    if ($lastRun -eq [datetime]::MinValue) { $lastRun = (Get-Date).AddHours(-1) }

    function Parse-LogLine {
        param([string]$Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
        $Line = $Line.Trim()

        if ($Line.StartsWith("{")) {
            try {
                $j = $Line | ConvertFrom-Json
                if ($j.level -eq "error" -or $j.level -eq "warn") {
                    return [PSCustomObject]@{ Time = [datetime]::Parse($j.ts); Level = $j.level; Message = $j.msg }
                }
            } catch {}
            return $null
        }

        if ($Line -match '^\[(?<ts>[^\]]+)\]\s*\[(?<level>error|warn)\]\s*(?<msg>.*)$') {
            $ts = [datetime]::MinValue
            if ([datetime]::TryParse($Matches['ts'], [ref]$ts)) {
                return [PSCustomObject]@{ Time = $ts; Level = $Matches['level']; Message = $Matches['msg'] }
            }
        }
        return $null
    }

    function Get-LatestStatus {
        param([string]$LogFile, [string]$Pattern, [string]$Default = "No data")
        if (-not (Test-Path $LogFile)) { return $Default }
        $lines = @(Get-Content $LogFile -Tail 20 -ErrorAction SilentlyContinue)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $parsed = Parse-LogLine ($lines[$i])
            if ($parsed -and $parsed.Message -match $Pattern) { return $parsed.Message }
        }
        return $Default
    }

    $dnsStatus = Get-LatestStatus -LogFile "$logDir\dns.log" -Pattern "DNS set to|DNS unchanged" -Default "Not set"
    $timerStatus = Get-LatestStatus -LogFile "$logDir\timer.log" -Pattern "Timer resolution set to" -Default "Not set"
    $watchdogStatus = Get-LatestStatus -LogFile "$logDir\watchdog.log" -Pattern "Integrity|Watchdog started" -Default "No check"

    $errors = New-Object System.Collections.Generic.List[string]
    $now = Get-Date

    $logFiles = @(Get-ChildItem $logDir -Filter "*.log" -File -ErrorAction SilentlyContinue)
    $logFiles += @(Get-ChildItem $logDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)

    $logFiles |
    Where-Object { $_.Name -ne "popup.log" } |
    ForEach-Object {
        $logName = $_.Name
        $lines = @(Get-Content $_.FullName -Tail 100 -ErrorAction SilentlyContinue)
        foreach ($line in $lines) {
            $parsed = Parse-LogLine $line
            if ($parsed -and $parsed.Level -eq "error") {
                if ($Force -or ($parsed.Time -gt $lastRun -and $parsed.Time -le $now.AddMinutes(5))) {
                    $shortMsg = $parsed.Message
                    if ($shortMsg.Length -gt 60) { $shortMsg = $shortMsg.Substring(0, 60) + "..." }
                    $errors.Add("[$logName] $shortMsg")
                }
            }
        }
    }

    if (-not $Force) { (Get-Date).ToString("o") | Out-File -FilePath $lastCheckFile -Force }

    if ($Force -or $errors.Count -gt 0) {
        if ($Force -and $errors.Count -eq 0) { $errors.Add("Forced popup test. No recent errors.") }

        $msg = "ShadowKit Status – $(Get-Date -Format 'HH:mm:ss')`n`n"
        $msg += "DNS: $dnsStatus`n"
        $msg += "Timer: $timerStatus`n"
        $msg += "Watchdog: $watchdogStatus`n"
        $msg += "`n=== Recent Errors ($($errors.Count)) ===`n"

        $displayErrors = $errors | Select-Object -Last 5
        $msg += ($displayErrors -join "`n")

        if ($errors.Count -gt 5) { $msg += "`n... and $($errors.Count - 5) more." }

        [void][System.Windows.Forms.MessageBox]::Show($msg, "ShadowKit Alert", "OK", "Warning")
        Write-PopupLog "Popup displayed: $($errors.Count) error(s)."
    } else {
        Write-PopupLog "No recent errors; popup skipped."
    }
} catch {
    Write-PopupLog "ErrorPopup failed: $_" "error"
    try { [void][System.Windows.Forms.MessageBox]::Show("ErrorPopup failed:`n$_", "ShadowKit Error", "OK", "Error") } catch {}
    exit 1
}

