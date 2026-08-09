# ShadowKit v4

**ShadowKit** is an enterprise-grade, self-healing background automation suite built for Windows 10/11 in pure PowerShell.

## Key Features
- **Isolated Runspace Engine**: ShadowController with backoff recovery.
- **Cross-Version IPC Bus**: Dual PS 5.1 & 7+ mutex-guarded status bus.
- **Structured Telemetry**: JSONL logging with 5MB rotation.
- **0.5ms Timer Resolution**: Low latency kernel timer lock.

## Architecture
| Component | Role |
| :--- | :--- |
| ShadowController.ps1 | Runspace Daemon |
| ShadowIPC.ps1 | Status Bus |
| ShadowLogger.ps1 | JSONL Logger |
| TimerOptimizer.ps1 | 0.5ms Timer Lock |
| DNSFrenzy.ps1 | Network Switch Listener |
| MemoryCleaner.ps1 | NTAPI Standby Purge |
| SystemCalibrator.ps1 | Drift Reverter |
| GameOptimizer.ps1 | High Performance Profile |
