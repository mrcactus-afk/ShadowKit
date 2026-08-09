# ShadowKit v4 🌵⚡

**ShadowKit** is an enterprise-grade, self-healing background automation and system optimization suite engineered for Windows 10/11 in pure PowerShell.

It continuously supervises system state, locks ultra-low latency power and timer profiles, purges standby memory, and prevents Windows Update or telemetry routines from undoing your performance configurations.

---

## Key Features

- **Isolated Runspace Engine**: ShadowController launches each plugin in its own isolated .NET Runspace with exponential backoff restart protection.
- **Cross-Version IPC Bus**: Mutex-guarded, dual-compatible status bus (status.json) supporting both PowerShell 5.1 and 7+ using atomic disk swaps.
- **Structured JSONL Telemetry**: Centralized log stream (shadowkit.jsonl) featuring automatic 5MB log rotation.
- **0.5ms Kernel Timer Lock**: TimerOptimizer enforces 0.5ms system timer resolution via Native API calls.
- **Event-Driven DNS**: DNSFrenzy listens to network adapter state changes via WMI event subscriptions.
- **Self-Healing Enforcement Matrix**: SystemCalibrator continuously scans and silently reverts registry or telemetry drift every 30 minutes.

---

## Suite Architecture

| Component | Type | Primary Role |
| :--- | :--- | :--- |
| ShadowController.ps1 | Service Daemon | Mutex-guarded singleton controller. Manages runspaces and handles health recovery. |
| ShadowIPC.ps1 | Core Module | Cross-process status bus reader/writer with mutex locking. |
| ShadowLogger.ps1 | Core Module | Structured JSONL logger with automatic size-based rotation. |
| TimerOptimizer.ps1 | Background Service | Locks system timer resolution to 0.5ms via NTAPI calls. |
| DNSFrenzy.ps1 | Background Service | Event-driven network interface switch listener using WMI. |
| MemoryCleaner.ps1 | Background Service | NTAPI-level standby list purging service. |
| SystemCalibrator.ps1 | Self-Healing Loop | Declarative profile enforcement engine; captures baseline and repairs state drift. |
| GameOptimizer.ps1 | One-Shot Plugin | Applies high-performance CPU profiles, USB suspend toggles, and ASPM tweaks. |
| GUI-WPF.ps1 | Dashboard | Hardware-accelerated dark-themed XAML telemetry dashboard with live metrics. |

---

## Quick Start

### Prerequisites
- Windows 10/11
- PowerShell 5.1 or 7+
- Administrator privileges

### Installation & Setup
1. Clone repository: git clone https://github.com/mrcactus-afk/ShadowKit.git`n2. Run tests: .\tests\Run-Tests.ps1`n3. Launch daemon: .\Launch-ShadowKit.ps1`n
---

## License

Distributed under the **MIT License**.