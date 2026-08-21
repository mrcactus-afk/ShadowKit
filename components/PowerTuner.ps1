param([switch]$Apply, [switch]$Revert, [switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
$stateFile = Join-Path $baseDir 'state\powertuner.state.json'
$logFile = Join-Path $baseDir 'logs\power.log'
New-Item -ItemType Directory -Path (Split-Path $stateFile), (Split-Path $logFile) -Force | Out-Null
function Write-PwrLog { param($m,$l='info') $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$ts [$l] $m" | Out-File $logFile -Append -Encoding UTF8 }

$baseScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'  # Balanced
$subProcessor = '54533251-82be-4824-96c1-47b60b740d00'
$setMaxProc = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
$setMinProc = '893dee8e-2bef-41e0-89c6-b55d0929964c'
$setCooling = '94D3A615-A899-4AC5-AE2B-E4D8F634367F'
$subPcie = '501a4d13-42af-4429-9fd1-a8218c268e20'
$setAspm = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
$subUsb = '2a737441-1930-4402-8d77-b2bebba308a3'
$setSelectiveSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Get-ActivePlanGuid {
    return (powercfg /getactivescheme | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
}

function Test-PlanExists {
    param([string]$guid)
    if (-not $guid) { return $false }
    return [bool](powercfg /list | Select-String $guid)
}

if ($Revert) {
    if (-not (Test-Path $stateFile)) { Write-PwrLog 'No state file, nothing to revert' warn; exit 0 }
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($state.originalScheme -and (Test-PlanExists $state.originalScheme)) {
        powercfg /setactive $state.originalScheme | Out-Null
        Write-PwrLog "Restored original scheme $($state.originalScheme)"
    }
    if ($state.duplicatedScheme -and (Test-PlanExists $state.duplicatedScheme)) {
        powercfg /delete $state.duplicatedScheme 2>$null | Out-Null
        Write-PwrLog "Deleted duplicated scheme $($state.duplicatedScheme)"
    }
    Remove-Item $stateFile -Force
    Set-ShadowStatus -Component 'PowerTuner' -Status 'Reverted'
    Write-PwrLog 'PowerTuner revert complete'
    exit 0
}

if ($Apply) {
    $original = Get-ActivePlanGuid
    # Reuse existing duplicated scheme if present and valid
    if (Test-Path $stateFile) {
        $existingState = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($existingState.duplicatedScheme -and (Test-PlanExists $existingState.duplicatedScheme)) {
            powercfg /setactive $existingState.duplicatedScheme | Out-Null
            Set-ShadowStatus -Component 'PowerTuner' -Status 'Applied'
            Write-PwrLog "Reused existing tuned plan $($existingState.duplicatedScheme)"
            exit 0
        }
    }
    $dup = powercfg /duplicatescheme $baseScheme 2>$null
    if (-not $dup) { Write-PwrLog 'Failed to duplicate Balanced scheme' error; exit 1 }
    $newGuid = ($dup | Select-String '([0-9a-f-]{36})').Matches[0].Groups[1].Value
    # Apply tuned settings
    $errors = @()
    try { powercfg /setacvalueindex $newGuid $subProcessor $setMaxProc 100 | Out-Null } catch { $errors += $_ }
    try { powercfg /setacvalueindex $newGuid $subProcessor $setMinProc 5 | Out-Null } catch { $errors += $_ }
    try { powercfg /setacvalueindex $newGuid $subProcessor $setCooling 1 | Out-Null } catch { $errors += $_ }
    try { powercfg /setacvalueindex $newGuid $subPcie $setAspm 0 | Out-Null } catch { $errors += $_ }
    try { powercfg /setacvalueindex $newGuid $subUsb $setSelectiveSuspend 0 | Out-Null } catch { $errors += $_ }
    if ($errors.Count -gt 0) { Write-PwrLog "PowerTuner errors: $($errors -join '; ')" error }
    powercfg /setactive $newGuid | Out-Null
    @{ originalScheme = $original; duplicatedScheme = $newGuid } | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
    Set-ShadowStatus -Component 'PowerTuner' -Status 'Applied'
    Write-PwrLog "PowerTuner applied tuned Balanced plan $newGuid"
    exit 0
}
Write-Host "Usage: PowerTuner.ps1 -Apply   or   -Revert"
