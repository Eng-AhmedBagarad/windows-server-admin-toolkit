[CmdletBinding()]
param(
    [ValidateSet("Install", "Uninstall", "Status")]
    [string]$Action = "Status"
)

$ErrorActionPreference = "Stop"
$taskName = "WindowsServerAdminToolkit-HealthCheck"
$runner = Join-Path $PSScriptRoot "Invoke-ScheduledHealthCheck.ps1"

switch ($Action) {
    "Install" {
        if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

        $taskAction = New-ScheduledTaskAction `
            -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$runner`""

        $start = (Get-Date).AddMinutes(1)
        $trigger = New-ScheduledTaskTrigger -Once -At $start `
            -RepetitionInterval (New-TimeSpan -Minutes 5) `
            -RepetitionDuration (New-TimeSpan -Days 3650)

        $principal = New-ScheduledTaskPrincipal `
            -UserId "$env:USERDOMAIN\$env:USERNAME" `
            -LogonType Interactive -RunLevel Limited

        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
            -MultipleInstances IgnoreNew

        Register-ScheduledTask -TaskName $taskName `
            -Action $taskAction -Trigger $trigger `
            -Principal $principal -Settings $settings `
            -Description "Read-only local server health reports every five minutes." `
            -Force | Out-Null

        Write-Host "Scheduled task registered: $taskName"
        Write-Host "Runs as the current user while logged on."
    }
    "Uninstall" {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false `
            -ErrorAction SilentlyContinue
        Write-Host "Removal requested for task: $taskName"
    }
    "Status" {
        Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue |
            Select-Object TaskName, State
        if (!(Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
            Write-Host "Task is not installed."
        }
    }
}

