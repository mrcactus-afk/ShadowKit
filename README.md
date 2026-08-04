# ShadowKit – Windows Automation Suite

ShadowKit is a lightweight, self‑healing automation system for Windows 11. It manages DNS switching, memory cleanup, system integrity monitoring, and provides GUI alerts for errors – all designed to run silently in the background.

## Features
- **DNS Switcher** – automatically selects the fastest Iranian DNS server (Shecan, Radar, 403, Begzar, etc.).
- **Memory Cleaner** – purges the standby list when memory usage exceeds 80%.
- **System Watchdog** – checks system integrity every 6 hours and repairs drift.
- **GUI Notifier** – shows a friendly popup when errors or warnings occur.
- **Modular & Configurable** – all settings in `config.json`; scripts are independent.

## Installation
1. Clone this repository or download the ZIP.
2. Run `Setup-ShadowKit.ps1` as **Administrator**.
3. The system will install a scheduled task that starts at boot.

## Usage
- All logs are in `C:\ShadowKit\logs\`.
- To check status: run `C:\ShadowKit\ShadowController.ps1` manually (shows console output).
- To uninstall: run `Uninstall-ShadowKit.ps1` as Administrator.

## Configuration
Edit `config.json` to adjust intervals, thresholds, or DNS server list.

## License
MIT – see [LICENSE](LICENSE).

## Authors
ShadowKit was crafted by Shadow Hacker and Butter – built for performance and simplicity.
