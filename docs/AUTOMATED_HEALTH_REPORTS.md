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
