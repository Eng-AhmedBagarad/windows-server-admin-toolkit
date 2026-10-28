# Windows Server Administration Toolkit

A PowerShell-based toolkit for Windows infrastructure operations, server health monitoring, storage capacity management, and network diagnostics. Built for Windows PowerShell 5.1 compatibility, read-only diagnostics, and structured JSON/CSV/HTML reporting.

## Overview

This toolkit provides IT administrators with reliable, reusable PowerShell scripts for monitoring Windows servers and workstations. Each script performs read-only diagnostics — no system configuration is changed — and exports structured reports in JSON, CSV, and HTML formats for troubleshooting, operational review, and automated health-check pipelines.

### What it does

- **Server health assessment:** CPU, RAM, disk capacity, OS version, uptime, and selected service status with configurable warning/critical thresholds.
- **Resource consumer analysis:** Process CPU/memory/I/O sampling over a configurable interval, with top-N rankings and exportable reports.
- **Network diagnostics:** Local network configuration, gateway reachability, DNS resolution, and TCP connectivity testing.
- **Disk capacity monitoring:** Per-drive utilization reporting with warning/critical thresholds.
- **Scheduled health checks:** Automated report generation with JSON/CSV/HTML validation and success/error logging.
- **Scheduled task management:** Install, uninstall, and query the health-check scheduled task.

## Project Highlights

- **Six PowerShell scripts** for server health, disk capacity, resource consumption, network diagnostics, scheduled health checks, and task management.
- **Windows PowerShell 5.1 compatible** — no external modules, uses built-in cmdlets and .NET classes.
- **Read-only diagnostics** — queries system state without modifying configuration.
- **Structured reporting** — JSON, CSV, and HTML exports from reporting scripts that support it (`Get-ServerHealth.ps1`, `Get-TopResourceConsumers.ps1`, `Test-NetworkConnectivity.ps1`).
- **Configurable thresholds** — warning and critical levels for CPU, RAM, and disk utilization.
- **69 Pester tests** — mocked, repeatable test suite covering all six scripts.
- **Scheduled automation** — optional Windows Scheduled Task runs health checks every 5 minutes with SUCCESS/ERROR logging.

## Core Features

| Feature | Script | Description |
|---------|--------|-------------|
| Server health | `Get-ServerHealth.ps1` | CPU, RAM, disk, OS, uptime, and service status with threshold-based health states (Healthy/Warning/Critical/Unknown). Exports JSON, CSV, HTML. |
| Resource consumers | `Get-TopResourceConsumers.ps1` | Samples process CPU, memory, and I/O over an interval; ranks top consumers per resource type. Exports JSON, CSV, HTML. |
| Network diagnostics | `Test-NetworkConnectivity.ps1` | Local network config, gateway reachability, DNS resolution, and TCP port connectivity. |
| Disk capacity | `Get-DiskUsage.ps1` | Per-drive free/used space and utilization percentages with warning/critical thresholds. |
| Scheduled health | `Invoke-ScheduledHealthCheck.ps1` | Orchestrates health report generation, validates all 3 report outputs, logs SUCCESS/ERROR. |
| Task management | `Manage-HealthCheckTask.ps1` | Install/Uninstall/Status for the scheduled health-check task. |

### Common capabilities

- **PowerShell 5.1 compatibility** across the toolkit.
- **Read-only diagnostics** for server health, disk capacity, resource consumption, and network connectivity.
- **Structured output and report exports** where supported by the individual script.
- **Automated reporting:** `Invoke-ScheduledHealthCheck.ps1` generates JSON, CSV, and HTML health reports.
- **Scheduled task management:** `Manage-HealthCheckTask.ps1` supports `-Action Install`, `-Action Uninstall`, and `-Action Status`.

Individual scripts have different parameters; see the usage examples below for each script.

## Directory Structure

```
windows-server-admin-toolkit/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   ├── Get-ServerHealth.ps1
│   ├── Get-TopResourceConsumers.ps1
│   ├── Test-NetworkConnectivity.ps1
│   ├── Invoke-ScheduledHealthCheck.ps1
│   ├── Manage-HealthCheckTask.ps1
│   └── Get-DiskUsage.ps1
├── tests/
│   ├── Get-ServerHealth.Tests.ps1
│   ├── Get-DiskUsage.Tests.ps1
│   ├── Get-TopResourceConsumers.Tests.ps1
│   ├── Test-NetworkConnectivity.Tests.ps1
│   ├── Invoke-ScheduledHealthCheck.Tests.ps1
│   └── Manage-HealthCheckTask.Tests.ps1
├── docs/
│   ├── USAGE.md
│   └── AUTOMATED_HEALTH_REPORTS.md
└── reports/              (generated reports — excluded from git)
```

## Requirements

- **PowerShell:** Windows PowerShell 5.1.
- **OS:** Windows workstation or Windows Server (domain-joined environments supported where applicable).
- **Permissions:** Appropriate permissions for the requested operations (e.g., `Get-CimInstance`, `Get-Service`, `Get-Counter`).
- **Testing:** Pester 5.7.1 (for running the included test suite).

No external modules are required. All scripts use built-in PowerShell cmdlets and .NET classes.

## Quick Start

Run any script directly from PowerShell:

```powershell
# Full server health report (console output)
.\scripts\Get-ServerHealth.ps1

# Health report with structured object output (for pipeline use)
.\scripts\Get-ServerHealth.ps1 -AsObject

# Health report exported to JSON, CSV, and HTML
.\scripts\Get-ServerHealth.ps1 `
    -ExportJsonPath .\reports\health.json `
    -ExportCsvPath  .\reports\health.csv  `
    -ExportHtmlPath .\reports\health.html

# Top resource consumers (5-minute sample, top 10 per resource)
.\scripts\Get-TopResourceConsumers.ps1 -SampleSeconds 300 -Top 10

# Disk capacity report with custom thresholds
.\scripts\Get-DiskUsage.ps1 -WarningThreshold 75 -CriticalThreshold 90

# Network diagnostics
.\scripts\Test-NetworkConnectivity.ps1
```

## Usage Examples

### Get-ServerHealth.ps1

```powershell
# Console report with default thresholds (CPU warn 80/crit 95, RAM warn 80/crit 90, disk warn 80/crit 90)
.\scripts\Get-ServerHealth.ps1

# Custom thresholds
.\scripts\Get-ServerHealth.ps1 `
    -CPUWarningThreshold 70 -CPUCriticalThreshold 90 `
    -RAMWarningThreshold 75 -RAMCriticalThreshold 85 `
    -DiskWarningThreshold 70 -DiskCriticalThreshold 85

# Monitor specific services
.\scripts\Get-ServerHealth.ps1 -ServiceName @("Spooler", "EventLog", "LanmanServer")

# Export all three formats for archiving or dashboarding
.\scripts\Get-ServerHealth.ps1 `
    -ExportJsonPath .\reports\latest-server-health.json `
    -ExportCsvPath  .\reports\latest-server-health.csv  `
    -ExportHtmlPath .\reports\latest-server-health.html

# Get structured output for further processing
$health = .\scripts\Get-ServerHealth.ps1 -AsObject
$health.OverallStatus
$health.Disks | Where-Object { $_.HealthStatus -eq "Critical" }
```

### Get-TopResourceConsumers.ps1

```powershell
# Sample for 60 seconds, show top 10 per resource
.\scripts\Get-TopResourceConsumers.ps1 -SampleSeconds 60 -Top 10

# Quick 5-second snapshot
.\scripts\Get-TopResourceConsumers.ps1 -SampleSeconds 5 -Top 5

# Export resource rankings to CSV/JSON/HTML
.\scripts\Get-TopResourceConsumers.ps1 `
    -SampleSeconds 120 `
    -Top 20 `
    -ExportCsvPath .\reports\resources.csv `
    -ExportJsonPath .\reports\resources.json `
    -ExportHtmlPath .\reports\resources.html

# Structured output for automation
$consumers = .\scripts\Get-TopResourceConsumers.ps1 -AsObject -Top 5
$consumers.TopCPU | Format-Table ProcessName, ProcessId, CPUPercent, MemoryMB -AutoSize
```

### Test-NetworkConnectivity.ps1

```powershell
# Full network diagnostic report
.\scripts\Test-NetworkConnectivity.ps1

# Structured output for automation
$result = .\scripts\Test-NetworkConnectivity.ps1 -AsObject
$result | Format-List
```

### Get-DiskUsage.ps1

```powershell
# Disk report with default thresholds (warn 80%, crit 90%)
.\scripts\Get-DiskUsage.ps1

# Custom thresholds
.\scripts\Get-DiskUsage.ps1 -WarningThreshold 75 -CriticalThreshold 85
```

### Invoke-ScheduledHealthCheck.ps1

```powershell
# Generates and validates all three report formats, logs SUCCESS/ERROR
.\scripts\Invoke-ScheduledHealthCheck.ps1
```

### Manage-HealthCheckTask.ps1

```powershell
# Install the scheduled health-check task (runs every 5 minutes)
.\scripts\Manage-HealthCheckTask.ps1 -Action Install

# Check task status
.\scripts\Manage-HealthCheckTask.ps1 -Action Status

# Uninstall the scheduled task
.\scripts\Manage-HealthCheckTask.ps1 -Action Uninstall
```

## Report Preview

The following excerpts show genuine output from the toolkit, with hostnames and machine-specific paths redacted.

### Server health — console output

```text
=== Overall Health: Critical ===
Generated: 10/27/2026 06:03:38

=== System Information ===

ComputerName    : [YOUR-COMPUTER-NAME]
OperatingSystem : Microsoft Windows 11 Pro
Version         : 10.0.26300
LastBootTime    : 10/16/2026 12:24:10 AM
UptimeDays      : 11
UptimeHours     : 5
UptimeMinutes   : 39

=== Resource Utilization ===

Resource UsagePercent HealthStatus
-------- ------------ ------------
CPU             39.52 Healthy
RAM             78.67 Healthy

=== Disk Health ===

Drive TotalGB UsedGB FreeGB UsedPercent HealthStatus
----- ------- ------ ------ ----------- ------------
C:     247.69 237.71   9.98       95.97 Critical
D:     327.87 257.17   70.7       78.44 Healthy
E:     376.94 314.63   62.32       83.47 Warning

=== Selected Service Health ===

ServiceName  Status  HealthStatus
-----------  ------  ------------
EventLog     Running Healthy
LanmanServer Running Healthy
Dnscache     Running Healthy
```

### Server health — JSON excerpt (redacted)

```json
{
    "OverallStatus": "Critical",
    "System": {
        "ComputerName": "[YOUR-COMPUTER-NAME]",
        "OperatingSystem": "Microsoft Windows 11 Pro",
        "Version": "10.0.26300",
        "UptimeDays": 11,
        "UptimeHours": 5,
        "UptimeMinutes": 39
    },
    "Resources": [
        { "Resource": "CPU", "UsagePercent": 39.52, "HealthStatus": "Healthy" },
        { "Resource": "RAM", "UsagePercent": 78.67, "HealthStatus": "Healthy" }
    ],
    "Disks": [
        { "Drive": "C:", "TotalGB": 247.69, "UsedGB": 237.71, "FreeGB": 9.98, "UsedPercent": 95.97, "HealthStatus": "Critical" },
        { "Drive": "D:", "TotalGB": 327.87, "UsedGB": 257.17, "FreeGB": 70.7, "UsedPercent": 78.44, "HealthStatus": "Healthy" },
        { "Drive": "E:", "TotalGB": 376.94, "UsedGB": 314.63, "FreeGB": 62.32, "UsedPercent": 83.47, "HealthStatus": "Warning" }
    ],
    "Services": [
        { "ServiceName": "EventLog", "Status": "Running", "HealthStatus": "Healthy" },
        { "ServiceName": "LanmanServer", "Status": "Running", "HealthStatus": "Healthy" },
        { "ServiceName": "Dnscache", "Status": "Running", "HealthStatus": "Healthy" }
    ]
}
```

### Resource consumers — console output (3-second sample)

```text
=== TOP CPU PROCESSES ===

ProcessName ProcessId CPUPercent MemoryMB Services
----------- --------- ---------- -------- --------
vmmemWSL         4648          7  2027.88
WmiPrvSE        29184       3.69    29.95
svchost          2676        2.6       25 Winmgmt
MsMpEng          5896       2.18   322.49 WinDefend
conhost         19728       2.11     9.18

=== TOP MEMORY PROCESSES ===

ProcessName        ProcessId MemoryMB CPUPercent Services
-----------        --------- -------- ---------- --------
vmmemWSL                4648  2027.88          7
Memory Compression      3492   688.75          0
chrome                 25656   549.48          0
chrome                 25932   463.56          0
chrome                 15044   333.67          0
```

## Reports

All exportable scripts generate reports in three formats:

- **JSON** (`ConvertTo-Json`): Machine-readable, suitable for dashboards, APIs, and automation.
- **CSV** (`Export-Csv`): Tabular data, suitable for spreadsheets and SIEM ingestion.
- **HTML** (`ConvertTo-Html`): Human-readable with embedded CSS, suitable for email or browser viewing.

Reports are written to the `reports/` directory by the scheduled health check. The `.gitignore` excludes generated reports (except `reports/.gitkeep`) so they are not committed to the repository.

## Scheduled Health Checks

The toolkit includes automated health-check orchestration:

1. `Invoke-ScheduledHealthCheck.ps1` — generates JSON/CSV/HTML health reports, validates all three outputs, cross-checks JSON/CSV status consistency, and logs SUCCESS or ERROR.
2. `Manage-HealthCheckTask.ps1` — installs/uninstalls/queries the Windows Scheduled Task that runs `Invoke-ScheduledHealthCheck.ps1` every 5 minutes.

See `docs/AUTOMATED_HEALTH_REPORTS.md` for the full setup guide.

## Testing

The toolkit includes **69 Pester tests** across 6 test files, all passing.

Run the full test suite:

```powershell
# Requires Pester 5.x
Invoke-Pester -Path ./tests -Output Normal
```

Individual test files:

```powershell
Invoke-Pester -Path ./tests/Get-ServerHealth.Tests.ps1 -Output Normal
Invoke-Pester -Path ./tests/Get-DiskUsage.Tests.ps1 -Output Normal
Invoke-Pester -Path ./tests/Get-TopResourceConsumers.Tests.ps1 -Output Normal
Invoke-Pester -Path ./tests/Test-NetworkConnectivity.Tests.ps1 -Output Normal
Invoke-Pester -Path ./tests/Invoke-ScheduledHealthCheck.Tests.ps1 -Output Normal
Invoke-Pester -Path ./tests/Manage-HealthCheckTask.Tests.ps1 -Output Normal
```

Tests cover report generation and validation (JSON/CSV/HTML), structured output (`-AsObject`), threshold behavior, process sampling, network diagnostics, disk capacity, and error scenarios.

## Known Limitations

- **PowerShell 5.1 compatibility:** Scripts are written for Windows PowerShell 5.1. Some modern PowerShell 7+ features are not used intentionally.
- **CPU sampling:** `Get-ServerHealth.ps1` averages two CPU samples 1 second apart, which adds ~1 second of runtime.
- **Process sampling:** `Get-TopResourceConsumers.ps1` requires a sampling interval (`-SampleSeconds`, default 2s). Processes that exit between CIM query and `Get-Process` may have missing memory data.
- **Network:** Windows does not provide reliable per-process network traffic through WMI/CIM; this script does not report per-process network usage.
- **Disk:** `Get-ServerHealth.ps1` delegates disk collection to `Get-DiskUsage.ps1`; if that script fails, disk status is reported as Unknown and factored into the overall status.
- **C: drive utilization:** On some systems, C: may run at 94–95% capacity, producing an `OverallStatus=Critical`. This is a genuine disk-space warning and is intentionally not suppressed. Free up disk space on C: to resolve.

## Skills & Technologies

- PowerShell (Windows PowerShell 5.1)
- Pester 5.x unit testing
- CIM/WMI (`Win32_LogicalDisk`, `Win32_OperatingSystem`, `Win32_Process`, `Win32_Service`)
- `Get-Counter` performance counters
- Async DNS resolution (`[System.Net.Dns]::GetHostAddressesAsync`)
- Async TCP connectivity (`[System.Net.Sockets.TcpClient]` BeginConnect/EndConnect)
- Windows Scheduled Tasks (`Register-ScheduledTask`, `Get-ScheduledTask`)
- Structured reporting: JSON (`ConvertTo-Json`), CSV (`Export-Csv`), HTML (`ConvertTo-Html`)

## License

This project is licensed under the MIT License. See `LICENSE` for details.

## Operational Principles

- **Read-only diagnostics by default.** No system configuration is changed.
- **Least-privilege execution.** Requests only the permissions needed for the operation.
- **No embedded credentials or secrets.**
- **Clear error handling** with actionable diagnostic messages.
- **Documented prerequisites, limitations, and compatibility.**
- **Administrative changes require explicit authorization** (e.g., scheduled task installation).

---
*Windows Server Administration Toolkit — reliable PowerShell diagnostics for Windows infrastructure.*