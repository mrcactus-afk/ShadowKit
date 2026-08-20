Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ShadowKit v8.0 Control Center" Height="650" Width="950"
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

function Update-All {
    $status = Get-ShadowStatus
    if (-not $status) { $summaryBox.Text = 'No status file found.'; return }
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

    # Per-component details
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
}

$refreshAllBtn.Add_Click({ Update-All })
$purgeBtn.Add_Click({
    Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
    try { $resp = Send-ShadowCommand -Action 'purge' -Payload @{ component = 'MemoryCleaner' }; [System.Windows.MessageBox]::Show($resp.result, 'Purge') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Purge Error') }
})
$refreshDnsBtn.Add_Click({
    Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
    try { $resp = Send-ShadowCommand -Action 'refresh' -Payload @{ component = 'DNSFrenzy' }; [System.Windows.MessageBox]::Show($resp.result, 'DNS Refresh') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'DNS Error') }
})
$calibBtn.Add_Click({
    Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force
    try { $resp = Send-ShadowCommand -Action 'enforce' -Payload @{ component = 'SystemCalibrator' }; [System.Windows.MessageBox]::Show($resp.result, 'Enforcement') } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, 'Enforcement Error') }
})
$applyGameBtn.Add_Click({
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GameOptimizer.ps1`" -Apply"
    [System.Windows.MessageBox]::Show('GameOptimizer apply started.','GameOptimizer')
})
$revertGameBtn.Add_Click({
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$baseDir\components\GameOptimizer.ps1`" -Revert"
    [System.Windows.MessageBox]::Show('GameOptimizer revert started.','GameOptimizer')
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Update-All })
$timer.Start()
Update-All
$window.ShowDialog() | Out-Null

