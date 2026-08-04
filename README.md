# ShadowKit – Windows Automation Suite

ShadowKit is a lightweight, self‑healing automation system for Windows 10/11. It manages DNS switching, memory cleanup, system integrity monitoring, and provides GUI alerts for errors – all designed to run silently in the background.

## Features
- **DNS Switcher** – automatically selects the fastest DNS server from a list (Iran‑optimised by default; easily customisable).
- **Memory Cleaner** – purges the standby list when memory usage exceeds a configurable threshold (80% default).
- **System Watchdog** – checks system integrity every 6 hours and repairs drift (requires a custom repair script).
- **GUI Notifier** – shows a friendly popup when errors or warnings are logged.
- **Modular & Configurable** – all settings in `config.json`; scripts are independent.
- **Self‑starting** – installs as a scheduled task that runs at boot.

## Prerequisites
- Windows 10/11 (x64)
- PowerShell 5.1 or later (built‑in)
- Administrator privileges for installation
- (Optional) A system repair script of your own (e.g., `WinOpt.ps1`) if you want the watchdog to actually fix things.

## Installation
1. **Clone or download** this repository:
   ```bash
   git clone https://github.com/mrcactus-afk/ShadowKit.git
Or download the ZIP and extract to any folder (but we recommend C:\ShadowKit).

Customise the configuration (optional):

Open config.json and adjust intervals, thresholds, and the repair script path.

Edit servers.json to add/remove DNS servers for your region.

Run the installer as Administrator:

Right‑click Setup-ShadowKit.ps1 and select "Run with PowerShell" (as Admin).

Or open an Admin PowerShell window, navigate to the folder, and run:

powershell
.\Setup-ShadowKit.ps1
The system will now:

Copy all files to C:\ShadowKit (if you didn't run from there).

Create a scheduled task named ShadowKit that starts at boot.

Launch the Master Controller immediately.

Usage
Check status – run ShadowController.ps1 manually in an Admin PowerShell window to see live console output.

View logs – all logs are in C:\ShadowKit\logs\:

master_YYYY-MM-DD.log – controller activity and component execution.

dns.log – DNS switching events.

memory.log – memory cleaner runs.

watchdog.log – integrity checks and repairs.

Stop the system – disable the scheduled task:

powershell
schtasks /change /tn "ShadowKit" /disable
Uninstall – run Uninstall-ShadowKit.ps1 as Administrator (removes the task and deletes the folder).

Configuration
All settings are in config.json. Example:

json
{
  "watchdog": {
    "enabled": true,
    "intervalMinutes": 360,
    "repairScript": "C:\\WinOpt.ps1",
    "checkArgs": "-WhatIf",
    "repairArgs": "-Max -Force"
  },
  "dns": {
    "enabled": true,
    "intervalMinutes": 10,
    "fallbackDNS": ["1.1.1.1", "1.0.0.1"],
    "serverListFile": "C:\\ShadowKit\\servers.json",
    "updateURL": ""
  },
  "memory": {
    "enabled": true,
    "intervalMinutes": 5,
    "thresholdPercent": 80,
    "forceClean": false
  },
  "logging": {
    "level": "info",
    "maxLogSizeMB": 10
  }
}
watchdog – set repairScript to your own script if you have one; otherwise, use a dummy (e.g., "C:\\Windows\\System32\\cmd.exe" with /c exit 0 as args) to always report OK.

dns – replace updateURL with a URL pointing to a JSON list of DNS servers if you want automatic updates.

memory – adjust thresholdPercent to trigger cleanup at different usage levels.

Customising the DNS List
Edit servers.json with your own servers. Each entry must have name, primary, and secondary fields. Example:

json
[
  {"name":"Cloudflare", "primary":"1.1.1.1", "secondary":"1.0.0.1"},
  {"name":"Google", "primary":"8.8.8.8", "secondary":"8.8.4.4"}
]
GUI Notifier
The notifier (ErrorPopup.ps1) runs every 5 minutes via a Startup shortcut and shows a popup when new errors/warnings appear. To customise its behavior, edit the script directly.

Troubleshooting
No popups – ensure the Startup shortcut exists (C:\Users\%USERNAME%\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\ShadowKitPopup.lnk). If missing, run the installation commands again.

Errors in logs – check config.json paths and that repairScript is valid.

DNS not switching – verify your network adapter is active and that the DNS servers in servers.json are reachable.

Watchdog fails – if you don't have a repair script, set repairScript to a dummy (e.g., cmd.exe with /c exit 0).

Uninstall
Run Uninstall-ShadowKit.ps1 as Administrator. It will:

Stop and delete the scheduled task.

Kill any running controller processes.

Ask you whether to delete the C:\ShadowKit folder.

License
MIT – see LICENSE for details.

Authors
ShadowKit was crafted by Shadow Hacker and Butter – built for performance and simplicity.

Contributing
Feel free to fork and submit pull requests. Issues and feature requests are welcome via GitHub Issues.
