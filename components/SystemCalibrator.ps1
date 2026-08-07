param([switch]$Silent, [switch]$Audit, [switch]$Restore, [switch]$UserScope, [switch]$Once)
. "C:\ShadowKit\components\ShadowIPC.ps1"
$configPath = "C:\ShadowKit\config.json"
$profilePath = "C:\ShadowKit\profile.json"
$baselinePath = "C:\ShadowKit\baseline.json"
if ($UserScope) { $baselinePath = "C:\ShadowKit\baseline_user.json" }
$logDir = "C:\ShadowKit\logs"
$logFile = Join-Path $logDir "calibrator.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-CalLog {
    param($Message, $Level = "info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $entry | Out-File -Append $logFile
    if (-not $Silent) {
        if ($Level -eq "error") { Write-Host $entry -ForegroundColor Red }
        else { Write-Host $entry -ForegroundColor Cyan }
    }
}

if (-not (Test-Path $configPath)) { Write-CalLog "Config missing" "error"; exit 1 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$cal = $config.calibrator
if (-not $cal) { Write-CalLog "No calibrator section in config. Exiting." "warn"; exit 0 }
if (-not $cal.enabled -and -not $Audit -and -not $Restore) { Write-CalLog "Calibrator disabled. Exiting." "warn"; exit 0 }
if (-not (Test-Path $profilePath)) { Write-CalLog "profile.json missing. Exiting." "error"; exit 1 }

$profile = Get-Content $profilePath -Raw | ConvertFrom-Json
$entries = @($profile.entries)

$cs = Get-CimInstance Win32_ComputerSystem
$facts = @{
    ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 0)
    cores = $cs.NumberOfLogicalProcessors
    battery = (@(Get-CimInstance Win32_Battery).Count -gt 0)
}

function Test-Condition {
    param($cond)
    if (-not $cond) { return $true }
    if ($cond.minRamGB -and $facts.ramGB -lt $cond.minRamGB) { return $false }
    if ($cond.minCores -and $facts.cores -lt $cond.minCores) { return $false }
    if ($cond.requiresBattery -and -not $facts.battery) { return $false }
    if ($cond.requiresNoBattery -and $facts.battery) { return $false }
    if ($cond.requiresAppData -and -not (Test-Path (Join-Path $env:APPDATA $cond.requiresAppData))) { return $false }
    return $true
}

function Entry-Allowed {
    param($e)
    if ($e.severity -eq "universal") { return $true }
    if ($e.severity -eq "conditional") { return (Test-Condition $e.condition) }
    if ($e.severity -eq "risky") { return ($cal.allowRisky -eq $true -and (Test-Condition $e.condition)) }
    return $false
}

function Get-Current {
    param($e)
    switch ($e.type) {
        "service" { $s = Get-Service -Name $e.target -EA SilentlyContinue; if ($s) { return [string]$s.StartType } else { return "MISSING" } }
        "registry" {
            $regPath = ($e.target -replace ":", "")
            $q = @(reg query $regPath /v $e.name 2>$null)
            if ($LASTEXITCODE -ne 0) { return "ABSENT" }
            $line = $q | Where-Object { $_ -match "REG_" } | Select-Object -First 1
            if (-not $line) { return "ABSENT" }
            $val = ($line -split "REG_\w+\s+")[1].Trim()
            if ($e.kind -eq "DWord") { return [string]([Convert]::ToInt32(($val -replace '^0x',''), 16)) }
            return $val
        }
        "power" { $p = powercfg -getactivescheme; if ($p -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { return $matches[1] } else { return "UNKNOWN" } }
    }
    return "UNKNOWN"
}

function Set-Entry {
    param($e)
    switch ($e.type) {
        "service" {
            $map = @{ "Disabled" = "disabled"; "Manual" = "demand"; "Automatic" = "auto" }
            sc.exe config $e.target start= $map[[string]$e.value] | Out-Null
            if ([string]$e.value -eq "Disabled") { Stop-Service -Name $e.target -Force -EA SilentlyContinue }
        }
        "registry" {
            $regPath = ($e.target -replace ":", "")
            $t = "REG_DWORD"
            if ($e.kind -eq "String") { $t = "REG_SZ" }
            $out = reg add "$regPath" /v "$($e.name)" /t $t /d "$($e.value)" /f 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-CalLog ("reg add failed: " + ($out -join " ")) "warn"
                if (-not (Test-Path $e.target)) { New-Item -Path $e.target -Force -EA SilentlyContinue | Out-Null }
                New-ItemProperty -Path $e.target -Name $e.name -Value $e.value -PropertyType $e.kind -Force -EA SilentlyContinue | Out-Null
            }
        }
        "power" { powercfg -setactive $e.value | Out-Null }
    }
}

$active = @($entries | Where-Object { Entry-Allowed $_ })

if ($UserScope) {
    $active = @($active | Where-Object { $_.type -eq "registry" -and $_.target -like "HKCU:*" })
} else {
    $active = @($active | Where-Object { -not ($_.type -eq "registry" -and $_.target -like "HKCU:*") })
}

if ($Restore) {
    if (-not (Test-Path $baselinePath)) { Write-CalLog "No baseline to restore." "warn"; exit 0 }
    $base = @(Get-Content $baselinePath -Raw | ConvertFrom-Json)
    foreach ($b in $base) {
        Set-Entry @{ type = $b.type; target = $b.target; name = $b.name; kind = $b.kind; value = $b.value }
        Write-CalLog ("Restored " + $b.type + " " + $b.target + " -> " + $b.value)
    }
    Remove-Item $baselinePath -Force -EA SilentlyContinue
    Write-CalLog "Baseline restored and removed."
    exit 0
}

if (-not $UserScope -and -not $Audit -and -not $Once -and -not (Test-Path "C:\ShadowKit\restorepoint.json")) {
    try {
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "SystemRestorePointCreationFrequency" -Value 0 -PropertyType DWord -Force -EA SilentlyContinue | Out-Null
        Enable-ComputerRestore -Drive $env:SystemDrive -EA SilentlyContinue
        sc.exe config SR start= demand | Out-Null
        sc.exe config VSS start= demand | Out-Null
        $sr = [wmiclass]"root\default:SystemRestore"
        Start-Service VSS -EA SilentlyContinue
        $res = $sr.CreateRestorePoint("ShadowKit Pre-Calibration", 0, 100)
        Write-CalLog ("CreateRestorePoint returnValue: " + $res.returnValue)
        Start-Sleep -Seconds 5
        $rp = Get-CimInstance -Namespace "root\default" -ClassName "SystemRestore" -EA SilentlyContinue | Sort-Object sequencenumber -Descending | Select-Object -First 1
        if ($rp -and $rp.Description -like "ShadowKit*") {
            [PSCustomObject]@{ seq = $rp.sequencenumber; description = $rp.Description; created = (Get-Date).ToString("o") } | ConvertTo-Json | Set-Content "C:\ShadowKit\restorepoint.json" -Encoding UTF8
            Write-CalLog ("Restore point created and verified (seq " + $rp.sequencenumber + ").")
        } else {
            Write-CalLog "System Restore stack absent or not persisting; baseline restore remains the revert path." "warn"
            [PSCustomObject]@{ seq = $null; description = "ShadowKit Pre-Calibration"; created = (Get-Date).ToString("o"); reason = "SR stack absent" } | ConvertTo-Json | Set-Content "C:\ShadowKit\restorepoint.json" -Encoding UTF8
        }
    } catch {
        Write-CalLog ("Restore point creation failed: " + $_) "error"
    }
}

if (-not (Test-Path $baselinePath)) {
    $base = @()
    foreach ($e in $active) {
        $base += [PSCustomObject]@{ type = $e.type; target = $e.target; name = $e.name; kind = $e.kind; value = (Get-Current $e) }
    }
    $base | ConvertTo-Json -Depth 4 | Set-Content $baselinePath -Encoding UTF8
    Write-CalLog ("Baseline captured (" + $base.Count + " entries).")
}

function Run-Pass {
    $drift = 0
    foreach ($e in $active) {
        $cur = Get-Current $e
        $desired = [string]$e.value
        if ($cur -ne $desired) {
            $drift++
            if ($Audit) {
                if (-not $Silent) { Write-Host ("DRIFT " + $e.type + " " + $e.target + " current=" + $cur + " desired=" + $desired) }
            } else {
                Set-Entry $e
                Write-CalLog ("Applied " + $e.type + " " + $e.target + " -> " + $desired + " (was " + $cur + ")")
            }
        }
    }
    return $drift
}

if ($Audit) {
    $d = Run-Pass
    if (-not $Silent) { Write-Host ("Drift count: " + $d) }
    if ($d -gt 0) { exit 1 } else { exit 0 }
}

if ($UserScope -or $Once) {
    $d = Run-Pass
    Write-CalLog ("One-shot pass complete. Entries applied: " + $d)
    exit 0
}

Write-CalLog ("SystemCalibrator started (interval " + $cal.intervalMinutes + " min). Active entries: " + $active.Count)
Set-ShadowStatus -Component "SystemCalibrator" -Status "Running" -Data @{ Entries = $active.Count }
while ($true) {
    $d = Run-Pass
    if ($d -gt 0) { Write-CalLog ("Drift pass: " + $d + " entries re-applied.") "warn" }
Set-ShadowStatus -Component "SystemCalibrator" -Status "Enforcing" -Data @{ LastDrift = $d; Time = (Get-Date).ToString("o") }
    Start-Sleep -Seconds ($cal.intervalMinutes * 60)
}






