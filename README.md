# ShadowKit – Windows Automation Suite (Intelligent Edition)

ShadowKit is a lightweight, self‑healing automation system for Windows 10/11. It manages DNS switching, memory cleanup, system integrity monitoring, and provides GUI alerts – all designed to run silently in the background.

## Features
- **DNS Switcher** – automatically selects the fastest DNS server from a list (Iran‑optimised). Now with **intelligent caching** – only re‑tests when the interval expires, saving CPU.
- **Memory Cleaner** – **ISLC‑style** – purges the standby list when it exceeds 1 GB (configurable). Uses performance counters to track standby cache size, not total memory usage.
- **System Watchdog** – checks system integrity every 6 hours and repairs drift (requires a custom repair script).
- **GUI Notifier** – shows a friendly popup when errors or warnings are logged.
- **Modular & Configurable** – all settings in `config.json`; scripts are independent.
- **Self‑starting** – installs as a scheduled task that runs at boot.

## Prerequisites
- Windows 10/11 (x64)
- PowerShell 5.1 or later (built‑in)
- Administrator privileges for installation

## Installation
1. Clone or download this repository.
2. Customise `config.json` and `servers.json` (optional).
3. Run `Setup-ShadowKit.ps1` as Administrator.
4. The system installs a scheduled task that starts at boot.

## Usage
- All logs are in `C:\ShadowKit\logs\`.
- Check status: run `ShadowController.ps1` manually.
- Uninstall: run `Uninstall-ShadowKit.ps1` as Administrator.

## Configuration
- `config.json` – intervals, thresholds, repair script path.
- `servers.json` – list of DNS servers to test.

## Intelligent Enhancements
- **MemoryCleaner** now uses ISLC‑style logic: monitors standby list size and purges when >1GB (adjustable).
- **DNSFrenzy** caches the best server and only re‑tests every interval, reducing network overhead.
- **Watchdog** logs system health and handles errors gracefully.

## License
MIT – see LICENSE.

## Authors
ShadowKit – built for performance and simplicity.
