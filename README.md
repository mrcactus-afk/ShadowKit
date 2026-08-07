# ShadowKit v4 - Self-Healing Windows Automation Suite

ShadowKit is an enterprise-grade, self-healing daemon architecture for Windows 10/11, written in pure PowerShell. It supervises system state, enforces performance matrices, and prevents Windows Update from undoing your debloat and optimization tweaks.

## v4 Architecture Highlights

- **Runspace Plugin Loader:** The ShadowController scans for plugin.json manifests and launches components in isolated .NET Runspaces with stdout/stderr crash capture and exponential backoff.
- **Atomic IPC Status Bus:** Components publish their heartbeat and health to a mutex-guarded status.json using atomic Move-Item swaps.
- **WPF Telemetry Dashboard:** A hardware-accelerated, dark-themed XAML dashboard that renders live CPU charts and reads the IPC bus.
- **CTT Enforcement Matrix:** The SystemCalibrator enforces the Chris Titus Tech gaming meta (Memory Compression OFF, Mouse Accel OFF, HAGS ON, VBS OFF) every 30 minutes.
- **GameOptimizer:** A one-shot module that applies the Ultimate performance layer (CPU min 100%, USB suspend OFF, PCIe ASPM OFF).

## Core Components

| Component | Role |
|---|---|
| **Controller** | Mutex-guarded singleton daemon. Discovers plugins, manages runspaces. |
| **SystemCalibrator** | Declarative profile enforcement. Captures baseline, repairs drift. |
| **DNSFrenzy** | Event-driven DNS switcher via WMI. |
| **TimerOptimizer** | Locks 0.5ms system timer resolution. |
| **MemoryCleaner** | NTAPI standby list purge. |
| **GameOptimizer** | One-shot CTT gaming layer application. |
| **GUI-WPF** | Live telemetry dashboard. |

## Installation

1. Clone the repository: `git clone https://github.com/mrcactus-afk/ShadowKit.git`
2. Run `.\Setup-ShadowKit.ps1` as Administrator.
3. Customize `config.json` and `profile.json`.
4. Launch the controller: `.\ShadowController.ps1`
5. Launch the dashboard: `.\components\GUI-WPF.ps1`

## The Self-Healing Loop

Windows Update inevitably re-enables telemetry and resets power plans. ShadowKit's SystemCalibrator runs every 30 minutes and silently reverts any drift. Your system stays stripped and optimized forever.

## License

MIT License. See LICENSE for details.
