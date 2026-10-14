
$healthScript = Join-Path $PSScriptRoot "..\scripts\Get-ServerHealth.ps1"

Describe "Get-ServerHealth script behavior" {
    BeforeEach {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                CSName = "TEST-SERVER"
                Caption = "Microsoft Windows Server"
                Version = "10.0"
                LastBootUpTime = (Get-Date).AddDays(-2)
                TotalVisibleMemorySize = 16MB
                FreePhysicalMemory = 4MB
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_OperatingSystem"
        }

        Mock Get-Counter {
            [PSCustomObject]@{
                CounterSamples = @(
                    [PSCustomObject]@{ CookedValue = 20 }
                    [PSCustomObject]@{ CookedValue = 30 }
                )
            }
        }

        Mock Get-Service {
            [PSCustomObject]@{
                Name = $Name
                Status = [System.ServiceProcess.ServiceControllerStatus]::Running
            }
        }

        Mock Write-Warning {}
    }

    It "returns structured system and resource data" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 30GB
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_LogicalDisk"
        }

        $report = & $healthScript -AsObject

        $report.System.ComputerName | Should Be "TEST-SERVER"
        $report.Resources.Count | Should Be 2
        $report.Memory.TotalGB | Should Be 16
        $report.Memory.AvailableGB | Should Be 4
        $report.Memory.UsedPercent | Should Be 75
        $report.Disks.Count | Should Be 1
        $report.Disks[0].HealthStatus | Should Be "Healthy"
        $report.OverallStatus | Should Be "Healthy"
    }

    It "marks overall health Critical when a disk is critical" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 5GB
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_LogicalDisk"
        }

        $report = & $healthScript -AsObject

        $report.Disks[0].HealthStatus | Should Be "Critical"
        $report.OverallStatus | Should Be "Critical"
    }

    It "marks CPU Warning when usage reaches the configured warning threshold" {
        Mock Get-Counter {
            [PSCustomObject]@{
                CounterSamples = @(
                    [PSCustomObject]@{ CookedValue = 85 }
                    [PSCustomObject]@{ CookedValue = 85 }
                )
            }
        }

        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 30GB
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_LogicalDisk"
        }

        $report = & $healthScript -AsObject

        $cpu = $report.Resources | Where-Object { $_.Resource -eq "CPU" }
        $cpu.HealthStatus | Should Be "Warning"
        $report.OverallStatus | Should Be "Warning"
    }

    It "returns Unknown when a requested service is not found" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 30GB
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_LogicalDisk"
        }

        Mock Get-Service {}

        $report = & $healthScript -AsObject -ServiceName "MissingTestService"

        $report.Services[0].Status | Should Be "NotFound"
        $report.Services[0].HealthStatus | Should Be "Unknown"
        $report.OverallStatus | Should Be "Unknown"
    }

    It "rejects invalid threshold ordering" {
        {
            & $healthScript -AsObject `
                -CPUWarningThreshold 95 `
                -CPUCriticalThreshold 90
        } | Should Throw
    }
}
