param(
    [switch]$Enforce,
    [switch]$Restore,
    [switch]$UserScope,
    [switch]$Audit,
    [switch]$Once,
    [switch]$Silent,
    [switch]$CreateRestorePoint
)

$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
$profilePath = Join-Path $baseDir 'config\profile.json'
$configPath = Join-Path $baseDir 'config.json'
$stateDir = Join-Path $baseDir 'state'
$stateFile = Join-Path $stateDir 'calibrator.state.json'
$logDir = Join-Path $baseDir 'logs'
New-Item -ItemType Directory -Path $stateDir, $logDir -Force | Out-Null

function Write-CalLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File (Join-Path $logDir 'calibrator.log') -Append -Encoding UTF8 }

Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

if (-not (Test-Path $profilePath)) { Write-CalLog "profile.json missing at $profilePath" error; exit 1 }
$profile = Get-Content $profilePath -Raw | ConvertFrom-Json
$config = @{}
if (Test-Path $configPath) { $config = Get-Content $configPath -Raw | ConvertFrom-Json }

$facts = @{
    ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    cores = [Environment]::ProcessorCount
    battery = (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) -ne $null
}

function Test-Condition {
    param($Condition)
    if (-not $Condition) { return $true }
    if ($Condition.minRamGB -and $facts.ramGB -lt $Condition.minRamGB) { return $false }
    if ($Condition.minCores -and $facts.cores -lt $Condition.minCores) { return $false }
    if ($Condition.onBattery -eq $true -and -not $facts.battery) { return $false }
    if ($Condition.onAC -eq $true -and $facts.battery) { return $false }
    return $true
}

function Save-PriorState {
    param([string]$Key, [object]$Value, [string]$Type)
    $state = @{}
    if (Test-Path $stateFile) {
        $raw = Get-Content $stateFile -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) { $state[$prop.Name] = $prop.Value }
    }
    $state[$Key] = @{
        prior = $Value
        type  = $Type
        ts    = (Get-Date).ToString('o')
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content $stateFile -Encoding UTF8
}

function Restore-PriorState {
    if (-not (Test-Path $stateFile)) { Write-CalLog "No state file to restore" warn; return }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($prop in $state.PSObject.Properties) {
        $key = $prop.Name
        $prior = $prop.Value.prior
        $type = $prop.Value.type
        Write-CalLog "Restoring $key = $prior (type $type)"
        try {
            if ($key -like 'REG:*') {
                $regPath = $key -replace '^REG:', ''
                $name = Split-Path $regPath -Leaf
                $path = Split-Path $regPath -Parent
                if ($null -eq $prior) {
                    Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue
                } else {
                    $regType = switch ($type) { 'DWord' { 'DWord' } 'String' { 'String' } default { 'DWord' } }
                    Set-ItemProperty -Path $path -Name $name -Value $prior -Type $regType -Force
                }
            }
            elseif ($key -like 'SERVICE:*') {
                $svcName = $key -replace '^SERVICE:', ''
                Set-Service -Name $svcName -StartupType $prior -ErrorAction SilentlyContinue
            }
            elseif ($key -like 'POWER:*') {
                powercfg -setactive $prior | Out-Null
            }
        } catch {
            Write-CalLog "Failed to restore $key : $_" error
        }
    }
    Remove-Item $stateFile -Force
}

function Apply-Entry {
    param($Entry)
    $allowRisky = [bool]$config.calibrator.allowRisky
    if ($Entry.severity -eq 'risky' -and -not $allowRisky) { return }
    if (-not (Test-Condition $Entry.condition)) { return }

    switch ($Entry.type) {
        'service' {
            $svc = Get-Service -Name $Entry.target -ErrorAction SilentlyContinue
            if ($svc) {
                $current = $svc.StartType
                if ($current -ne $Entry.value) {
                    Save-PriorState -Key "SERVICE:$($Entry.target)" -Value $current -Type 'Service'
                    Set-Service -Name $Entry.target -StartupType $Entry.value
                    Write-CalLog "Set service $($Entry.target) from $current to $($Entry.value)"
                }
            }
        }
        'registry' {
            $regPath = $Entry.target
            $name = $Entry.name
            $desired = $Entry.value
            $kind = $Entry.kind
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            $current = (Get-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue).$name
            if ($current -ne $desired) {
                Save-PriorState -Key "REG:$regPath\$name" -Value $current -Type $kind
                Set-ItemProperty -Path $regPath -Name $name -Value $desired -Type $kind -Force
                Write-CalLog "Set registry $regPath\$name from $current to $desired"
            }
        }
        'power' {
            $current = (powercfg -getactivescheme | Select-String -Pattern '([0-9a-f-]{36})').Matches[0].Groups[1].Value
            if ($current -ne $Entry.value) {
                Save-PriorState -Key "POWER:active" -Value $current -Type 'Power'
                powercfg -setactive $Entry.value | Out-Null
                Write-CalLog "Set power plan from $current to $($Entry.value)"
            }
        }
    }
}

function Audit-Entries {
    $issues = @()
    foreach ($entry in $profile.entries) {
        if (-not (Test-Condition $entry.condition)) { continue }
        switch ($entry.type) {
            'service' {
                $svc = Get-Service -Name $entry.target -ErrorAction SilentlyContinue
                if ($svc -and $svc.StartType -ne $entry.value) {
                    $issues += "Service $($entry.target) is $($svc.StartType), expected $($entry.value)"
                }
            }
            'registry' {
                $current = (Get-ItemProperty -Path $entry.target -Name $entry.name -ErrorAction SilentlyContinue).$entry.name
                if ($current -ne $entry.value) {
                    $issues += "Registry $($entry.target)\$($entry.name) is $current, expected $($entry.value)"
                }
            }
            'power' {
                $current = (powercfg -getactivescheme | Select-String -Pattern '([0-9a-f-]{36})').Matches[0].Groups[1].Value
                if ($current -ne $entry.value) {
                    $issues += "Power plan is $current, expected $($entry.value)"
                }
            }
        }
    }
    return $issues
}

if ($Restore) {
    Restore-PriorState
    Set-ShadowStatus -Component 'SystemCalibrator' -Status 'Restored'
    Write-CalLog 'Restore completed'
    exit 0
}

if ($UserScope) {
    Restore-PriorState
    Set-ShadowStatus -Component 'SystemCalibrator' -Status 'Restored (UserScope)'
    exit 0
}

if ($Audit) {
    $issues = Audit-Entries
    if ($issues.Count -gt 0) {
        Write-CalLog "Audit found $($issues.Count) issues" warn
        $issues | ForEach-Object { Write-CalLog $_ warn }
        exit 1
    }
    Write-CalLog 'Audit clean'
    exit 0
}

if ($Enforce -or $Once) {
    if ($CreateRestorePoint) {
        try {
            Checkpoint-Computer -Description 'ShadowKit Pre-Enforce Restore Point' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-CalLog 'Restore point created'
        } catch { Write-CalLog "Restore point creation failed: $_" warn }
    }
    foreach ($entry in $profile.entries) {
        try { Apply-Entry -Entry $entry } catch { Write-CalLog "Failed to apply entry: $_" error }
    }
    Set-ShadowStatus -Component 'SystemCalibrator' -Status 'Enforced'
    Write-CalLog 'Enforcement completed'
    exit 0
}

Set-ShadowStatus -Component 'SystemCalibrator' -Status 'Running'
while ($true) {
    foreach ($entry in $profile.entries) {
        try { Apply-Entry -Entry $entry } catch { Write-CalLog "Failed to apply entry: $_" error }
    }
    Set-ShadowStatus -Component 'SystemCalibrator' -Status 'Running' -Data @{ lastRun = (Get-Date).ToString('o') }
    Start-Sleep -Seconds 1800
}
