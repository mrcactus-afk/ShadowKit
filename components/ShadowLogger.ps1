$script:ShadowKitLogFile = "$PSScriptRoot\..\state\shadowkit.jsonl"
function Write-ShadowKitLog {
    param([string]$Message, [string]$Level = "info", [string]$Module = "Core", [hashtable]$Data = @{})
    $dir = Split-Path $script:ShadowKitLogFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $fi = Get-Item $script:ShadowKitLogFile -ErrorAction SilentlyContinue
    if ($fi -and $fi.Length -gt 5MB) { Move-Item $script:ShadowKitLogFile "$script:ShadowKitLogFile.old" -Force }
    @{ timestamp = (Get-Date -Format "o"); level = $Level.ToLower(); module = $Module; message = $Message; pid = $PID; data = $Data } |
        ConvertTo-Json -Compress | Out-File -Append -Encoding UTF8 -FilePath $script:ShadowKitLogFile
}
