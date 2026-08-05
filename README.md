# ShadowKit – Windows Automation Suite (v3.0)

ShadowKit is a self-healing automation system for Windows 10/11. It supervises DNS selection, timer resolution, standby memory purging, and system integrity, with a GUI dashboard and error-only alerting.

## Features

- **Singleton Controller** – global mutex prevents duplicate instances; handle-safe process supervision with restart throttling.
- **DNS Switcher** – parallel runspace latency probing; loss-penalized scoring; TUN/tunnel/VPN adapters excluded; Iran-optimised server list.
- **Timer Optimizer** – enforces 0.5 ms system timer resolution; verified live via NtQueryTimerResolution.
- **Memory Cleaner** – purges standby list via NtSetSystemInformation (SystemMemoryListInformation) with correct privileges; NTSTATUS logged on failure.
- **Watchdog** – live CIM process-state integrity checks; double-query WMI reads; detached self-repair.
- **GUI v2.2** – async runspace performance monitor; accurate controller status; atomic config writes.
- **Error Popup** – alerts on [error] only; clock-skew guard discards future-dated entries.
- **Self-starting** – scheduled task at boot with MultipleInstances IgnoreNew.
- **Log Rotation** – archives logs over 5 MB.

## Installation

1. Run `Setup-ShadowKit.ps1` as Administrator.
2. Customise `config.json` and `servers.json`.
3. Launch the dashboard via `Launch-GUI.bat`.

## Tooling

- `tools\AIO-CleanRestart.ps1` – kill all generations, single clean start, singleton verification.
- `tools\AIO-Audit.ps1` – full health audit (processes, task, live timer, live DNS, log activity, fresh errors).
- `tools\Diagnose-ShadowKit.ps1` – state extraction report.

## Known Issues

- Windows time sync disabled by external debloat causes cross-session timestamp skew; popup guard compensates.
- TimerOptimizer hardening rewrite (runtime bounds re-validation) not deployed; current build verified functional.
- GUI must run in the interactive session; popups cannot render from SYSTEM.

## License

MIT

