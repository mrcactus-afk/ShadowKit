param([switch]$Force)
Add-Type -AssemblyName System.Windows.Forms
$logDir = "C:\ShadowKit\logs"
$popupLog = Join-Path $logDir "popup.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Write-PopupLog { param($m,$l="info") $ts=Get-Date -Format "yyyy-MM-dd HH:mm:ss"; "[$ts] [$l] $m" | Out-File -Append $popupLog }
try {
    $errors = @()
    $logFiles = Get-ChildItem $logDir -Filter "*.log" -File | Where-Object { $_.Name -ne "popup.log" }
    foreach ($f in $logFiles) {
        $lines = Get-Content $f.FullName -Tail 50 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '\[error\]') {
                $errors += "[$($f.Name)] $line"
            }
        }
    }
    if ($Force -or $errors.Count -gt 0) {
        $msg = "ShadowKit Errors`n$(Get-Date)`n`n" + ($errors -join "`n")
        [void][System.Windows.Forms.MessageBox]::Show($msg, "ShadowKit Alert", "OK", "Warning")
        Write-PopupLog "Popup displayed: $($errors.Count) errors"
    }
} catch { Write-PopupLog "ErrorPopup failed: $_" "error" }
