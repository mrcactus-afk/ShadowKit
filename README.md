# ShadowKit v8.0

Windows tuning and automation suite. Runs a background controller, keeps core components alive, and gives you a WPF dashboard for control and monitoring.

## What it does

- Supervisor controller with process monitoring and restarts
- SystemCalibrator enforces services, registry, and power plan from profile
- MemoryCleaner purges standby list at 500 MB threshold
- DNSFrenzy picks fastest DNS and applies it
- TimerOptimizer locks timer resolution
- GameOptimizer one-shot with full snapshot/revert
- Tier1 optimizers: Network, FileSystem, Power, Debloat, GPU
- SecurityTweaker toggles VBS/HVCI and Defender exclusions with warnings
- ThermalManager monitors CPU temp and swaps power plans
- PowerContextSwitcher switches power plans on AC/battery
- EventMonitor logs status changes and thermal events
- Self-update from GitHub with rollback
- WPF dashboard with live graphs, settings editor, and all controls

## Install

Clone and run setup as admin:

```powershell
git clone https://github.com/mrcactus-afk/ShadowKit.git
cd ShadowKit
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup-ShadowKit.ps1
Quick start
Launch menu:

powershell
& C:\ShadowKit\Launch-ShadowKit.ps1
Dashboard:

powershell
& C:\ShadowKit\components\GUI-WPF.ps1
Validation:

powershell
& C:\ShadowKit\Validate-ShadowKit.ps1
Uninstall
powershell
& C:\ShadowKit\Uninstall-ShadowKit.ps1 -Force
Requirements
Windows 10/11

PowerShell 5.1+

Administrator privileges

Optional: Pester for tests

License
MIT

text