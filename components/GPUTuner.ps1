param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\gputuner.state.json'
$logFile = Join-Path $baseDir 'logs\gpu.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-GpuLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-GpuLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        $key = $_.PSPath
        if ($state.PowerMizerEnable -ne $null) { Set-ItemProperty -Path $key -Name 'PowerMizerEnable' -Value $state.PowerMizerEnable -Type DWord -Force -ErrorAction SilentlyContinue }
        if ($state.PerfLevelSrc -ne $null) { Set-ItemProperty -Path $key -Name 'PerfLevelSrc' -Value $state.PerfLevelSrc -Type DWord -Force -ErrorAction SilentlyContinue }
        if ($state.PowerMizerDefault -ne $null) { Set-ItemProperty -Path $key -Name 'PowerMizerDefault' -Value $state.PowerMizerDefault -Type DWord -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'GPUTuner' -Status 'Reverted'
    Write-GpuLog 'GPUTuner revert complete'
    exit 0
}

if ($Apply) {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if (-not $gpus) { Write-GpuLog 'No GPU found' warn; exit 1 }
    $nvidia = $gpus | Where-Object { $_.AdapterCompatibility -match 'NVIDIA' -or $_.Name -match 'NVIDIA' }
    if ($nvidia) {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        $state = @{}
        $key = (Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PSPath -Name 'DriverDesc' -ErrorAction SilentlyContinue).DriverDesc -match 'NVIDIA' } | Select-Object -First 1).PSPath
        if ($key) {
            $state.PowerMizerEnable = (Get-ItemProperty $key -Name 'PowerMizerEnable' -ErrorAction SilentlyContinue).PowerMizerEnable
            $state.PerfLevelSrc = (Get-ItemProperty $key -Name 'PerfLevelSrc' -ErrorAction SilentlyContinue).PerfLevelSrc
            $state.PowerMizerDefault = (Get-ItemProperty $key -Name 'PowerMizerDefault' -ErrorAction SilentlyContinue).PowerMizerDefault
            Set-ItemProperty -Path $key -Name 'PowerMizerEnable' -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $key -Name 'PerfLevelSrc' -Value 0x3322 -Type DWord -Force
            Set-ItemProperty -Path $key -Name 'PowerMizerDefault' -Value 0 -Type DWord -Force
            Write-GpuLog 'NVIDIA power management set to maximum performance'
        }
        $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
        Set-ShadowStatus -Component 'GPUTuner' -Status 'Applied'
        Write-GpuLog 'GPUTuner apply complete'
        exit 0
    } else {
        Write-GpuLog 'NVIDIA GPU not found. AMD/Intel GPU-specific registry tweaks are not applied by GPUTuner.' warn
        Set-ShadowStatus -Component 'GPUTuner' -Status 'Skipped'
        exit 0
    }
}
Write-Host "Usage: GPUTuner.ps1 -Apply   or   -Revert"
