Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

# Performance counters
$cpuCounter = $null
try { $cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total"); $cpuCounter.NextValue() | Out-Null } catch {}

# Data buffers for graphs
$script:maxPoints = 60
$script:cpuHistory = New-Object System.Collections.Generic.List[float]
$script:ramHistory = New-Object System.Collections.Generic.List[float]
$script:tempHistory = New-Object System.Collections.Generic.List[float]
for ($i=0; $i -lt $script:maxPoints; $i++) { $script:cpuHistory.Add(0); $script:ramHistory.Add(0); $script:tempHistory.Add(0) }

function Get-RamPercent {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $total = $os.TotalVisibleMemorySize
        $free = $os.FreePhysicalMemory
        return [math]::Round((($total - $free) / $total) * 100, 1)
    } catch { return 0 }
}

function Get-CpuPercent {
    if ($script:cpuCounter) {
        try { return [math]::Round($script:cpuCounter.NextValue(), 1) } catch {}
    }
    try { return [math]::Round((Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average, 1) } catch { return 0 }
}

function Get-TempC {
    try {
        $sensor = Get-CimInstance -Namespace "root\LibreHardwareMonitor" -ClassName Sensor -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Name -match 'CPU Package' }
        if ($sensor) { return [math]::Round($sensor.Value, 1) }
    } catch {}
    try {
        $status = Get-ShadowStatus -Component 'ThermalManager'
        if ($status -and $status.data -and $status.data.TempC) { return $status.data.TempC }
    } catch {}
    try {
        $fallback = Get-CimInstance -Namespace "root\wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
        if ($fallback) { return [math]::Round(($fallback.CurrentTemperature - 2732) / 10, 1) }
    } catch {}
    return 0
}

function Update-History([System.Collections.Generic.List[float]]$list, [float]$value) {
    if ($list.Count -ge $script:maxPoints) { $list.RemoveAt(0) }
    $list.Add($value)
}

function Update-GraphPolyline($polyline, $history, $chartHeight, $chartWidth) {
    if ($history.Count -lt 2) { return }
    $height = if ($chartHeight -gt 1) { $chartHeight } else { 150 }
    $width = if ($chartWidth -gt 1) { $chartWidth } else { 250 }
    $points = New-Object System.Windows.Media.PointCollection
    $stepX = $width / ($script:maxPoints - 1)
    for ($i = 0; $i -lt $history.Count; $i++) {
        $x = $i * $stepX
        $y = $height - (($history[$i] / 100) * $height)
        $points.Add([System.Windows.Point]::new($x, $y))
    }
    $polyline.Points = $points
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ShadowKit v8.0 Control Center" Height="800" Width="1200"
        Background="#1E1E1E" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="SHADOWKIT v8.0" FontSize="22" FontWeight="Bold" Foreground="#007ACC" Margin="0,0,0,10"/>
        <TabControl Grid.Row="1" x:Name="MainTabs" Background="#252526" BorderThickness="1" BorderBrush="#3F3F46">
            <TabItem Header="Summary" Background="#252526">
                <TextBox x:Name="SummaryBox" Background="#252526" Foreground="#F1F1F1" BorderThickness="0" FontFamily="Consolas" FontSize="13" IsReadOnly="True" VerticalScrollBarVisibility="Auto"/>
            </TabItem>
            <TabItem Header="MemoryCleaner" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="Standby List:" FontSize="14" Foreground="#F1F1F1"/>
                    <TextBlock x:Name="StandbyText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <TextBlock Text="Last Purge:" FontSize="14" Foreground="#F1F1F1" Margin="0,10,0,0"/>
                    <TextBlock x:Name="PurgeText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#FFAA00"/>
                    <Button x:Name="PurgeBtn" Content="Purge Standby List" Width="180" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="DNSFrenzy" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="Primary DNS:" FontSize="14" Foreground="#F1F1F1"/>
                    <TextBlock x:Name="DnsPrimaryText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <TextBlock Text="Secondary DNS:" FontSize="14" Foreground="#F1F1F1" Margin="0,10,0,0"/>
                    <TextBlock x:Name="DnsSecondaryText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <TextBlock Text="Server:" FontSize="14" Foreground="#F1F1F1" Margin="0,10,0,0"/>
                    <TextBlock x:Name="DnsNameText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#FFAA00"/>
                    <Button x:Name="RefreshDnsBtn" Content="Refresh DNS" Width="150" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="TimerOptimizer" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="Timer Resolution:" FontSize="14" Foreground="#F1F1F1"/>
                    <TextBlock x:Name="TimerResText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <TextBlock Text="Minimum Resolution:" FontSize="14" Foreground="#F1F1F1" Margin="0,10,0,0"/>
                    <TextBlock x:Name="TimerMinText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="SystemCalibrator" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="Last Drift:" FontSize="14" Foreground="#F1F1F1"/>
                    <TextBlock x:Name="CalibDriftText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <TextBlock Text="Active Entries:" FontSize="14" Foreground="#F1F1F1" Margin="0,10,0,0"/>
                    <TextBlock x:Name="CalibEntriesText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    <Button x:Name="CalibBtn" Content="Run Enforcement" Width="160" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="Tier1 Optimizers" Background="#252526">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="10">
                        <TextBlock Text="Network Optimizer" FontSize="16" FontWeight="Bold" Foreground="#F1F1F1"/>
                        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
                            <Button x:Name="ApplyNetwork" Content="Apply" Width="100"/>
                            <Button x:Name="RevertNetwork" Content="Revert" Width="100"/>
                        </StackPanel>
                        <TextBlock Text="File System Tuner" FontSize="16" FontWeight="Bold" Foreground="#F1F1F1"/>
                        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
                            <Button x:Name="ApplyFs" Content="Apply" Width="100"/>
                            <Button x:Name="RevertFs" Content="Revert" Width="100"/>
                        </StackPanel>
                        <TextBlock Text="Power Tuner" FontSize="16" FontWeight="Bold" Foreground="#F1F1F1"/>
                        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
                            <Button x:Name="ApplyPower" Content="Apply" Width="100"/>
                            <Button x:Name="RevertPower" Content="Revert" Width="100"/>
                        </StackPanel>
                        <TextBlock Text="Debloat Enforcer" FontSize="16" FontWeight="Bold" Foreground="#F1F1F1"/>
                        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
                            <Button x:Name="ApplyDebloat" Content="Apply" Width="100"/>
                            <Button x:Name="RevertDebloat" Content="Revert" Width="100"/>
                        </StackPanel>
                        <TextBlock Text="GPU Tuner" FontSize="16" FontWeight="Bold" Foreground="#F1F1F1"/>
                        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
                            <Button x:Name="ApplyGpu" Content="Apply" Width="100"/>
                            <Button x:Name="RevertGpu" Content="Revert" Width="100"/>
                        </StackPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="SecurityTweaker" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="WARNING: Disabling VBS/HVCI lowers security for performance gains." FontSize="14" FontWeight="Bold" Foreground="Red" TextWrapping="Wrap"/>
                    <TextBlock Text="Applies to Windows kernel protections. Requires reboot for full effect." FontSize="12" Foreground="#FFAA00" Margin="0,5,0,10" TextWrapping="Wrap"/>
                    <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                        <Button x:Name="ApplySecurity" Content="Apply" Width="100"/>
                        <Button x:Name="RevertSecurity" Content="Revert" Width="100"/>
                    </StackPanel>
                </StackPanel>
            </TabItem>
            <TabItem Header="Live Graphs" Background="#252526">
                <Grid Margin="10">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" Margin="5">
                        <TextBlock Text="CPU %" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                        <Canvas x:Name="CpuChart" Width="250" Height="150" Background="#1E1E1E" ClipToBounds="True">
                            <Polyline x:Name="CpuLine" Stroke="#4EC9B0" StrokeThickness="2"/>
                        </Canvas>
                        <TextBlock x:Name="CpuValueText" Text="0%" FontSize="12" Foreground="#4EC9B0" Margin="0,5,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Margin="5">
                        <TextBlock Text="RAM %" FontSize="14" FontWeight="Bold" Foreground="#FFAA00"/>
                        <Canvas x:Name="RamChart" Width="250" Height="150" Background="#1E1E1E" ClipToBounds="True">
                            <Polyline x:Name="RamLine" Stroke="#FFAA00" StrokeThickness="2"/>
                        </Canvas>
                        <TextBlock x:Name="RamValueText" Text="0%" FontSize="12" Foreground="#FFAA00" Margin="0,5,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2" Margin="5">
                        <TextBlock Text="Temperature C" FontSize="14" FontWeight="Bold" Foreground="#D16969"/>
                        <Canvas x:Name="TempChart" Width="250" Height="150" Background="#1E1E1E" ClipToBounds="True">
                            <Polyline x:Name="TempLine" Stroke="#D16969" StrokeThickness="2"/>
                        </Canvas>
                        <TextBlock x:Name="TempValueText" Text="0 C" FontSize="12" Foreground="#D16969" Margin="0,5,0,0"/>
                    </StackPanel>
                </Grid>
            </TabItem>
            <TabItem Header="Settings" Background="#252526">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="Config File:" FontSize="14" Foreground="#F1F1F1" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <ComboBox x:Name="SettingsFileCombo" Width="250" Height="28" SelectedIndex="0">
                            <ComboBoxItem Content="config.json"/>
                            <ComboBoxItem Content="config\profile.json"/>
                            <ComboBoxItem Content="config\servers.json"/>
                            <ComboBoxItem Content="config\thermalmanager.json"/>
                        </ComboBox>
                    </StackPanel>
                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
                        <Button x:Name="SettingsLoadBtn" Content="Load" Width="100"/>
                        <Button x:Name="SettingsValidateBtn" Content="Validate" Width="100"/>
                        <Button x:Name="SettingsSaveBtn" Content="Save" Width="100"/>
                    </StackPanel>
                    <TextBox Grid.Row="2" x:Name="SettingsContentBox" Background="#1E1E1E" Foreground="#F1F1F1" BorderThickness="1" BorderBrush="#3F3F46" FontFamily="Consolas" FontSize="13" AcceptsReturn="True" AcceptsTab="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                    <TextBlock Grid.Row="3" x:Name="SettingsStatusText" Text="Select a config file and click Load." FontSize="12" Foreground="#4EC9B0" Margin="0,10,0,0"/>
                </Grid>
            </TabItem>
        </TabControl>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,10,0,0">
            <Button x:Name="RefreshAllBtn" Content="Refresh All" Width="100"/>
            <Button x:Name="ApplyGameBtn" Content="Apply GameOptimizer" Width="150"/>
            <Button x:Name="RevertGameBtn" Content="Revert GameOptimizer" Width="150"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Controls
$summaryBox = $window.FindName('SummaryBox')
$standbyText = $window.FindName('StandbyText')
$purgeText = $window.FindName('PurgeText')
$purgeBtn = $window.FindName('PurgeBtn')
$dnsPrimaryText = $window.FindName('DnsPrimaryText')
$dnsSecondaryText = $window.FindName('DnsSecondaryText')
$dnsNameText = $window.FindName('DnsNameText')
$refreshDnsBtn = $window.FindName('RefreshDnsBtn')
$timerResText = $window.FindName('TimerResText')
$timerMinText = $window.FindName('TimerMinText')
$calibDriftText = $window.FindName('CalibDriftText')
$calibEntriesText = $window.FindName('CalibEntriesText')
$calibBtn = $window.FindName('CalibBtn')
$refreshAllBtn = $window.FindName('RefreshAllBtn')
$applyGameBtn = $window.FindName('ApplyGameBtn')
$revertGameBtn = $window.FindName('RevertGameBtn')
$applyNetwork = $window.FindName('ApplyNetwork')
$revertNetwork = $window.FindName('RevertNetwork')
$applyFs = $window.FindName('ApplyFs')
$revertFs = $window.FindName('RevertFs')
$applyPower = $window.FindName('ApplyPower')
$revertPower = $window.FindName('RevertPower')
$applyDebloat = $window.FindName('ApplyDebloat')
$revertDebloat = $window.FindName('RevertDebloat')
$applyGpu = $window.FindName('ApplyGpu')
$revertGpu = $window.FindName('RevertGpu')
$applySecurity = $window.FindName('ApplySecurity')
$revertSecurity = $window.FindName('RevertSecurity')
$cpuLine = $window.FindName('CpuLine')
$ramLine = $window.FindName('RamLine')
$tempLine = $window.FindName('TempLine')
$cpuValueText = $window.FindName('CpuValueText')
$ramValueText = $window.FindName('RamValueText')
$tempValueText = $window.FindName('TempValueText')
$cpuChart = $window.FindName('CpuChart')
$ramChart = $window.FindName('RamChart')
$tempChart = $window.FindName('TempChart')

function Update-All {
    # Status summary
    $status = Get-ShadowStatus
    if ($status) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("SHADOWKIT COMPONENT STATUS")
        [void]$sb.AppendLine("=========================")
        foreach ($prop in $status.PSObject.Properties) {
            $name = $prop.Name
            $s = $prop.Value.status
            $procId = $prop.Value.pid
            $updated = $prop.Value.updated
            [void]$sb.AppendLine("$name : $s (PID: $procId, Updated: $updated)")
        }
        $summaryBox.Text = $sb.ToString()

        # Component details
        if ($status.MemoryCleaner) {
            $data = $status.MemoryCleaner.data
            $standbyText.Text = if ($data.standbyMB) { "$($data.standbyMB) MB" } else { 'N/A' }
            $purgeText.Text = if ($data.lastPurge) { $data.lastPurge } else { 'Never' }
        }
        if ($status.DNSFrenzy) {
            $data = $status.DNSFrenzy.data
            $dnsPrimaryText.Text = if ($data.primary) { $data.primary } else { 'N/A' }
            $dnsSecondaryText.Text = if ($data.secondary) { $data.secondary } else { 'N/A' }
            $dnsNameText.Text = if ($data.name) { $data.name } else { 'N/A' }
        }
        if ($status.TimerOptimizer) {
            $data = $status.TimerOptimizer.data
            $timerResText.Text = if ($data.resolutionMs) { "$($data.resolutionMs) ms" } else { 'N/A' }
            $timerMinText.Text = if ($data.minResolutionMs) { "$($data.minResolutionMs) ms" } else { 'N/A' }
        }
        if ($status.SystemCalibrator) {
            $data = $status.SystemCalibrator.data
            $calibDriftText.Text = if ($data.LastDrift) { $data.LastDrift } else { 'N/A' }
            $calibEntriesText.Text = if ($data.Entries) { $data.Entries } else { 'N/A' }
        }
    } else {
        $summaryBox.Text = 'No status file found.'
    }

    # Live graphs update
    $cpu = Get-CpuPercent
    $ram = Get-RamPercent
    $temp = Get-TempC
    Update-History $script:cpuHistory $cpu
    Update-History $script:ramHistory $ram
    Update-History $script:tempHistory $temp
    Update-GraphPolyline $cpuLine $script:cpuHistory $cpuChart.Height $cpuChart.Width
    Update-GraphPolyline $ramLine $script:ramHistory $ramChart.Height $ramChart.Width
    Update-GraphPolyline $tempLine $script:tempHistory $tempChart.Height $tempChart.Width
    $cpuValueText.Text = "$cpu%"
    $ramValueText.Text = "$ram%"
    $tempValueText.Text = "$temp C"
}

# Button events (same as before)
$refreshAllBtn.Add_Click({ Update-All })
$purgeBtn.Add_Click({ Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force; try { $resp = Send-ShadowCommand -Action 'purge' -Payload @{ component = 'MemoryCleaner' }; [System.Windows.MessageBox]::Show($resp.result, 'Purge') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Purge Error') } })
$refreshDnsBtn.Add_Click({ Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force; try { $resp = Send-ShadowCommand -Action 'refresh' -Payload @{ component = 'DNSFrenzy' }; [System.Windows.MessageBox]::Show($resp.result, 'DNS Refresh') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'DNS Error') } })
$calibBtn.Add_Click({ Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force; try { $resp = Send-ShadowCommand -Action 'enforce' -Payload @{ component = 'SystemCalibrator' }; [System.Windows.MessageBox]::Show($resp.result, 'Enforcement') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Enforcement Error') } })
$applyGameBtn.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GameOptimizer.ps1`" -Apply"; [System.Windows.MessageBox]::Show('GameOptimizer applied.') })
$revertGameBtn.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GameOptimizer.ps1`" -Revert"; [System.Windows.MessageBox]::Show('GameOptimizer reverted.') })
$applyNetwork.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\NetworkOptimizer.ps1`" -Apply"; [System.Windows.MessageBox]::Show('NetworkOptimizer applied.') })
$revertNetwork.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\NetworkOptimizer.ps1`" -Revert"; [System.Windows.MessageBox]::Show('NetworkOptimizer reverted.') })
$applyFs.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\FileSystemTuner.ps1`" -Apply"; [System.Windows.MessageBox]::Show('FileSystemTuner applied.') })
$revertFs.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\FileSystemTuner.ps1`" -Revert"; [System.Windows.MessageBox]::Show('FileSystemTuner reverted.') })
$applyPower.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\PowerTuner.ps1`" -Apply"; [System.Windows.MessageBox]::Show('PowerTuner applied.') })
$revertPower.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\PowerTuner.ps1`" -Revert"; [System.Windows.MessageBox]::Show('PowerTuner reverted.') })
$applyDebloat.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\DebloatEnforcer.ps1`" -Apply"; [System.Windows.MessageBox]::Show('DebloatEnforcer applied.') })
$revertDebloat.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\DebloatEnforcer.ps1`" -Revert"; [System.Windows.MessageBox]::Show('DebloatEnforcer reverted.') })
$applyGpu.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GPUTuner.ps1`" -Apply"; [System.Windows.MessageBox]::Show('GPUTuner applied.') })
$revertGpu.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GPUTuner.ps1`" -Revert"; [System.Windows.MessageBox]::Show('GPUTuner reverted.') })
$applySecurity.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\SecurityTweaker.ps1`" -Apply"; [System.Windows.MessageBox]::Show('SecurityTweaker applied. Reboot for full effect.') })
$revertSecurity.Add_Click({ Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\SecurityTweaker.ps1`" -Revert"; [System.Windows.MessageBox]::Show('SecurityTweaker reverted.') })

# Timer and show
# Settings tab controls
$settingsFileCombo = $window.FindName('SettingsFileCombo')
$settingsContentBox = $window.FindName('SettingsContentBox')
$settingsLoadBtn = $window.FindName('SettingsLoadBtn')
$settingsValidateBtn = $window.FindName('SettingsValidateBtn')
$settingsSaveBtn = $window.FindName('SettingsSaveBtn')
$settingsStatusText = $window.FindName('SettingsStatusText')

$configFiles = @{
    'config.json' = Join-Path $baseDir 'config.json'
    'config\profile.json' = Join-Path $baseDir 'config\profile.json'
    'config\servers.json' = Join-Path $baseDir 'config\servers.json'
    'config\thermalmanager.json' = Join-Path $baseDir 'config\thermalmanager.json'
}

function Get-SelectedConfigPath {
    $selected = $settingsFileCombo.SelectedItem.Content
    if ($configFiles.ContainsKey($selected)) { return $configFiles[$selected] }
    return $null
}

$settingsLoadBtn.Add_Click({
    $path = Get-SelectedConfigPath
    if ($path -and (Test-Path $path)) {
        $settingsContentBox.Text = Get-Content $path -Raw
        $settingsStatusText.Text = "Loaded: $path"
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::GreenYellow
    } else {
        $settingsStatusText.Text = "Config file not found."
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::Tomato
    }
})

$settingsValidateBtn.Add_Click({
    $path = Get-SelectedConfigPath
    $content = $settingsContentBox.Text
    try {
        $null = $content | ConvertFrom-Json -ErrorAction Stop
        $settingsStatusText.Text = "JSON is valid."
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::GreenYellow
    } catch {
        $settingsStatusText.Text = "Invalid JSON: $($_.Exception.Message)"
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::Tomato
    }
})

$settingsSaveBtn.Add_Click({
    $path = Get-SelectedConfigPath
    $content = $settingsContentBox.Text
    try {
        $null = $content | ConvertFrom-Json -ErrorAction Stop
        Set-Content -Path $path -Value $content -Encoding UTF8
        $settingsStatusText.Text = "Saved: $path"
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::GreenYellow
    } catch {
        $settingsStatusText.Text = "Cannot save invalid JSON: $($_.Exception.Message)"
        $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::Tomato
    }
})

# Auto-load default config.json on start
# Manually load default config.json on start
$defaultConfigPath = Join-Path $baseDir 'config.json'
if (Test-Path $defaultConfigPath) {
    $settingsContentBox.Text = Get-Content $defaultConfigPath -Raw
    $settingsStatusText.Text = "Loaded: $defaultConfigPath"
    $settingsStatusText.Foreground = [System.Windows.Media.Brushes]::GreenYellow
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({ Update-All })
$timer.Start()
Update-All
$window.ShowDialog() | Out-Null



