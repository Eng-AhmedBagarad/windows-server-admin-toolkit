# User Guide — Windows Server Administration Toolkit

This guide explains how to run the toolkit's PowerShell scripts, interpret their output, and troubleshoot common problems.

## 1. Requirements

- Windows 10/11 or a supported Windows Server version.
- Windows PowerShell 5.1 for the currently tested environment.
- Access to the project files.
- Permission to query the system information required by each check.
- Pester 5.x for running the existing test suite.

The scripts are diagnostic tools. Run them on the computer you want to inspect.

## 2. Get Started

Download or clone the repository, then open PowerShell in the project directory.

For an existing local copy:

```powershell
Set-Location C:\Projects\windows-server-admin-toolkit
```

Review the available scripts:

```powershell
Get-ChildItem .\scripts\*.ps1
```

If Windows blocks a script because of execution policy, first check the policy:

```powershell
Get-ExecutionPolicy -List
```

If your organization's policy permits it, you can run a script in a temporary PowerShell process with a process-scoped bypass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Get-DiskUsage.ps1"
```

This does not permanently change the machine's execution policy. Follow your organization's security policy; do not bypass organizational restrictions.

The scheduled task created by `Manage-HealthCheckTask.ps1 -Action Install` uses `-ExecutionPolicy Bypass` in its action arguments so the health-check runner can execute under Task Scheduler without requiring a machine-wide execution policy change. This bypass applies only to the scheduled task's PowerShell process, not to interactive sessions.

## 3. Check Disk Capacity

Run:

```powershell
.\scripts\Get-DiskUsage.ps1
```

The script checks local fixed disks and returns structured objects containing:

- `Drive`: drive letter.
- `VolumeName`: volume label.
- `TotalGB`: total capacity in GB.
- `UsedGB`: used capacity in GB.
- `FreeGB`: available capacity in GB.
- `UsedPercent`: percentage of capacity in use.
- `HealthStatus`: `Healthy`, `Warning`, or `Critical`.

### Default thresholds

| Used capacity | Status |
| --- | --- |
| Below 80% | Healthy |
| 80% to below 90% | Warning |
| 90% or above | Critical |

### Customize thresholds

```powershell
.\scripts\Get-DiskUsage.ps1 -WarningThreshold 70 -CriticalThreshold 85
```

The critical threshold must be greater than the warning threshold. Both values must be between 0 and 100.

### Use the results in PowerShell

```powershell
$disks = .\scripts\Get-DiskUsage.ps1

$disks | Format-Table Drive, TotalGB, FreeGB, UsedPercent, HealthStatus -AutoSize
```

To show only disks that need attention:

```powershell
$disks | Where-Object {
    $_.HealthStatus -ne "Healthy"
} | Format-Table Drive, FreeGB, UsedPercent, HealthStatus -AutoSize
```

If no local fixed disks are found, the script issues a warning. Disks with invalid capacity information are skipped.

## 4. Run the Complete Server Health Report

Run:

```powershell
.\scripts\Get-ServerHealth.ps1
```

The report includes:

- Computer name, Windows edition, version, and uptime.
- CPU utilization based on performance-counter samples.
- RAM usage and available memory.
- Local fixed-disk capacity and status.
- Status of selected Windows services.
- An overall health status.

### Overall health status

- `Critical`: at least one reported check is critical.
- `Warning`: no critical check was found, but at least one check raised a warning.
- `Unknown`: no critical or warning status was found, but at least one check could not be confirmed.
- `Healthy`: all evaluated checks reported healthy.

A critical status takes precedence over warning and unknown statuses.

### Customize thresholds

```powershell
.\scripts\Get-ServerHealth.ps1 `
    -CPUWarningThreshold 70 `
    -CPUCriticalThreshold 90 `
    -RAMWarningThreshold 75 `
    -RAMCriticalThreshold 90 `
    -DiskWarningThreshold 80 `
    -DiskCriticalThreshold 90
```

Each critical threshold must be greater than its corresponding warning threshold.

### Select which services to check

By default, the script checks `EventLog`, `LanmanServer`, and `Dnscache`.

To check different services:

```powershell
.\scripts\Get-ServerHealth.ps1 -ServiceName "EventLog","Spooler"
```

Each service is reported with its actual status (`Status`) and an interpreted health state (`HealthStatus`):

| Actual state | HealthStatus |
| --- | --- |
| `Running`, matching the expected state | `Healthy` |
| `Stopped`, but expected to be `Running` | `Warning` |
| `Stopped`, and expected to be `Stopped` | `Healthy` |
| `Paused`, `StartPending`, `StopPending`, `ContinuePending`, `PausePending` | `Warning` |
| Not found | `Unknown` |

A service that cannot be found is reported as `Unknown`. A service that is not in its expected state is reported as `Warning`.

By default every service is expected to be `Running`. Use `-ExpectedServiceState` to declare that a service is expected to be stopped — for example, on a hardened server where unneeded services are disabled — so it is reported as `Healthy` instead of `Warning`.

Example: keep `EventLog` and `LanmanServer` expected running, but mark `Telnet` as expected stopped:

```powershell
.\scripts\Get-ServerHealth.ps1 `
    -ServiceName "EventLog","LanmanServer","Telnet" `
    -ExpectedServiceState @{ Telnet = "Stopped" }
```

Here `Telnet` reports `Healthy` when it is actually `Stopped`. Any other service that is not `Running` reports `Warning`.

Choose services appropriate for the server's role. A stopped service is not necessarily a fault if it is optional or intentionally disabled.

### Return structured data

Use `-AsObject` when another PowerShell command or script needs to consume the report:

```powershell
$report = .\scripts\Get-ServerHealth.ps1 -AsObject

$report.OverallStatus
$report.System
$report.Resources
$report.Disks
$report.Services
```

Display the disk results:

```powershell
$report.Disks |
    Format-Table Drive, UsedPercent, HealthStatus -AutoSize
```

Display services that are not healthy:

```powershell
$report.Services |
    Where-Object { $_.HealthStatus -ne "Healthy" } |
    Format-Table ServiceName, Status, HealthStatus -AutoSize
```

The `-AsObject` option returns the report object rather than the formatted console report.

## 5. Export Reports

The server health script can save reports as JSON, CSV, or both. Exporting is optional; without export parameters, the script displays its normal console report.

Create an output directory if needed:

```powershell
New-Item -ItemType Directory -Path .\reports -Force
```

Export both formats:

```powershell
.\scripts\Get-ServerHealth.ps1 `
    -ExportJsonPath ".\reports\health-report.json" `
    -ExportCsvPath ".\reports\health-report.csv"
```

**JSON** preserves the complete nested report, including overall status, system information, CPU and RAM resources, disks, and services.

**CSV** provides a flat table suitable for Excel and other reporting tools. It includes overall health, system information, resources, each disk, and each selected service.

The output directory must already exist. The script does not create it automatically.

Use `-Verbose` to display messages confirming where reports were saved.

Read the JSON report:

```powershell
$report = Get-Content .\reports\health-report.json -Raw |
    ConvertFrom-Json

$report.OverallStatus
$report.Disks |
    Format-Table Drive, UsedPercent, HealthStatus -AutoSize
```

Read the CSV report:

```powershell
Import-Csv .\reports\health-report.csv |
    Format-Table Category, Name, Status, UsagePercent -AutoSize
```

You can also export JSON while returning the report as an object:

```powershell
$report = .\scripts\Get-ServerHealth.ps1 `
    -AsObject `
    -ExportJsonPath ".\reports\health-report.json"
```

## 6. Run Network Diagnostics

Run:

```powershell
.\scripts\Test-NetworkConnectivity.ps1
```

The script reports local network configuration, gateway reachability, DNS resolution, and TCP connectivity. It is read-only and does not modify system state.

### Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `ComputerName` | `localhost`, `127.0.0.1` | Hostnames or IP addresses to test. |
| `Port` | `80`, `443` | TCP ports to test on each host. |
| `TimeoutSeconds` | `5` | Timeout in seconds for each connection attempt. |
| `ExportCsvPath` | (none) | Path to save a flat CSV report. |
| `ExportJsonPath` | (none) | Path to save a JSON report. |
| `ExportHtmlPath` | (none) | Path to save an HTML report. |
| `AsObject` | (switch) | Return a structured report object instead of console output. |

### Console output

Without `-AsObject`, the script prints five sections to the console:

- `=== NETWORK CONFIGURATION ===`
- `=== DEFAULT GATEWAYS ===`
- `=== GATEWAY REACHABILITY ===`
- `=== DNS RESOLUTION ===`
- `=== TCP CONNECTIVITY ===`

### Return structured data

Use `-AsObject` when another PowerShell command or script needs to consume the report:

```powershell
$report = .\scripts\Test-NetworkConnectivity.ps1 -AsObject

$report.GeneratedAt
$report.NetworkConfiguration
$report.Gateways
$report.GatewayReachability
$report.DNSResolution
$report.TCPConnectivity
```

### Export reports

The script can save CSV, JSON, and HTML reports. The output directory must already exist.

```powershell
.\scripts\Test-NetworkConnectivity.ps1 `
    -ExportCsvPath ".\reports\network-report.csv" `
    -ExportJsonPath ".\reports\network-report.json" `
    -ExportHtmlPath ".\reports\network-report.html"
```

## 7. Check Top Resource Consumers

Run:

```powershell
.\scripts\Get-TopResourceConsumers.ps1
```

The script samples process CPU, memory, and I/O over a configurable interval and reports the top consumers in each category. It is read-only and does not modify system state.

### Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `SampleSeconds` | `2` | Number of seconds to sample process activity. |
| `Top` | `10` | Number of top processes to report per category. |
| `ExportCsvPath` | (none) | Path to save a CSV report. |
| `ExportJsonPath` | (none) | Path to save a JSON report. |
| `ExportHtmlPath` | (none) | Path to save an HTML report. |

### Console output

The script prints four sections to the console:

- `=== TOP CPU PROCESSES ===`
- `=== TOP MEMORY PROCESSES ===`
- `=== TOP PROCESS I/O READERS ===`
- `=== TOP PROCESS I/O WRITERS ===`

### Export reports

The script can save CSV, JSON, and HTML reports. The output directory must already exist.

```powershell
.\scripts\Get-TopResourceConsumers.ps1 `
    -SampleSeconds 2 `
    -Top 10 `
    -ExportCsvPath ".\reports\resource-consumers.csv" `
    -ExportJsonPath ".\reports\resource-consumers.json" `
    -ExportHtmlPath ".\reports\resource-consumers.html"
```

## 8. Run the Tests

From the repository root, run the full test suite:

```powershell
Invoke-Pester .\tests
```

To run only disk-monitoring tests:

```powershell
Invoke-Pester .\tests\Get-DiskUsage.Tests.ps1
```

To run only server-health tests:

```powershell
Invoke-Pester .\tests\Get-ServerHealth.Tests.ps1
```

Install Pester only if it is not already available and you are authorized to install PowerShell modules. The current test suite was validated with Pester 5.x.

Tests use mocked system data for repeatable checks. Passing tests does not by itself certify every Windows version or production environment.

## 9. Troubleshooting

### Access denied or collection errors

- Run PowerShell under an account with the necessary permissions.
- Try an elevated PowerShell session only if required and authorized.
- Check whether Windows performance counters and CIM queries are available.
- Review the full error message before changing permissions.

### CPU data is unavailable

The health script uses the Windows Processor performance counter. If collection fails, it issues a warning and reports CPU status as `Unknown`. Investigate performance-counter availability on the target machine.

### Disk data is unavailable

Confirm that Windows can query local fixed disks through CIM. The health report treats missing disk results as an unknown health condition.

### A service is missing or stopped

Check the service name and the server's intended role. Missing services are reported as `Unknown`; stopped services are reported as `Warning`. Review the result rather than automatically starting a service.

### The overall status is Critical

Inspect the individual CPU, RAM, disk, and service results to identify the check responsible for the status. For disk warnings or critical results, review free capacity and investigate disk usage before deleting files.

## 10. Safety and Limitations

- These scripts are intended for read-only diagnostics.
- They do not intentionally change system configuration.
- The health report depends on the availability of Windows CIM and performance-counter data.
- Default service checks are examples, not universal requirements for every server role.
- Health thresholds are configurable indicators; they should be adjusted to the workload and operational requirements.
- Validate results in your own environment before relying on them for production monitoring.
- The `scripts` directory contains disk-capacity, server-health, network diagnostics, and top resource consumer scripts.

## 11. Common Commands

| Task | Command |
| --- | --- |
| Check disks | `.\scripts\Get-DiskUsage.ps1` |
| Check server health | `.\scripts\Get-ServerHealth.ps1` |
| Get a structured report | `.\scripts\Get-ServerHealth.ps1 -AsObject` |
| Check selected services | `.\scripts\Get-ServerHealth.ps1 -ServiceName "EventLog","Spooler"` |
| Run network diagnostics | `.\scripts\Test-NetworkConnectivity.ps1` |
| Get structured network report | `.\scripts\Test-NetworkConnectivity.ps1 -AsObject` |
| Check top resource consumers | `.\scripts\Get-TopResourceConsumers.ps1` |
| Run all tests | `Invoke-Pester .\tests` |
