# ============================================================
# ShadowKit GUI v1.0 – Control Panel
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $result = [System.Windows.Forms.MessageBox]::Show("This tool works best with Administrator privileges.`nContinue without admin?", "ShadowKit GUI", "YesNo", "Warning")
    if ($result -eq "No") { exit }
}

$script:baseDir = "C:\ShadowKit"
$script:logDir = Join-Path $baseDir "logs"
$script:configFile = Join-Path $baseDir "config.json"
$script:serversFile = Join-Path $baseDir "servers.json"

function Get-TaskStatus {
    $task = Get-ScheduledTask -TaskName "ShadowKit" -ErrorAction SilentlyContinue
    if ($task) { return $task.State } else { return "Not found" }
}

function Get-ComponentStatus {
    $proc = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*ShadowController*" }
    if ($proc) { return "Running (PID $($proc.Id))" } else { return "Not running" }
}

function Get-ConfigState {
    param($Component)
    $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
    return $cfg.$Component.enabled
}

function Set-ConfigState {
    param($Component, $State)
    $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
    $cfg.$Component.enabled = $State
    $cfg | ConvertTo-Json -Depth 5 | Out-File $configFile -Encoding utf8
}

function Get-LogContent {
    param($LogName)
    $path = Join-Path $logDir $LogName
    if (Test-Path $path) {
        return Get-Content $path -Tail 50 -ErrorAction SilentlyContinue
    } else {
        return "Log file not found."
    }
}

function Update-StatusLabels {
    $taskStatusLabel.Text = "Scheduled Task: $(Get-TaskStatus)"
    $compStatusLabel.Text = "Controller: $(Get-ComponentStatus)"
    $wdState = Get-ConfigState -Component "watchdog"
    $dnsState = Get-ConfigState -Component "dns"
    $memState = Get-ConfigState -Component "memory"
    $wdStatusLabel.Text = "Watchdog: $(if($wdState){'Enabled'}else{'Disabled'})"
    $dnsStatusLabel.Text = "DNS: $(if($dnsState){'Enabled'}else{'Disabled'})"
    $memStatusLabel.Text = "Memory: $(if($memState){'Enabled'}else{'Disabled'})"
}

function Restart-ShadowKit {
    schtasks /end /tn "ShadowKit" 2>$null
    Start-ScheduledTask -TaskName "ShadowKit"
    Start-Sleep -Seconds 2
    Update-StatusLabels
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "ShadowKit Control Panel v1.0"
$form.Size = New-Object System.Drawing.Size(850, 650)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"
$form.Controls.Add($tabControl)

# ---- Tab 1: Status ----
$tabStatus = New-Object System.Windows.Forms.TabPage
$tabStatus.Text = "Status"
$tabControl.TabPages.Add($tabStatus)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = "Fill"
$statusPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$tabStatus.Controls.Add($statusPanel)

$sysGroup = New-Object System.Windows.Forms.GroupBox
$sysGroup.Text = "System Status"
$sysGroup.Location = New-Object System.Drawing.Point(10, 10)
$sysGroup.Size = New-Object System.Drawing.Size(380, 160)
$statusPanel.Controls.Add($sysGroup)

$taskStatusLabel = New-Object System.Windows.Forms.Label
$taskStatusLabel.Text = "Scheduled Task: ..."
$taskStatusLabel.AutoSize = $true
$taskStatusLabel.Location = New-Object System.Drawing.Point(10, 25)
$sysGroup.Controls.Add($taskStatusLabel)

$compStatusLabel = New-Object System.Windows.Forms.Label
$compStatusLabel.Text = "Controller: ..."
$compStatusLabel.AutoSize = $true
$compStatusLabel.Location = New-Object System.Drawing.Point(10, 55)
$sysGroup.Controls.Add($compStatusLabel)

$refreshBtn = New-Object System.Windows.Forms.Button
$refreshBtn.Text = "Refresh"
$refreshBtn.Location = New-Object System.Drawing.Point(10, 90)
$refreshBtn.Size = New-Object System.Drawing.Size(100, 30)
$refreshBtn.Add_Click({ Update-StatusLabels })
$sysGroup.Controls.Add($refreshBtn)

$restartBtn = New-Object System.Windows.Forms.Button
$restartBtn.Text = "Restart All"
$restartBtn.Location = New-Object System.Drawing.Point(120, 90)
$restartBtn.Size = New-Object System.Drawing.Size(120, 30)
$restartBtn.Add_Click({
    Restart-ShadowKit
    [System.Windows.Forms.MessageBox]::Show("ShadowKit restarted.", "Action", "OK", "Information")
})
$sysGroup.Controls.Add($restartBtn)

$healthBtn = New-Object System.Windows.Forms.Button
$healthBtn.Text = "Health Check"
$healthBtn.Location = New-Object System.Drawing.Point(250, 90)
$healthBtn.Size = New-Object System.Drawing.Size(120, 30)
$healthBtn.Add_Click({
    $msg = "Health Check Results:`n"
    $msg += "Scheduled Task: $(Get-TaskStatus)`n"
    $msg += "Controller: $(Get-ComponentStatus)`n"
    $msg += "Watchdog: $(if((Get-ConfigState -Component 'watchdog')){'Enabled'}else{'Disabled'})`n"
    $msg += "DNS: $(if((Get-ConfigState -Component 'dns')){'Enabled'}else{'Disabled'})`n"
    $msg += "Memory: $(if((Get-ConfigState -Component 'memory')){'Enabled'}else{'Disabled'})"
    [System.Windows.Forms.MessageBox]::Show($msg, "Health Check", "OK", "Information")
})
$sysGroup.Controls.Add($healthBtn)

$compGroup = New-Object System.Windows.Forms.GroupBox
$compGroup.Text = "Component Control"
$compGroup.Location = New-Object System.Drawing.Point(410, 10)
$compGroup.Size = New-Object System.Drawing.Size(400, 200)
$statusPanel.Controls.Add($compGroup)

$wdStatusLabel = New-Object System.Windows.Forms.Label
$wdStatusLabel.Text = "Watchdog: ..."
$wdStatusLabel.AutoSize = $true
$wdStatusLabel.Location = New-Object System.Drawing.Point(10, 30)
$compGroup.Controls.Add($wdStatusLabel)

$wdToggleBtn = New-Object System.Windows.Forms.Button
$wdToggleBtn.Text = "Toggle"
$wdToggleBtn.Location = New-Object System.Drawing.Point(150, 25)
$wdToggleBtn.Size = New-Object System.Drawing.Size(80, 30)
$wdToggleBtn.Add_Click({
    $current = Get-ConfigState -Component "watchdog"
    $new = -not $current
    Set-ConfigState -Component "watchdog" -State $new
    Restart-ShadowKit
    Update-StatusLabels
    [System.Windows.Forms.MessageBox]::Show("Watchdog set to $(if($new){'Enabled'}else{'Disabled'}).", "Action", "OK", "Information")
})
$compGroup.Controls.Add($wdToggleBtn)

$dnsStatusLabel = New-Object System.Windows.Forms.Label
$dnsStatusLabel.Text = "DNS: ..."
$dnsStatusLabel.AutoSize = $true
$dnsStatusLabel.Location = New-Object System.Drawing.Point(10, 70)
$compGroup.Controls.Add($dnsStatusLabel)

$dnsToggleBtn = New-Object System.Windows.Forms.Button
$dnsToggleBtn.Text = "Toggle"
$dnsToggleBtn.Location = New-Object System.Drawing.Point(150, 65)
$dnsToggleBtn.Size = New-Object System.Drawing.Size(80, 30)
$dnsToggleBtn.Add_Click({
    $current = Get-ConfigState -Component "dns"
    $new = -not $current
    Set-ConfigState -Component "dns" -State $new
    Restart-ShadowKit
    Update-StatusLabels
    [System.Windows.Forms.MessageBox]::Show("DNS set to $(if($new){'Enabled'}else{'Disabled'}).", "Action", "OK", "Information")
})
$compGroup.Controls.Add($dnsToggleBtn)

$memStatusLabel = New-Object System.Windows.Forms.Label
$memStatusLabel.Text = "Memory: ..."
$memStatusLabel.AutoSize = $true
$memStatusLabel.Location = New-Object System.Drawing.Point(10, 110)
$compGroup.Controls.Add($memStatusLabel)

$memToggleBtn = New-Object System.Windows.Forms.Button
$memToggleBtn.Text = "Toggle"
$memToggleBtn.Location = New-Object System.Drawing.Point(150, 105)
$memToggleBtn.Size = New-Object System.Drawing.Size(80, 30)
$memToggleBtn.Add_Click({
    $current = Get-ConfigState -Component "memory"
    $new = -not $current
    Set-ConfigState -Component "memory" -State $new
    Restart-ShadowKit
    Update-StatusLabels
    [System.Windows.Forms.MessageBox]::Show("Memory set to $(if($new){'Enabled'}else{'Disabled'}).", "Action", "OK", "Information")
})
$compGroup.Controls.Add($memToggleBtn)

# ---- Tab 2: Logs ----
$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "Logs"
$tabControl.TabPages.Add($tabLogs)

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = "Fill"
$logPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$tabLogs.Controls.Add($logPanel)

$logSelectorLabel = New-Object System.Windows.Forms.Label
$logSelectorLabel.Text = "Select Log:"
$logSelectorLabel.AutoSize = $true
$logSelectorLabel.Location = New-Object System.Drawing.Point(10, 15)
$logPanel.Controls.Add($logSelectorLabel)

$logCombo = New-Object System.Windows.Forms.ComboBox
$logCombo.Location = New-Object System.Drawing.Point(120, 12)
$logCombo.Size = New-Object System.Drawing.Size(200, 25)
$logCombo.Items.AddRange(@("dns.log", "memory.log", "watchdog.log", "master_*.log"))
$logCombo.SelectedIndex = 0
$logPanel.Controls.Add($logCombo)

$logRefreshBtn = New-Object System.Windows.Forms.Button
$logRefreshBtn.Text = "Refresh"
$logRefreshBtn.Location = New-Object System.Drawing.Point(340, 10)
$logRefreshBtn.Size = New-Object System.Drawing.Size(80, 30)
$logRefreshBtn.Add_Click({
    $selected = $logCombo.SelectedItem
    if ($selected -eq "master_*.log") {
        $logFile = Get-ChildItem (Join-Path $logDir "master_*.log") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($logFile) { $content = Get-LogContent -LogName $logFile.Name } else { $content = "No master log found." }
    } else {
        $content = Get-LogContent -LogName $selected
    }
    $logTextBox.Text = $content
})
$logPanel.Controls.Add($logRefreshBtn)

$logTextBox = New-Object System.Windows.Forms.TextBox
$logTextBox.Multiline = $true
$logTextBox.ScrollBars = "Vertical"
$logTextBox.ReadOnly = $true
$logTextBox.Location = New-Object System.Drawing.Point(10, 50)
$logTextBox.Size = New-Object System.Drawing.Size(800, 480)
$logTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logPanel.Controls.Add($logTextBox)

$logCombo_SelectedIndexChanged = {
    $selected = $logCombo.SelectedItem
    if ($selected -eq "master_*.log") {
        $logFile = Get-ChildItem (Join-Path $logDir "master_*.log") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($logFile) { $content = Get-LogContent -LogName $logFile.Name } else { $content = "No master log found." }
    } else {
        $content = Get-LogContent -LogName $selected
    }
    $logTextBox.Text = $content
}
$logCombo.Add_SelectedIndexChanged($logCombo_SelectedIndexChanged)
$logCombo_SelectedIndexChanged.Invoke()

# ---- Tab 3: Config ----
$tabConfig = New-Object System.Windows.Forms.TabPage
$tabConfig.Text = "Config"
$tabControl.TabPages.Add($tabConfig)

$configPanel = New-Object System.Windows.Forms.Panel
$configPanel.Dock = "Fill"
$configPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$tabConfig.Controls.Add($configPanel)

$configEditBtn = New-Object System.Windows.Forms.Button
$configEditBtn.Text = "Edit config.json"
$configEditBtn.Location = New-Object System.Drawing.Point(10, 20)
$configEditBtn.Size = New-Object System.Drawing.Size(180, 30)
$configEditBtn.Add_Click({
    if (Test-Path $configFile) {
        Start-Process notepad.exe $configFile
    } else {
        [System.Windows.Forms.MessageBox]::Show("config.json not found.", "Error", "OK", "Error")
    }
})
$configPanel.Controls.Add($configEditBtn)

$serversEditBtn = New-Object System.Windows.Forms.Button
$serversEditBtn.Text = "Edit servers.json"
$serversEditBtn.Location = New-Object System.Drawing.Point(200, 20)
$serversEditBtn.Size = New-Object System.Drawing.Size(180, 30)
$serversEditBtn.Add_Click({
    if (Test-Path $serversFile) {
        Start-Process notepad.exe $serversFile
    } else {
        [System.Windows.Forms.MessageBox]::Show("servers.json not found.", "Error", "OK", "Error")
    }
})
$configPanel.Controls.Add($serversEditBtn)

$configReloadBtn = New-Object System.Windows.Forms.Button
$configReloadBtn.Text = "Reload Config (Restart)"
$configReloadBtn.Location = New-Object System.Drawing.Point(390, 20)
$configReloadBtn.Size = New-Object System.Drawing.Size(180, 30)
$configReloadBtn.Add_Click({
    Restart-ShadowKit
    [System.Windows.Forms.MessageBox]::Show("Config reloaded (ShadowKit restarted).", "Action", "OK", "Information")
})
$configPanel.Controls.Add($configReloadBtn)

# ---- Tab 4: About ----
$tabAbout = New-Object System.Windows.Forms.TabPage
$tabAbout.Text = "About"
$tabControl.TabPages.Add($tabAbout)

$aboutLabel = New-Object System.Windows.Forms.Label
$aboutLabel.Text = "ShadowKit Control Panel v1.0`n`nBuilt for Butter by CAT Shadow Hacker.`nComponent toggles enable/disable in real-time.`n`nOpen source under MIT License."
$aboutLabel.AutoSize = $true
$aboutLabel.Location = New-Object System.Drawing.Point(20, 20)
$aboutLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$tabAbout.Controls.Add($aboutLabel)

# ---- Show ----
Update-StatusLabels
$form.ShowDialog()
