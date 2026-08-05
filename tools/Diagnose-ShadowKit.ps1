$ErrorActionPreference = "SilentlyContinue"
$Root = "C:\ShadowKit"
$LogDir = Join-Path $Root "logs"
$ReportPath = Join-Path $LogDir ("diagnostic_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
$report = New-Object System.Collections.Generic.List[string]
$report.Add("ShadowKit Diagnostic " + (Get-Date -Format "o"))

$report.Add("")
$report.Add("=== Scheduled Task ===")
$task = Get-ScheduledTask -TaskName "ShadowKitController" -ErrorAction SilentlyContinue
if ($task) { $report.Add("State: " + $task.State) } else { $report.Add("Not found") }

$report.Add("")
$report.Add("=== Processes ===")
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match "ShadowKit" } | ForEach-Object { $report.Add($_.CommandLine) }

$report.Add("")
$report.Add("=== Log Tails ===")
Get-ChildItem $LogDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | ForEach-Object {
    $report.Add("--- " + $_.Name + " ---")
    @(Get-Content $_.FullName -Tail 5) | ForEach-Object { $report.Add($_) }
}

$report | Out-File $ReportPath -Encoding UTF8
$report | Write-Output
