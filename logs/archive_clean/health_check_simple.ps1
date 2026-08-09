$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$watchdogRunning = $null -ne (Get-Process | Where-Object { $_.ProcessName -like '*watchdog*' } | Select-Object -First 1)
if ($watchdogRunning) { $status = 'RUNNING' } else { $status = 'NOT_RUNNING' }
Write-Output "[$timestamp] WATCHDOG_PROCESS: $status"
$masterLog = 'C:\ShadowKit\logs\shadowkit.jsonl'
$logExists = Test-Path $masterLog
$logSize = if ($logExists) { (Get-Item $masterLog).Length } else { 0 }
Write-Output "[$timestamp] MASTER_LOG: Exists=$logExists, Size=$logSize bytes"
$services = Get-Service | Where-Object { $_.Name -like '*shadow*' }
Write-Output "[$timestamp] SERVICES: Found $($services.Count) ShadowKit-related services"
$services | ForEach-Object { Write-Output "  - $($_.Name): $($_.Status)" }
$drive = Get-Item 'C:\'
$freeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
Write-Output "[$timestamp] DISK_SPACE: C: drive has $freeSpaceGB GB free"
$memory = Get-CimInstance Win32_OperatingSystem
$freeMemGB = [math]::Round($memory.FreePhysicalMemory / 1MB, 2)
Write-Output "[$timestamp] MEMORY: $freeMemGB GB free physical memory"
$reportPath = "C:\ShadowKit\logs\health_check_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$reportContent = @(
    "[$timestamp] WATCHDOG_PROCESS: $status",
    "[$timestamp] MASTER_LOG: Exists=$logExists, Size=$logSize bytes",
    "[$timestamp] SERVICES: Found $($services.Count) ShadowKit-related services",
    "[$timestamp] DISK_SPACE: C: drive has $freeSpaceGB GB free",
    "[$timestamp] MEMORY: $freeMemGB GB free physical memory"
)
$reportContent | Out-File -FilePath $reportPath -Encoding UTF8