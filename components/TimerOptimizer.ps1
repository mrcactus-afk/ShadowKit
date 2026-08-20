param([switch]$Silent)
$ErrorActionPreference = 'Stop'
$baseDir = 'C:\ShadowKit'
Import-Module (Join-Path $baseDir 'modules\ShadowIPC.psm1') -Force

$csharp = @"
using System;
using System.Runtime.InteropServices;
public class TimerRes {
    [DllImport("ntdll.dll")] public static extern int NtSetTimerResolution(uint d, bool s, out uint c);
    [DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint min, out uint max, out uint cur);
}
"@
Add-Type -TypeDefinition $csharp -ErrorAction SilentlyContinue

Set-ShadowStatus -Component 'TimerOptimizer' -Status 'Running'
while ($true) {
    try {
        $min=[uint32]0; $max=[uint32]0; $cur=[uint32]0
        [TimerRes]::NtQueryTimerResolution([ref]$min, [ref]$max, [ref]$cur) | Out-Null
        if ($cur -eq 0) { $cur = 5000 }
        if ($min -eq 0) { $min = 5000 }
        [TimerRes]::NtSetTimerResolution($min, $true, [ref]$cur) | Out-Null
        Set-ShadowStatus -Component 'TimerOptimizer' -Status 'Running' -Data @{
            resolutionMs = [math]::Round($cur/10000.0,3)
            minResolutionMs = [math]::Round($min/10000.0,3)
        }
    } catch { }
    Start-Sleep -Seconds 30
}
