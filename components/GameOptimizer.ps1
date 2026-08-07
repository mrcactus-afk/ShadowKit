#Requires -RunAsAdministrator
param([switch]$Revert, [switch]$Silent)
. "C:\ShadowKit\components\ShadowLogger.ps1"
. "C:\ShadowKit\components\ShadowIPC.ps1"

$stateDir  = "C:\ShadowKit\state"
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$stateFile = Join-Path $stateDir "gameoptimizer.state.json"
$ULT_GUID  = "e9a42b02-d5df-448d-aa00-03f14749eb61"

function Log([string]$m, [string]$l = "info") { Write-ShadowKitLog -Message $m -Level $l -Module "GameOptimizer" }
function Get-Guid([string]$s) { if ($s -match '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}') { return $Matches[0] } ; return $null }

$state = @{}
if (Test-Path $stateFile) { $state = (Get-Content $stateFile -Raw | ConvertFrom-Json) }
function Save-State { $script:state | ConvertTo-Json -Depth 6 | Set-Content $stateFile -Force }

# ============ REGISTRY ACTION TABLE ============
$regActions = @(
    @{ P = "HKCU\System\GameConfigStore";                                   N = "GameDVR_Enabled";   T = "REG_DWORD"; V = 0 }
    @{ P = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR";              N = "AllowGameDVR";      T = "REG_DWORD"; V = 0 }
    @{ P = "HKCU\Software\Microsoft\GameBar";                               N = "AutoGameModeEnabled"; T = "REG_DWORD"; V = 1 }
    @{ P = "HKCU\Software\Microsoft\GameBar";                               N = "AllowAutoGameMode"; T = "REG_DWORD"; V = 1 }
    @{ P = "HKCU\Control Panel\Mouse";                                      N = "MouseSpeed";        T = "REG_SZ";    V = "0" }
    @{ P = "HKCU\Control Panel\Mouse";                                      N = "MouseThreshold1";   T = "REG_SZ";    V = "0" }
    @{ P = "HKCU\Control Panel\Mouse";                                      N = "MouseThreshold2";   T = "REG_SZ";    V = "0" }
    @{ P = "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers";         N = "HwSchMode";         T = "REG_DWORD"; V = 2 }
)

if ($Revert) {
    Log "REVERT mode: restoring previous state" "warn"
    Set-ShadowStatus -Component "GameOptimizer" -Status "Reverting"
    if ($state.PSObject.Properties.Name -contains "MemoryCompression") { if ($state.MemoryCompression) { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } }
    if ($state.PSObject.Properties.Name -contains "PriorScheme") { powercfg -setactive $state.PriorScheme 2>$null }
    if ($state.PSObject.Properties.Name -contains "Reg") {
        foreach ($r in $state.Reg) {
            if ($null -eq $r.Prior) { reg delete $r.P /v $r.N /f 2>$null | Out-Null }
            else { reg add $r.P /v $r.N /t $r.T /d "$($r.Prior)" /f 2>$null | Out-Null }
        }
    }
    if ($state.PSObject.Properties.Name -contains "Wake") { foreach ($d in $state.Wake) { powercfg -deviceenablewake "$d" 2>$null | Out-Null } }
    if ($state.PSObject.Properties.Name -contains "Eee") {
        foreach ($e in $state.Eee) { Set-NetAdapterAdvancedProperty -Name $e.Adapter -DisplayName $e.DisplayName -DisplayValue $e.Prior -NoRestart -ErrorAction SilentlyContinue | Out-Null }
    }
    Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    Set-ShadowStatus -Component "GameOptimizer" -Status "Reverted"
    Log "REVERT complete. Reboot to fully restore HAGS/memory compression." "warn"
    exit 0
}

# ============ APPLY ============
$state = @{ Reg = @(); Wake = @(); Eee = @() }
Set-ShadowStatus -Component "GameOptimizer" -Status "Applying"

# 1. Memory compression OFF
try {
    $mc = (Get-MMAgent -ErrorAction Stop).MemoryCompression
    $state.MemoryCompression = [bool]$mc
    if ($mc) { Disable-MMAgent -MemoryCompression -ErrorAction Stop; Log "Memory compression disabled (was ON)" }
    else { Log "Memory compression already off" }
} catch { Log "Memory compression toggle failed: $($_.Exception.Message)" "warn" }

# 2. Ultimate Performance plan + sub-settings
try {
    $prior = Get-Guid (powercfg -getactivescheme)
    $state.PriorScheme = $prior
    $newGuid = Get-Guid (powercfg -duplicatescheme $ULT_GUID 2>$null)
    if ($newGuid) { powercfg -setactive $newGuid | Out-Null; Log "Ultimate Performance plan activated ($newGuid)" }
    else { Log "Ultimate plan duplicate failed, tuning active scheme instead" "warn" }
    powercfg -setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60fe74077 893dee8e-2d51-4f0e-a269-5807a749e56f 100
    powercfg -setdcvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60fe74077 893dee8e-2d51-4f0e-a269-5807a749e56f 100
    powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg -setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0
    powercfg -setactive SCHEME_CURRENT | Out-Null
    Log "Power sub-settings forced: CPU min 100%, USB suspend off, PCIe ASPM off"
} catch { Log "Power plan tuning failed: $($_.Exception.Message)" "warn" }

# 3. Registry layer
foreach ($a in $regActions) {
    $priorVal = $null
    try { $priorVal = (Get-ItemProperty -Path ("Registry::" + $a.P) -Name $a.N -ErrorAction Stop).($a.N) } catch { $priorVal = $null }
    $state.Reg += @{ P = $a.P; N = $a.N; T = $a.T; Prior = $priorVal }
    reg add $a.P /v $a.N /t $a.T /d "$($a.V)" /f 2>$null | Out-Null
    Log "Registry enforced: $($a.P)\$($a.N) = $($a.V)"
}

# 4. Kill wake-capable devices
try {
    $armed = powercfg -devicequery wake_armed 2>$null | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "NONE|None" }
    foreach ($d in $armed) {
        powercfg -devicedisablewake "$d" 2>$null | Out-Null
        $state.Wake += $d
        Log "Wake disabled: $d"
    }
} catch { Log "Wake device sweep failed: $($_.Exception.Message)" "warn" }

# 5. Energy Efficient Ethernet OFF per adapter
try {
    foreach ($ad in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        $props = Get-NetAdapterAdvancedProperty -Name $ad.Name -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -match "Energy Efficient|EEE|Green Ethernet|GigaLite" }
        foreach ($p in $props) {
            if ($p.DisplayValue -ne "Disabled") {
                $state.Eee += @{ Adapter = $ad.Name; DisplayName = $p.DisplayName; Prior = $p.DisplayValue }
                Set-NetAdapterAdvancedProperty -Name $ad.Name -DisplayName $p.DisplayName -DisplayValue "Disabled" -NoRestart -ErrorAction SilentlyContinue | Out-Null
                Log "EEE disabled on $($ad.Name) ($($p.DisplayName))"
            }
        }
    }
} catch { Log "EEE sweep failed: $($_.Exception.Message)" "warn" }

Save-State
Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true }
Log "GameOptimizer APPLY complete. Reboot once for HAGS + memory compression to fully latch."
"=== GameOptimizer applied. State saved to $stateFile. REBOOT once. ==="
"=== To undo everything: .\components\GameOptimizer.ps1 -Revert ==="
