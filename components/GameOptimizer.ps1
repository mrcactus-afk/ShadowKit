param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
$stateFile = Join-Path $baseDir 'state\gameoptimizer.state.json'
$logDir = Join-Path $baseDir 'logs'
New-Item -ItemType Directory -Path $logDir, (Split-Path $stateFile) -Force | Out-Null
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

function Write-GoLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File (Join-Path $logDir 'gameoptimizer.log') -Append -Encoding UTF8 }

if ($Revert) {
    Write-GoLog 'Starting GameOptimizer revert...' warn
    if (-not (Test-Path $stateFile)) { Write-GoLog 'No state file found, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    try {
        if ($state.PSObject.Properties.Name -contains 'memoryCompression' -and $state.memoryCompression -eq $true) {
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            Write-GoLog 'Re-enabled memory compression'
        }
    } catch { Write-GoLog "Memory compression revert failed: $_" error }
    try {
        if ($state.PSObject.Properties.Name -contains 'priorScheme' -and $state.priorScheme) {
            powercfg -setactive $state.priorScheme | Out-Null
            Write-GoLog "Restored power plan $($state.priorScheme)"
        }
    } catch { Write-GoLog "Power plan revert failed: $_" error }
    try {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $prior = $state.hags
        if ($null -eq $prior) {
            Remove-ItemProperty -Path $path -Name 'HwSchMode' -Force -ErrorAction SilentlyContinue
            Write-GoLog 'Removed HAGS registry key'
        } else {
            Set-ItemProperty -Path $path -Name 'HwSchMode' -Value $prior -Type DWord -Force
            Write-GoLog "Restored HAGS to $prior"
        }
    } catch { Write-GoLog "HAGS revert failed: $_" error }
    try {
        $regs = @(
            @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Prior = $state.gameDvrUser },
            @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'; Name = 'AllowGameDVR'; Prior = $state.gameDvrMachine }
        )
        foreach ($r in $regs) {
            if ($null -eq $r.Prior) {
                Remove-ItemProperty -Path $r.Path -Name $r.Name -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Prior -Type DWord -Force
            }
        }
        Write-GoLog 'Restored GameDVR registry keys'
    } catch { Write-GoLog "GameDVR revert failed: $_" error }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'GameOptimizer' -Status 'Reverted'
    Write-GoLog 'GameOptimizer revert complete'
    exit 0
}

if ($Apply) {
    Write-GoLog 'Starting GameOptimizer apply...'
    $state = @{}
    try {
        $mc = (Get-MMAgent -ErrorAction Stop).MemoryCompression
        $state.memoryCompression = [bool]$mc
        if ($mc) { Disable-MMAgent -MemoryCompression -ErrorAction Stop; Write-GoLog 'Memory compression disabled' }
    } catch { Write-GoLog "Memory compression step failed: $($_.Exception.Message)" warn }
    try {
        $prior = (powercfg -getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
        $state.priorScheme = $prior
        $dup = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
        if ($dup) {
            $newGuid = ($dup | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
            powercfg -setactive $newGuid | Out-Null
            Write-GoLog "Ultimate Performance activated ($newGuid)"
        } else {
            Write-GoLog 'Ultimate Performance duplicate failed, keeping active scheme' warn
        }
    } catch { Write-GoLog "Power plan step failed: $($_.Exception.Message)" warn }
    try {
        $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        $prior = (Get-ItemProperty -Path $path -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode
        $state.hags = $prior
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'HwSchMode' -Value 2 -Type DWord -Force
        Write-GoLog 'HAGS enabled (2). Warning: may cause driver instability on some systems'
    } catch { Write-GoLog "HAGS step failed: $($_.Exception.Message)" warn }
    try {
        $userPath = 'HKCU:\System\GameConfigStore'
        $machinePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
        $priorUser = (Get-ItemProperty -Path $userPath -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled
        $priorMachine = (Get-ItemProperty -Path $machinePath -Name 'AllowGameDVR' -ErrorAction SilentlyContinue).AllowGameDVR
        $state.gameDvrUser = $priorUser
        $state.gameDvrMachine = $priorMachine
        New-Item -Path $userPath -Force | Out-Null
        New-Item -Path $machinePath -Force | Out-Null
        Set-ItemProperty -Path $userPath -Name 'GameDVR_Enabled' -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $machinePath -Name 'AllowGameDVR' -Value 0 -Type DWord -Force
        Write-GoLog 'GameDVR disabled'
    } catch { Write-GoLog "GameDVR step failed: $($_.Exception.Message)" warn }
    $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'GameOptimizer' -Status 'Applied' -Data @{ RebootRequired = $true }
    Write-GoLog 'GameOptimizer applied. Reboot recommended.'
    exit 0
}
Write-Host "Usage: GameOptimizer.ps1 -Apply   or   -Revert"

