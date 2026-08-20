# ShadowKit v8.0

Powerful Windows automation suite for gamers, power users, and anyone who wants a cleaner, faster, more responsive machine without extra junk or unnecessary bloat.

ShadowKit runs as a background controller with a supervisor process model, isolated components, a simple file-based command bus, and a WPF dashboard for telemetry and manual controls.

## Features

- Supervisor Controller — singleton mutex, process monitoring, exponential backoff restarts, and hidden-window operation
- SystemCalibrator — enforces registry, service, and power-plan entries from a JSON profile with snapshot/revert and optional restore point
- MemoryCleaner — standby list purge via NTAPI with a performance-counter fallback
- DNSFrenzy — latency-based DNS server selection, RFC1918 filtering, optional DNS mixing, and updateURL support
- TimerOptimizer — kernel timer resolution lock via NTAPI
- GameOptimizer — one-shot gaming tweaks with full snapshot/revert (may enable HAGS; see notes)
- WPF Dashboard — tabbed telemetry and manual controls for purge, DNS refresh, calibration, and GameOptimizer
- Command Bus — file-based queue with mutex synchronization for dashboard actions
- Log Rotation — controller rotates logs larger than 5 MB into `logs/archive`

## Installation

Clone the repository to a temporary folder and run the setup script as Administrator:

```powershell
git clone https://github.com/mrcactus-afk/ShadowKit.git
cd ShadowKit
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Setup-ShadowKit.ps1
```

The setup script will:

1. Copy files to `C:\ShadowKit`
2. Harden ACLs so only SYSTEM and Administrators have access
3. Register the `ShadowKitController` scheduled task to run at boot
4. Start the controller

## Quick start

Launch the text UI:

```powershell
& C:\ShadowKit\Launch-ShadowKit.ps1
```

Or start the controller and open the WPF dashboard manually:

```powershell
Start-ScheduledTask -TaskName ShadowKitController
& C:\ShadowKit\components\GUI-WPF.ps1
```

## Validation

Run the validation script to check required files, scheduled task, component status, and process counts:

```powershell
& C:\ShadowKit\Validate-ShadowKit.ps1
```

## Uninstall

Run the safe uninstaller as Administrator:

```powershell
& C:\ShadowKit\Uninstall-ShadowKit.ps1 -Force
```

This will attempt to restore system state, remove scheduled tasks, stop any running components, and remove the installation folder.

## File layout

```
C:\ShadowKit\
├── ShadowController.ps1        # Supervisor daemon
├── Watchdog.ps1                # Optional separate watchdog
├── Uninstall-ShadowKit.ps1     # Safe uninstaller
├── Validate-ShadowKit.ps1      # Validation script
├── Launch-ShadowKit.ps1        # TUI launcher
├── config.json                 # Main config
├── modules\
│   └── ShadowIPC.psm1          # Status + command bus
├── components\
│   ├── SystemCalibrator.ps1
│   ├── MemoryCleaner.ps1
│   ├── DNSFrenzy.ps1
│   ├── TimerOptimizer.ps1
│   ├── GameOptimizer.ps1
│   └── GUI-WPF.ps1
├── config\
│   ├── profile.json            # Calibration profile
│   └── servers.json            # DNS server list
├── state\                      # Runtime state (gitignored)
├── logs\                       # Runtime logs (gitignored)
└── tests\                      # Basic tests and runner
```

## Requirements

- Windows 10 or 11
- PowerShell 5.1+
- Administrator privileges for installation and some operations
- Optional: Pester for running the test suite

## Notes

- MemoryCleaner manual purge requires SYSTEM privileges — use the dashboard or the command bus rather than running the purge directly from an admin console when possible.
- GameOptimizer may enable Hardware-Accelerated GPU Scheduling (HAGS). If you see driver instability after enabling it, revert the change using the snapshot/revert tools.
- DNSFrenzy filters RFC1918 private IPs by default. If you use a local DNS server intentionally, add it to `config/servers.json` and adjust `dnsMix` in the main config.

## License

MIT
