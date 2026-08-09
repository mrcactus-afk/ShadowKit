# GameOptimizer One-Shot Plugin Wrapper
param([switch]$Silent)
. "C:\ShadowKit\components\ShadowLogger.ps1"
. "C:\ShadowKit\components\ShadowIPC.ps1"

Write-ShadowKitLog -Message "GameOptimizer one-shot wrapper starting..." -Level info -Module GameOptimizer
Set-ShadowStatus -Component "GameOptimizer" -Status "Applying"

try {
    & "C:\ShadowKit\components\GameOptimizer.ps1" -Silent:$Silent
    Write-ShadowKitLog -Message "GameOptimizer applied successfully." -Level info -Module GameOptimizer
    Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true }
} catch {
    Write-ShadowKitLog -Message "GameOptimizer failed: $_" -Level error -Module GameOptimizer
    Set-ShadowStatus -Component "GameOptimizer" -Status "Failed"
}
exit 0
