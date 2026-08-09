Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. "C:\\ShadowKit\\components\\ShadowIPC.ps1"`n. "C:\\ShadowKit\\components\\ShadowAlert.ps1"

# DPI Awareness (Windows 10/11)
if ([Environment]::OSVersion.Version.Major -ge 10) {
    $sig = '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(int dpiFlag);'
    $type = Add-Type -MemberDefinition $sig -Name "Win32Utils" -Namespace "Win32" -PassThru
    $type::SetProcessDpiAwarenessContext(-4) | Out-Null
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ShadowKit v4 Control Center" Height="650" Width="850"
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
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="150"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>`n        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="SHADOWKIT v4 CONTROL CENTER" FontSize="22" FontWeight="Bold" Foreground="#007ACC" Margin="0,0,0,15"/>

        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="CPU: " FontSize="14"/>
            <TextBlock x:Name="CpuText" Text="0%" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
            <TextBlock Text="   |   RAM: " FontSize="14"/>
            <TextBlock x:Name="RamText" Text="0 MB" FontSize="14" FontWeight="Bold" Foreground="#4EC9B0"/>
            <TextBlock Text="   |   Controller: " FontSize="14"/>
            <TextBlock x:Name="CtrlText" Text="Offline" FontSize="14" FontWeight="Bold" Foreground="#D16969"/>
        </StackPanel>

        <Border Grid.Row="2" Background="#252526" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="4" Margin="0,0,0,15">
            <Canvas x:Name="ChartCanvas" ClipToBounds="True"/>
        </Border>

        <Border Grid.Row="3" Background="#252526" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="4" Margin="0,0,0,15">
            <TextBox x:Name="StatusBoard" Background="#252526" Foreground="#F1F1F1" BorderThickness="0" 
                     FontFamily="Consolas" FontSize="13" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                     Text="Waiting for component telemetry..."/>
        </Border>

        <Border Grid.Row="4" Background="#2D2D30" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="4" Margin="0,0,0,10"><ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="120"><StackPanel x:Name="AlertPanel" Margin="10"><TextBlock Text="No alerts" Foreground="#808080" FontSize="12" FontFamily="Consolas"/></StackPanel></ScrollViewer></Border><StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="OpenConfigBtn" Content="Open Config"/>
            <Button x:Name="ViewLogsBtn" Content="View Logs"/>
            <Button x:Name="RestartBtn" Content="Restart Controller"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$cpuText = $window.FindName("CpuText")
$ramText = $window.FindName("RamText")
$ctrlText = $window.FindName("CtrlText")
$chartCanvas = $window.FindName("ChartCanvas")
$statusBoard = $window.FindName("StatusBoard")
$openConfigBtn = $window.FindName("OpenConfigBtn")
$viewLogsBtn = $window.FindName("ViewLogsBtn")
$restartBtn = $window.FindName("RestartBtn")

# Zero-lag Performance Counters
$script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
$script:cpuCounter.NextValue() | Out-Null

# Chart Setup
$script:points = New-Object System.Windows.Media.PointCollection
$polyline = New-Object System.Windows.Shapes.Polyline
$polyline.Stroke = [System.Windows.Media.Brushes]::GreenYellow
$polyline.StrokeThickness = 2
$polyline.Points = $script:points
$chartCanvas.Children.Add($polyline) | Out-Null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)

$timer.Add_Tick({
    # 1. Hardware Metrics
    $cpu = [math]::Round($script:cpuCounter.NextValue(), 0)
    $cpuText.Text = "$cpu%"
    
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $ramUsedMB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1KB, 0)
        $ramText.Text = "$ramUsedMB MB"
    }

    # 2. IPC Telemetry Board
    $allStatus = Get-ShadowStatus
    $ctrlStatus = "Offline"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("SHADOWKIT COMPONENT TELEMETRY (Live via status.json)")
    [void]$sb.AppendLine("=======================================================")
    
    if ($allStatus) {
        foreach ($prop in $allStatus.PSObject.Properties) {
            $name = $prop.Name
            $data = $prop.Value
            $status = $data.status
            $updated = $data.updated
            if ($null -eq $updated) { $updated = "N/A" }
            
            $icon = if ($status -match "Running|Applied|Enforcing") { "[OK]" } else { "[!!]" }
            [void]$sb.AppendLine("$icon $($name.PadRight(22)) | Status: $($status.PadRight(15)) | $updated")
        }
        if ($allStatus.Controller) { $ctrlStatus = $allStatus.Controller.status }
    } else {
        [void]$sb.AppendLine("Waiting for telemetry... Start ShadowController.ps1 first.")
    }
    
    $StatusBoard.Text = $sb.ToString()
    $ctrlText.Text = $ctrlStatus
    $ctrlText.Foreground = if ($ctrlStatus -match "Running") { [System.Windows.Media.Brushes]::GreenYellow } else { [System.Windows.Media.Brushes]::Tomato }

    # 3. Chart Logic
    $canvasWidth = $chartCanvas.ActualWidth
    $canvasHeight = $chartCanvas.ActualHeight
    if ($canvasWidth -gt 0 -and $canvasHeight -gt 0) {
        if ($script:points.Count -gt 60) { $script:points.RemoveAt(0) }
        for ($i = 0; $i -lt $script:points.Count; $i++) {
            $x = ($canvasWidth / 60) * $i
            $script:points[$i] = New-Object System.Windows.Point($x, $script:points[$i].Y)
        }
        $y = $canvasHeight - (($cpu / 100) * $canvasHeight)
        $script:points.Add((New-Object System.Windows.Point($canvasWidth, $y)))
    }
    # 4. Alert Panel
    $AlertPanel.Children.Clear()
    $alerts = Get-ShadowAlerts -UnacknowledgedOnly -Limit 10
    if ($alerts.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "No active alerts"
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        $tb.FontSize = 12
        $tb.FontFamily = "Consolas"
        $AlertPanel.Children.Add($tb) | Out-Null
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
            $AlertPanel.Children.Add($border) | Out-Null
        }
    }
})

$openConfigBtn.Add_Click({ Start-Process notepad "C:\ShadowKit\config.json" })
$viewLogsBtn.Add_Click({ Start-Process notepad "C:\ShadowKit\logs\shadowkit.jsonl" })
$restartBtn.Add_Click({ 
    $result = [System.Windows.MessageBox]::Show("Restart ShadowKit controller?", "Confirm", "YesNo", "Question")
    if ($result -eq "Yes") { Start-Process powershell "-File C:\ShadowKit\ShadowController.ps1 -WindowStyle Hidden" }
})

$timer.Start()
$window.ShowDialog() | Out-Null

