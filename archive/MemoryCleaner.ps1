param([switch]$Silent)
$configPath = "C:\ShadowKit\config.json"
$logDir = "C:\ShadowKit\logs"
$logFile = Join-Path $logDir "memory.log"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

. "C:\ShadowKit\components\ShadowLogger.ps1"

function Write-MemoryLog {
    param($Message, $Level = "info", $Data = @{})
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $entry | Out-File -Append $logFile
    Write-ShadowKitLog -Message $Message -Level $Level -Module "MemoryCleaner" -Data $Data
    if (-not $Silent) {
        if ($Level -eq "error") { Write-Host $entry -ForegroundColor Red }
        else { Write-Host $entry -ForegroundColor Cyan }
    }
}

if (-not (Test-Path $configPath)) { Write-MemoryLog "Config missing" "error"; exit 1 }
$config = Get-Content $configPath | ConvertFrom-Json
$memConfig = $config.memory

if (-not $memConfig.enabled) {
    Write-MemoryLog "MemoryCleaner disabled in config. Exiting." "warn"
    exit 0
}

$interval = $memConfig.intervalMinutes
$standbyThresholdMB = 1024

$csharp = @"
using System;
using System.Runtime.InteropServices;

public class CacheCleaner {
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool SetSystemFileCacheSize(long MinimumFileCacheSize, long MaximumFileCacheSize, uint Flags);

    [DllImport("ntdll.dll", SetLastError=true)]
    private static extern int NtSetSystemInformation(int SystemInformationClass, IntPtr SystemInformation, int SystemInformationLength);

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError=true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint TOKEN_QUERY = 0x0008;
    private const uint SE_PRIVILEGE_ENABLED = 0x2;
    private const int SystemMemoryListInformation = 80;
    private const int MemoryPurgeStandbyList = 4;

    [StructLayout(LayoutKind.Sequential, Pack=1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public long Luid;
        public uint Attributes;
    }

    public static bool EnablePrivilege(string privilegeName) {
        IntPtr tokenHandle;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tokenHandle)) return false;
        long luid;
        if (!LookupPrivilegeValue(null, privilegeName, out luid)) return false;
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Luid = luid;
        tp.Attributes = SE_PRIVILEGE_ENABLED;
        bool result = AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        return result && err == 0;
    }

    public static bool PurgeWithSetSystemFileCacheSize() {
        return SetSystemFileCacheSize(-1, -1, 0);
    }

    public static int PurgeWithNtSetSystemInformation() {
        int cmd = MemoryPurgeStandbyList;
        IntPtr ptr = Marshal.AllocHGlobal(sizeof(int));
        Marshal.WriteInt32(ptr, cmd);
        int status = NtSetSystemInformation(SystemMemoryListInformation, ptr, sizeof(int));
        Marshal.FreeHGlobal(ptr);
        return status;
    }
}
"@
try { Add-Type -TypeDefinition $csharp -ErrorAction Stop } catch { Write-MemoryLog "C# compile failed: $_" "error"; exit 1 }

[CacheCleaner]::EnablePrivilege("SeIncreaseQuotaPrivilege") | Out-Null
[CacheCleaner]::EnablePrivilege("SeProfileSingleProcessPrivilege") | Out-Null

function Get-StandbyMB {
    try {
        $c = Get-Counter "\Memory\Standby Cache Reserve Bytes" -ErrorAction Stop
        return [math]::Round($c.CounterSamples[0].CookedValue / 1MB, 1)
    } catch {
        return $null
    }
}

function PurgeWithRetry {
    param([int]$MaxAttempts = 3)

    for ($i=0; $i -lt $MaxAttempts; $i++) {
        $status = [CacheCleaner]::PurgeWithNtSetSystemInformation()
        if ($status -eq 0) {
            Write-MemoryLog "Purge succeeded using NtSetSystemInformation (attempt $($i+1))."
            return $true
        } else {
            $ntHex = "0x" + $status.ToString("X8")
            Write-MemoryLog "NtSetSystemInformation attempt $($i+1) failed with NTSTATUS $ntHex." "warn" @{ ntstatus = $ntHex; attempt = ($i + 1) }
            Start-Sleep -Seconds 1
        }
    }

    if ([CacheCleaner]::PurgeWithSetSystemFileCacheSize()) {
        Write-MemoryLog "Purge succeeded using SetSystemFileCacheSize fallback."
        return $true
    }

    Write-MemoryLog "All purge methods failed." "error"
    return $false
}

Write-MemoryLog "MemoryCleaner started (interval: ${interval}min) – NtSetSystemInformation primary"

while ($true) {
    $standby = Get-StandbyMB
    if ($standby -ne $null) {
        if ($standby -gt $standbyThresholdMB) {
            Write-MemoryLog "Standby: $standby MB – purging..."
            PurgeWithRetry | Out-Null
        } else {
            Write-MemoryLog "Standby: $standby MB – below threshold, skipping."
        }
    } else {
        Write-MemoryLog "Could not read standby list size." "warn"
    }
    Start-Sleep -Seconds ($interval * 60)
}

