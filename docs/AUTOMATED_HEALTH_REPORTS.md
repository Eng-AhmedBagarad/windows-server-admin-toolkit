# Automated Health Reports

The health collector is read-only. It writes reports to the local `reports`
directory; it does not remediate services, disks, or system configuration.

## Run once

From the repository root:

```powershell
.\scripts\Invoke-ScheduledHealthCheck.ps1
```

The runner produces `latest-server-health.json`, `latest-server-health.csv`,
and `latest-server-health.html`. A log is written to
`reports\scheduled-health-check.log`.

## Optional five-minute schedule

Install the task for the current user (while logged on):

```powershell
.\scripts\Manage-HealthCheckTask.ps1 -Action Install
```

Check status:

```powershell
.\scripts\Manage-HealthCheckTask.ps1 -Action Status
```

Remove the task:

```powershell
.\scripts\Manage-HealthCheckTask.ps1 -Action Uninstall
```

Installation is opt-in. Reports are local files and may contain host and
infrastructure details; do not publish real reports to a public repository.
The HTML page reloads every 300 seconds. The computer must be running, and
the scheduled task runs under the current user's interactive session.

### Laptop battery power and Task Scheduler

The scheduled health-check task should be allowed to run when the
computer is using battery power. Otherwise, Task Scheduler can prevent
the task from starting or stop it when the computer switches to battery.

Inspect the task settings:

```powershell
$taskName = "WindowsServerAdminToolkit-HealthCheck"

(Get-ScheduledTask -TaskName $taskName).Settings |
    Select-Object DisallowStartIfOnBatteries, StopIfGoingOnBatteries
```

For a laptop intended to run health checks on battery, configure the task:

```powershell
$taskName = "WindowsServerAdminToolkit-HealthCheck"
$settings = (Get-ScheduledTask -TaskName $taskName).Settings

$settings.DisallowStartIfOnBatteries = $false
$settings.StopIfGoingOnBatteries = $false

Set-ScheduledTask -TaskName $taskName -Settings $settings
```

These settings apply to this scheduled task, not the computer's overall
power plan. Consider battery life when deciding how frequently to run
scheduled jobs.

### Verify automatic execution

Check the most recent task result:

```powershell
Get-ScheduledTaskInfo -TaskName "WindowsServerAdminToolkit-HealthCheck" |
    Select-Object LastRunTime, LastTaskResult
```

A `LastTaskResult` of `0` indicates success. Also check the log for a
new timestamp and a successful report-generation entry:

```powershell
Get-Content `
    "C:\Projects\windows-server-admin-toolkit\reports\scheduled-health-check.log" `
    -Tail 5
```

To verify the recurring schedule, observe the log across at least one
scheduled interval without manually starting the task. Confirm that
the timestamp advances and that the generated JSON, CSV, and HTML
reports are refreshed.
