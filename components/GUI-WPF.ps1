# =====================================================================
# FILE: components\GUI-WPF.ps1 (v2.2 – self-contained, no missing functions)
# Replace C:\ShadowKit\components\GUI-WPF.ps1 with this version.
# It does not depend on Format-ComponentDetails or Send-ShadowCommand being in ShadowIPC.
# =====================================================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. "C:\ShadowKit\components\ShadowIPC.ps1" -ErrorAction SilentlyContinue
. "C:\ShadowKit\components\ShadowAlert.ps1" -ErrorAction SilentlyContinue

# Fallback functions if not defined in ShadowIPC
if (-not (Get-Command Format-ComponentDetails -ErrorAction SilentlyContinue)) {
    function Format-ComponentDetails {
        param($ComponentName, $Data)
        $out = ""
        switch ($ComponentName) {
            "DNSFrenzy" {
                $out += "Primary DNS: $($Data.primaryDNS)`n"
                $out += "Secondary: $($Data.secondaryDNS)`n"
                $out += "Last latency test: $($Data.lastLatency) ms`n"
                $out += "Server list count: $($Data.serverCount)"
            }
            "TimerOptimizer" {
                $out += "Current resolution: $($Data.resolutionMs) ms`n"
                $out += "Minimum supported: $($Data.minResolutionMs) ms"
            }
            "MemoryCleaner" {
                $out += "Standby list size: $($Data.standbyMB) MB`n"
                $out += "Last purge: $($Data.lastPurgeTime)`n"
                $out += "Purge status: $($Data.purgeStatus)"
            }
            "SystemCalibrator" {
                $out += "Last drift count: $($Data.LastDrift)`n"
                $out += "Active entries: $($Data.Entries)`n"
                $out += "Last enforced: $($Data.Time)"
            }
            "GameOptimizer" {
                $out += "Applied: $(if ($Data.RebootRequired) { 'Reboot required' } else { 'No reboot needed' })`n"
                $out += "State saved: $($Data.StateFile)"
            }
            default {
                $out = ($Data | Format-List -Property * | Out-String).Trim()
            }
        }
        return $out
    }
}

if (-not (Get-Command Send-ShadowCommand -ErrorAction SilentlyContinue)) {
    function Send-ShadowCommand {
        param($Command, [int]$TimeoutMs = 5000)
        # Use the same pipe name as defined in ShadowIPC.ps1
        $pipeName = "ShadowKit-Control"
        try {
            $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect($TimeoutMs)
            $writer = New-Object System.IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $writer.WriteLine($Command)
            $reader = New-Object System.IO.StreamReader($pipe)
            $response = $reader.ReadLine()
            $pipe.Close(); $pipe.Dispose()
            return $response | ConvertFrom-Json
        } catch {
            return @{ error = $_.Exception.Message; success = $false }
        }
    }
}

# DPI Awareness
if ([Environment]::OSVersion.Version.Major -ge 10) {
    $sig = '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(int dpiFlag);'
    $type = Add-Type -MemberDefinition $sig -Name "Win32Utils" -Namespace "Win32" -PassThru
    $type::SetProcessDpiAwarenessContext(-4) | Out-Null
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ShadowKit Control Center" Height="700" Width="950"
        Background="#1E1E1E" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#F1F1F1" />
            <Setter Property="FontFamily" Value="Segoe UI" />
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#007ACC"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="SHADOWKIT v7.1 CONTROL CENTER" FontSize="20" FontWeight="Bold" Foreground="#007ACC" Margin="0,0,0,10"/>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="CPU: " FontSize="14"/>
            <TextBlock x:Name="CpuText" Text="0%" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
            <TextBlock Text="   RAM: " FontSize="14"/>
            <TextBlock x:Name="RamText" Text="0 MB" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
            <TextBlock Text="   Controller: " FontSize="14"/>
            <TextBlock x:Name="CtrlText" Text="Offline" FontSize="14" FontWeight="Bold" Foreground="#D16969"/>
        </StackPanel>

        <TabControl Grid.Row="2" Margin="0,0,0,10" Background="#2D2D30" BorderThickness="1" BorderBrush="#3F3F46">
            <TabItem Header="Summary" Background="#252526">
                <TextBox x:Name="StatusBoard" Background="#252526" Foreground="#F1F1F1" BorderThickness="0"
                         FontFamily="Consolas" FontSize="13" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                         Text="Waiting for telemetry..."/>
            </TabItem>
            <TabItem Header="MemoryCleaner" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="MemoryCleaner Controls" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Standby List: " FontSize="14"/>
                        <TextBlock x:Name="StandbyText" Text="N/A" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Last Purge: " FontSize="14"/>
                        <TextBlock x:Name="PurgeTimeText" Text="Never" FontSize="14" Foreground="#FFAA00"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Purge Status: " FontSize="14"/>
                        <TextBlock x:Name="PurgeStatusText" Text="Idle" FontSize="14" Foreground="#888888"/>
                    </StackPanel>
                    <Button x:Name="PurgeButton" Content="Purge Standby List Now" Width="200" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="DNSFrenzy" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="DNS Status" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
                    <TextBlock x:Name="DnsPrimaryText" Text="Primary: N/A" FontSize="14"/>
                    <TextBlock x:Name="DnsSecondaryText" Text="Secondary: N/A" FontSize="14"/>
                    <TextBlock x:Name="DnsLatencyText" Text="Last latency: N/A" FontSize="14"/>
                    <Button x:Name="RefreshDnsButton" Content="Refresh DNS Servers" Width="180" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="TimerOptimizer" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="Timer Resolution" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
                    <TextBlock x:Name="TimerResText" Text="Current: N/A" FontSize="14"/>
                    <TextBlock x:Name="TimerMinText" Text="Minimum: N/A" FontSize="14"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="SystemCalibrator" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="System Calibrator" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
                    <TextBlock x:Name="CalibDriftText" Text="Last Drift: N/A" FontSize="14"/>
                    <TextBlock x:Name="CalibEntriesText" Text="Active Entries: N/A" FontSize="14"/>
                    <Button x:Name="CalibButton" Content="Run Enforcement Now" Width="180" HorizontalAlignment="Left" Margin="0,10,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="GameOptimizer" Background="#252526">
                <StackPanel Margin="10">
                    <TextBlock Text="GameOptimizer" FontSize="16" FontWeight="Bold" Margin="0,0,0,10"/>
                    <TextBlock x:Name="GameStatusText" Text="Status: N/A" FontSize="14"/>
                    <TextBlock x:Name="GameRebootText" Text="Reboot required: N/A" FontSize="14"/>
                </StackPanel>
            </TabItem>
        </TabControl>

        <Border Grid.Row="3" Background="#2D2D30" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="4" Margin="0,0,0,10">
            <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="100">
                <StackPanel x:Name="AlertPanel" Margin="10">
                    <TextBlock Text="No alerts" Foreground="#808080" FontSize="12" FontFamily="Consolas"/>
                </StackPanel>
            </ScrollViewer>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Find controls
$cpuText = $window.FindName("CpuText")
$ramText = $window.FindName("RamText")
$ctrlText = $window.FindName("CtrlText")
$statusBoard = $window.FindName("StatusBoard")
$standbyText = $window.FindName("StandbyText")
$purgeTimeText = $window.FindName("PurgeTimeText")
$purgeStatusText = $window.FindName("PurgeStatusText")
$purgeButton = $window.FindName("PurgeButton")
$dnsPrimaryText = $window.FindName("DnsPrimaryText")
$dnsSecondaryText = $window.FindName("DnsSecondaryText")
$dnsLatencyText = $window.FindName("DnsLatencyText")
$refreshDnsButton = $window.FindName("RefreshDnsButton")
$timerResText = $window.FindName("TimerResText")
$timerMinText = $window.FindName("TimerMinText")
$calibDriftText = $window.FindName("CalibDriftText")
$calibEntriesText = $window.FindName("CalibEntriesText")
$calibButton = $window.FindName("CalibButton")
$gameStatusText = $window.FindName("GameStatusText")
$gameRebootText = $window.FindName("GameRebootText")
$alertPanel = $window.FindName("AlertPanel")

# Performance counters
$script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
$script:cpuCounter.NextValue() | Out-Null

# Dispatcher timer
$dispatchTimer = New-Object System.Windows.Threading.DispatcherTimer
$dispatchTimer.Interval = [TimeSpan]::FromSeconds(2)

$dispatchTimer.Add_Tick({
    # CPU & RAM
    $cpu = [math]::Round($script:cpuCounter.NextValue(), 0)
    $cpuText.Text = "$cpu%"
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB, 0)
        $ramText.Text = "$ramUsedMB MB"
    }

    # Component status
    $allStatus = Get-ShadowStatus
    $ctrlStatus = "Offline"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("SHADOWKIT COMPONENT TELEMETRY")
    [void]$sb.AppendLine("=================================")

    if ($allStatus) {
        foreach ($prop in $allStatus.PSObject.Properties) {
            $name = $prop.Name
            $data = $prop.Value
            $status = $data.status
            $updated = $data.updated
            $procId = $data.pid   # changed from $pid to $procId to avoid read-only variable
            $detail = Format-ComponentDetails -ComponentName $name -Data $data.data
            [void]$sb.AppendLine("$name ($procId): $status")
            if ($detail) { [void]$sb.AppendLine("  $detail") }
        }
        if ($allStatus.Controller) { $ctrlStatus = $allStatus.Controller.status }
    } else {
        [void]$sb.AppendLine("No telemetry yet – waiting for controller...")
    }
    $StatusBoard.Text = $sb.ToString()
    $ctrlText.Text = $ctrlStatus
    $ctrlText.Foreground = if ($ctrlStatus -match "Running") { [System.Windows.Media.Brushes]::GreenYellow } else { [System.Windows.Media.Brushes]::Tomato }

    # MemoryCleaner details
    $mcData = if ($allStatus -and $allStatus.MemoryCleaner) { $allStatus.MemoryCleaner.data } else { $null }
    if ($mcData) {
        $standby = if ($mcData.standbyMB -ne $null) { "$($mcData.standbyMB) MB" } else { "N/A" }
        $standbyText.Text = $standby
        $lastPurge = if ($mcData.lastPurge) { $mcData.lastPurge } else { "Never" }
        $purgeTimeText.Text = $lastPurge
        $purgeStatus = if ($mcData.purgeStatus) { $mcData.purgeStatus } else { "Idle" }
        $purgeStatusText.Text = $purgeStatus
        $purgeStatusText.Foreground = if ($purgeStatus -eq "Success") { [System.Windows.Media.Brushes]::GreenYellow } else { [System.Windows.Media.Brushes]::Gray }
    }

    # DNSFrenzy details
    $dnsData = if ($allStatus -and $allStatus.DNSFrenzy) { $allStatus.DNSFrenzy.data } else { $null }
    if ($dnsData) {
        $dnsPrimaryText.Text = "Primary: $(if ($dnsData.primaryDNS) { $dnsData.primaryDNS } else { 'N/A' })"
        $dnsSecondaryText.Text = "Secondary: $(if ($dnsData.secondaryDNS) { $dnsData.secondaryDNS } else { 'N/A' })"
        $dnsLatencyText.Text = "Last latency: $(if ($dnsData.lastLatency) { "$($dnsData.lastLatency) ms" } else { 'N/A' })"
    }

    # TimerOptimizer details
    $timerData = if ($allStatus -and $allStatus.TimerOptimizer) { $allStatus.TimerOptimizer.data } else { $null }
    if ($timerData) {
        $timerResText.Text = "Current: $(if ($timerData.resolutionMs) { "$($timerData.resolutionMs) ms" } else { 'N/A' })"
        $timerMinText.Text = "Minimum: $(if ($timerData.minResolutionMs) { "$($timerData.minResolutionMs) ms" } else { 'N/A' })"
    }

    # SystemCalibrator details
    $calData = if ($allStatus -and $allStatus.SystemCalibrator) { $allStatus.SystemCalibrator.data } else { $null }
    if ($calData) {
        $calibDriftText.Text = "Last Drift: $(if ($calData.LastDrift -ne $null) { $calData.LastDrift } else { 'N/A' })"
        $calibEntriesText.Text = "Active Entries: $(if ($calData.Entries -ne $null) { $calData.Entries } else { 'N/A' })"
    }

    # GameOptimizer details
    $gameStatus = if ($allStatus -and $allStatus.GameOptimizer) { $allStatus.GameOptimizer } else { $null }
    if ($gameStatus) {
        $gameStatusText.Text = "Status: $($gameStatus.status)"
        $reboot = if ($gameStatus.data -and $gameStatus.data.RebootRequired) { "Yes" } else { "No" }
        $gameRebootText.Text = "Reboot required: $reboot"
    }

    # Alerts
    $alertPanel.Children.Clear()
    $alerts = Get-ShadowAlerts -UnacknowledgedOnly -Limit 10
    if ($alerts.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "No active alerts"
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        $tb.FontSize = 12
        $tb.FontFamily = "Consolas"
        $alertPanel.Children.Add($tb)
    } else {
        foreach ($a in $alerts) {
            $border = New-Object System.Windows.Controls.Border
            $border.BorderThickness = [System.Windows.Thickness]::new(0,0,0,1)
            $border.BorderBrush = [System.Windows.Media.Brushes]::DarkGray
            $border.Padding = [System.Windows.Thickness]::new(0,2,0,4)
            $border.Margin = [System.Windows.Thickness]::new(0,0,0,2)
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "[$($a.level.ToUpper())] [$($a.component)] $($a.message)"
            $tb.Foreground = if ($a.level -eq "error") { [System.Windows.Media.Brushes]::Tomato } else { [System.Windows.Media.Brushes]::Gold }
            $tb.FontSize = 11
            $tb.FontFamily = "Consolas"
            $tb.TextWrapping = "Wrap"
            $border.Child = $tb
            $alertPanel.Children.Add($border)
        }
    }
})

# Button events
$purgeButton.Add_Click({
    $purgeButton.IsEnabled = $false
    $purgeButton.Content = "Purging..."
    try {
        $result = Send-ShadowCommand -Command '{"action":"purge","component":"MemoryCleaner"}'
        if ($result.success) {
            [System.Windows.MessageBox]::Show("Purge completed. Freed $($result.freedMB) MB.", "Success")
            $purgeStatusText.Text = "Success"
            $purgeStatusText.Foreground = [System.Windows.Media.Brushes]::GreenYellow
        } else {
            [System.Windows.MessageBox]::Show("Purge failed: $($result.error)", "Error", "OK", "Error")
            $purgeStatusText.Text = "Failed"
            $purgeStatusText.Foreground = [System.Windows.Media.Brushes]::Red
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error: $_", "Error", "OK", "Error")
    } finally {
        $purgeButton.IsEnabled = $true
        $purgeButton.Content = "Purge Standby List Now"
    }
})

$refreshDnsButton.Add_Click({
    $result = Send-ShadowCommand -Command '{"action":"refresh","component":"DNSFrenzy"}'
    if ($result.success) {
        [System.Windows.MessageBox]::Show("DNS refresh triggered.", "Success")
    } else {
        [System.Windows.MessageBox]::Show("Failed: $($result.error)", "Error", "OK", "Error")
    }
})

$calibButton.Add_Click({
    $result = Send-ShadowCommand -Command '{"action":"enforce","component":"SystemCalibrator"}'
    if ($result.success) {
        [System.Windows.MessageBox]::Show("Calibration triggered.", "Success")
    } else {
        [System.Windows.MessageBox]::Show("Failed: $($result.error)", "Error", "OK", "Error")
    }
})

$dispatchTimer.Start()
$window.ShowDialog() | Out-Null