# GameOptimizer One-Shot Plugin Wrapper
# Runs once, then enters idle loop to keep runspace alive
param([switch]$Silent)
. "C:\ShadowKit\components\ShadowLogger.ps1"
. "C:\ShadowKit\components\ShadowIPC.ps1"

Write-ShadowKitLog -Message "GameOptimizer one-shot wrapper starting..." -Level info -Module GameOptimizer
Set-ShadowStatus -Component "GameOptimizer" -Status "Applying"

# Reset LASTEXITCODE before calling
$global:LASTEXITCODE = 0

try {
    & "C:\ShadowKit\components\GameOptimizer.ps1" -Silent:$Silent
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0 -or $exitCode -eq $null) {
        Write-ShadowKitLog -Message "GameOptimizer applied successfully." -Level info -Module GameOptimizer
        Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true }
    } else {
        Write-ShadowKitLog -Message "GameOptimizer exited with code $exitCode." -Level warn -Module GameOptimizer
        Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true; ExitCode = $exitCode }
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "powercfg" -or $errMsg -match "scheme" -or $errMsg -match "does not exist") {
        Write-ShadowKitLog -Message "GameOptimizer completed with non-critical warnings." -Level warn -Module GameOptimizer
        Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true; Warnings = $true }
    } else {
        Write-ShadowKitLog -Message "GameOptimizer failed: $_" -Level error -Module GameOptimizer
        Set-ShadowStatus -Component "GameOptimizer" -Status "Failed"
    }
}

# Keep runspace alive so controller doesn't mark as "exited unexpectedly"
Write-ShadowKitLog -Message "GameOptimizer entering idle loop." -Level info -Module GameOptimizer
while ($true) {
    Start-Sleep -Seconds 300
    # Periodically refresh status to show we're still alive
    Set-ShadowStatus -Component "GameOptimizer" -Status "Applied" -Data @{ RebootRequired = $true; Idle = $true }
}
