param([switch]$Check, [switch]$Repair, [switch]$Force)
$ErrorActionPreference = "SilentlyContinue"
$logFile = "C:\ShadowKit\logs\watchdog_helper.log"
$SK = "C:\ShadowKit"

function Write-HelperLog {
    param($msg, $level = "info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$level] $msg"
    $entry | Out-File -Append $logFile
    if ($level -eq "error") { Write-Host $entry -ForegroundColor Red }
    else { Write-Host $entry -ForegroundColor Cyan }
}

function Test-ComponentRunning {
    param([string]$ScriptName)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -like "*$ScriptName*"
        }
        if ($null -ne $procs -and @($procs).Count -gt 0) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Test-PowerPlan {
    $plan = powercfg -getactivescheme
    if ($plan -match "381b4222-f694-41f0-9685-ff5bb260df2e" -or $plan -match "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") {
        return $true
    }
    return $false
}

function Test-MinecraftSettings {
    $opt = "$env:APPDATA\FreesmLauncher\instances\1.21.11\minecraft\options.txt"
    if (Test-Path $opt) {
        $content = Get-Content $opt -Raw
        $rd = if ($content -match 'renderDistance:(\d+)') { [int]$matches[1] }
        $fps = if ($content -match 'maxFps:(\d+)') { [int]$matches[1] }
        if ($rd -ge 6 -and $fps -ge 120) { return $true }
    }
    return $false
}

function Test-JvmG1GC {
    $cfg = "$env:APPDATA\FreesmLauncher\freesmlauncher.cfg"
    if (Test-Path $cfg) {
        $content = Get-Content $cfg -Raw
        if ($content -match 'JvmArgs=.*G1GC') { return $true }
    }
    return $false
}

function Test-GpuPerformance {
    $path = "HKCU:\Software\Microsoft\DirectX\GraphicsSettings"
    if (Test-Path $path) {
        $val = (Get-ItemProperty -Path $path -Name "Javaw.exe" -ErrorAction SilentlyContinue).'Javaw.exe'
        if ($val -eq 2) { return $true }
    }
    return $false
}

function Repair-PowerPlan {
    Write-HelperLog "Repairing power plan to Balanced..." "warn"
    powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e
}

function Repair-Component {
    param([string]$ScriptPath, [string]$Name)
    Write-HelperLog "Restarting $Name in background..." "warn"
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Silent" -WindowStyle Hidden
}

function Repair-MinecraftSettings {
    Write-HelperLog "Reapplying Minecraft balanced settings..." "warn"
    $mc = "$env:APPDATA\FreesmLauncher\instances\1.21.11\minecraft"
    $opt = "$mc\options.txt"
    (Get-Content $opt -Raw) -replace 'renderDistance:\d+', 'renderDistance:8' `
        -replace 'particles:\d+', 'particles:1' `
        -replace 'entityDistanceScaling:[\d.]+', 'entityDistanceScaling:0.75' `
        -replace 'maxFps:\d+', 'maxFps:120' | Out-File $opt -Encoding UTF8
}

function Repair-JvmG1GC {
    Write-HelperLog "Reapplying JVM G1GC args..." "warn"
    $cfg = "$env:APPDATA\FreesmLauncher\freesmlauncher.cfg"
    $jvm = '-XX:+UseG1GC -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=4M -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1ReservePercent=20 -XX:ParallelGCThreads=4 -XX:ConcGCThreads=2'
    $content = Get-Content $cfg -Raw
    if ($content -match 'JvmArgs=(.*)') {
        $content = $content -replace 'JvmArgs=[^\n]*', "JvmArgs=$jvm"
    } else {
        $content += "`nJvmArgs=$jvm"
    }
    $content | Out-File $cfg -Encoding UTF8 -Force
}

function Repair-GpuPerformance {
    Write-HelperLog "Reapplying GPU high performance for Java..." "warn"
    New-Item -Path "HKCU:\Software\Microsoft\DirectX\GraphicsSettings" -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\DirectX\GraphicsSettings" -Name "Javaw.exe" -Value 2 -Type DWord -Force
}

if ($Check) {
    Write-HelperLog "Running integrity checks..." "info"
    $allGood = $true

    if (-not (Test-PowerPlan)) { Write-HelperLog "FAIL: Power plan not Balanced or High Performance." "error"; $allGood = $false }
    if (-not (Test-ComponentRunning -ScriptName "TimerOptimizer.ps1")) { Write-HelperLog "FAIL: TimerOptimizer process not running." "error"; $allGood = $false }
    if (-not (Test-ComponentRunning -ScriptName "DNSFrenzy.ps1")) { Write-HelperLog "FAIL: DNSFrenzy process not running." "error"; $allGood = $false }
    if (-not (Test-ComponentRunning -ScriptName "MemoryCleaner.ps1")) { Write-HelperLog "FAIL: MemoryCleaner process not running." "error"; $allGood = $false }
    if (-not (Test-MinecraftSettings)) { Write-HelperLog "FAIL: Minecraft settings not optimized." "error"; $allGood = $false }
    if (-not (Test-JvmG1GC)) { Write-HelperLog "FAIL: JVM G1GC not configured." "error"; $allGood = $false }
    if (-not (Test-GpuPerformance)) { Write-HelperLog "FAIL: GPU high performance not set for Java." "error"; $allGood = $false }

    & "$SK\components\SystemCalibrator.ps1" -Audit -Silent
    if ($LASTEXITCODE -ne 0) { Write-HelperLog "FAIL: SystemCalibrator drift detected." "error"; $allGood = $false }

    if ($allGood) { Write-HelperLog "All checks passed." "info"; exit 0 } else { exit 1 }
}

if ($Repair -or $Force) {
    Write-HelperLog "Starting repair process..." "warn"
    if (-not (Test-PowerPlan)) { Repair-PowerPlan }
    if (-not (Test-ComponentRunning -ScriptName "TimerOptimizer.ps1")) { Repair-Component -ScriptPath "$SK\components\TimerOptimizer.ps1" -Name "TimerOptimizer" }
    if (-not (Test-ComponentRunning -ScriptName "DNSFrenzy.ps1")) { Repair-Component -ScriptPath "$SK\components\DNSFrenzy.ps1" -Name "DNSFrenzy" }
    if (-not (Test-ComponentRunning -ScriptName "MemoryCleaner.ps1")) { Repair-Component -ScriptPath "$SK\components\MemoryCleaner.ps1" -Name "MemoryCleaner" }
    if (-not (Test-MinecraftSettings)) { Repair-MinecraftSettings }
    if (-not (Test-JvmG1GC)) { Repair-JvmG1GC }
    if (-not (Test-GpuPerformance)) { Repair-GpuPerformance }
    & "$SK\components\SystemCalibrator.ps1" -Once -Silent
    schtasks /run /tn "ShadowKitCalibratorUser" 2>$null | Out-Null
    Write-HelperLog "Repair process completed." "info"
    exit 0
}

exit 0



