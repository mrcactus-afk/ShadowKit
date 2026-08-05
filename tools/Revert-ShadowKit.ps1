param([switch]$SystemRestore)
& "C:\ShadowKit\components\SystemCalibrator.ps1" -Restore -Silent
& "C:\ShadowKit\components\SystemCalibrator.ps1" -Restore -UserScope -Silent
if ($SystemRestore -and (Test-Path "C:\ShadowKit\restorepoint.json")) {
    $rp = Get-Content "C:\ShadowKit\restorepoint.json" -Raw | ConvertFrom-Json
    if ($rp.seq) {
        ([wmiclass]"root\default:SystemRestore").Restore($rp.seq) | Out-Null
    } else {
        "System Restore point unavailable on this machine; baseline values restored above."
    }
}
"Revert complete."


