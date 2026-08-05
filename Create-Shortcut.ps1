$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\ShadowKit GUI.lnk")
$Shortcut.TargetPath = "C:\ShadowKit\Launch-GUI.bat"
$Shortcut.Save()
Write-Host "Desktop shortcut created." -ForegroundColor Green
