#
# .SYNOPSIS
#     Tests for Manage-HealthCheckTask.ps1 scheduled-task management logic.
#
# .DESCRIPTION
#     Mocks every scheduled-task cmdlet that could register, change, query, or remove
#     a real task. No real scheduled tasks are created, modified, or deleted.
#

Describe 'Manage-HealthCheckTask' {
    BeforeAll {
        $script:scriptPath = Join-Path $PSScriptRoot "..\scripts\Manage-HealthCheckTask.ps1"
        $script:scriptPath = Resolve-Path $script:scriptPath
    }

    BeforeEach {
        $script:MockRunnerExists = $true
        $script:MockTaskExists = $true

        Mock Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Principal, $Settings, $Description, $Force) }

        Mock Unregister-ScheduledTask { }

        Mock Get-ScheduledTask {
            if ($script:MockTaskExists) {
                [PSCustomObject]@{
                    TaskName = 'WindowsServerAdminToolkit-HealthCheck'
                    State    = 'Ready'
                }
            }
            else {
                $null
            }
        }

        Mock Write-Host { }
    }

    It 'installs with correct task registration arguments' {
        & $script:scriptPath -Action Install

        Assert-MockCalled Register-ScheduledTask -Exactly 1 -Scope It -ParameterFilter {
            $TaskName -eq 'WindowsServerAdminToolkit-HealthCheck' -and
            $null -ne $Action -and
            $null -ne $Trigger -and
            $null -ne $Principal -and
            $null -ne $Settings -and
            $Description -eq 'Read-only local server health reports every five minutes.' -and
            $Force -eq $true
        }
    }

    It 'throws when the runner is missing' {
        Mock Test-Path { param($Path) $false }

        { & $script:scriptPath -Action Install } | Should -Throw 'Runner not found*'
    }

    It 'throws when registration fails' {
        Mock Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Principal, $Settings, $Description, $Force) throw 'Registration failed' }

        { & $script:scriptPath -Action Install } | Should -Throw 'Registration failed'
    }

    It 'uninstalls the scheduled task' {
        & $script:scriptPath -Action Uninstall

        Assert-MockCalled Unregister-ScheduledTask -Exactly 1 -Scope It -ParameterFilter {
            $TaskName -eq 'WindowsServerAdminToolkit-HealthCheck' -and
            $Confirm -eq $false
        }
    }

    It 'uninstalls when the task is absent' {
        $script:MockTaskExists = $false

        & $script:scriptPath -Action Uninstall

        Assert-MockCalled Unregister-ScheduledTask -Exactly 1 -Scope It
    }

    It 'reports status when the task exists' {
        & $script:scriptPath -Action Status

        Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It -ParameterFilter {
            $TaskName -eq 'WindowsServerAdminToolkit-HealthCheck'
        }
    }

    It 'reports that the task is not installed when absent' {
        $script:MockTaskExists = $false

        & $script:scriptPath -Action Status

        Assert-MockCalled Write-Host -Exactly 1 -Scope It -ParameterFilter {
            $Object -eq 'Task is not installed.'
        }
    }
}
