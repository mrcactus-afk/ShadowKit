# ShadowLogger.ps1 – safe stub (no Export-ModuleMember)
function Write-ShadowKitLog {
    param($Message, $Level='info', $Module='System', $Data=@{})
    # Do nothing – fallback for components that call this
}
function Read-ShadowKitLog {
    param($Tail=200)
    return @()
}
