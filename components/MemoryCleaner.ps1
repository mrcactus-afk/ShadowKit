param([switch]$Silent, [switch]$ManualPurge)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

$csharp = @"
using System;
using System.Runtime.InteropServices;
public class CacheCleaner {
    [DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int classId, IntPtr ptr, int len);
    public static int PurgeStandby() {
        int cmd = 4;
        IntPtr p = Marshal.AllocHGlobal(4);
        Marshal.WriteInt32(p, cmd);
        int status = NtSetSystemInformation(80, p, 4);
        Marshal.FreeHGlobal(p);
        return status;
    }
}
"@
Add-Type -TypeDefinition $csharp -ErrorAction SilentlyContinue

function Get-StandbyBytes {
    try {
        $counter = Get-Counter '\Memory\Standby Cache Reserve Bytes' -ErrorAction Stop
        return $counter.CounterSamples[0].CookedValue
    } catch {
        try {
            $mem = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
            return [int64]$mem.StandbyCacheReserveBytes
        } catch {
            return 0
        }
    }
}

if ($ManualPurge) {
    $standbyBytes = Get-StandbyBytes
    $standbyMB = [math]::Round($standbyBytes / 1MB, 1)
    $status = [CacheCleaner]::PurgeStandby()
    if ($status -eq 0) {
        Set-ShadowStatus -Component 'MemoryCleaner' -Status 'Purged' -Data @{ standbyMB=$standbyMB; purgeStatus='Success'; lastPurge=(Get-Date).ToString('o') }
    } else {
        Set-ShadowStatus -Component 'MemoryCleaner' -Status 'Failed' -Data @{ standbyMB=$standbyMB; purgeStatus="Failed NTSTATUS $status" }
    }
    exit 0
}

Set-ShadowStatus -Component 'MemoryCleaner' -Status 'Running' -Data @{ standbyMB = 0; purgeStatus = 'Idle' }
while ($true) {
    $standbyBytes = Get-StandbyBytes
    $standbyMB = [math]::Round($standbyBytes / 1MB, 1)
    $purgeStatus = 'Idle'
    $lastPurge = $null
    if ($standbyBytes -ge 500MB) {
        $status = [CacheCleaner]::PurgeStandby()
        if ($status -eq 0) {
            $purgeStatus = 'Success'
            $lastPurge = (Get-Date).ToString('o')
        } else {
            $purgeStatus = "Failed (NTSTATUS $status)"
        }
    }
    Set-ShadowStatus -Component 'MemoryCleaner' -Status 'Running' -Data @{
        standbyMB   = $standbyMB
        lastPurge   = $lastPurge
        purgeStatus = $purgeStatus
    }
    Start-Sleep -Seconds 300
}


