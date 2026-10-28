$healthScript = Join-Path $PSScriptRoot "..\scripts\Get-ServerHealth.ps1"

Describe "Get-ServerHealth script behavior" {
    BeforeEach {
        $healthScript = Join-Path $PSScriptRoot "..\scripts\Get-ServerHealth.ps1"
        $healthScript = Resolve-Path $healthScript

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

        $report.System.ComputerName | Should -Be "TEST-SERVER"
        $report.Resources.Count | Should -Be 2
        $report.Memory.TotalGB | Should -Be 16
        $report.Memory.AvailableGB | Should -Be 4
        $report.Memory.UsedPercent | Should -Be 75
        $report.Disks.Count | Should -Be 1
        $report.Disks[0].HealthStatus | Should -Be "Healthy"
        $report.OverallStatus | Should -Be "Healthy"
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

        $report.Disks[0].HealthStatus | Should -Be "Critical"
        $report.OverallStatus | Should -Be "Critical"
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
        $cpu.HealthStatus | Should -Be "Warning"
        $report.OverallStatus | Should -Be "Warning"
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

        $report.Services[0].Status | Should -Be "NotFound"
        $report.Services[0].HealthStatus | Should -Be "Unknown"
        $report.OverallStatus | Should -Be "Unknown"
    }

    It "rejects invalid threshold ordering" {
        {
            & $healthScript -AsObject `
                -CPUWarningThreshold 95 `
                -CPUCriticalThreshold 90
        } | Should -Throw
    }

    It "exports a complete JSON report" {
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

        $jsonPath = Join-Path $env:TEMP (
            "health-report-" + [guid]::NewGuid().ToString("N") + ".json"
        )

        try {
            & $healthScript -ExportJsonPath $jsonPath | Out-Null

            Test-Path $jsonPath | Should -Be $true

            $exported = Get-Content $jsonPath -Raw | ConvertFrom-Json

            $exported.System.ComputerName | Should -Be "TEST-SERVER"
            $exported.Resources.Count | Should -Be 2
            $exported.Disks.Count | Should -Be 1
            $exported.Disks[0].HealthStatus | Should -Be "Healthy"
        }
        finally {
            Remove-Item $jsonPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "exports CSV rows for resources, disks, and services" {
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

        $csvPath = Join-Path $env:TEMP (
            "health-report-" + [guid]::NewGuid().ToString("N") + ".csv"
        )

        try {
            & $healthScript -ExportCsvPath $csvPath | Out-Null

            Test-Path $csvPath | Should -Be $true

            $rows = @(Import-Csv $csvPath)

            ($rows | Where-Object { $_.Category -eq "Resource" }).Count |
                Should -Be 2


            ($resourceTypes = @($rows | Where-Object { $_.Category -eq "Disk" })).Count |
                Should -Be 1

            ($rows | Where-Object { $_.Category -eq "Service" }).Count |
                Should -Be 3

            @($rows | Where-Object { $_.Category -eq "Overall" }).Count |
                Should -Be 1
        }
        finally {
            Remove-Item $csvPath -Force -ErrorAction SilentlyContinue
        }
    }


    It "exports a complete HTML report" {
        $htmlPath = Join-Path $env:TEMP (
            "health-report-" + [guid]::NewGuid().ToString("N") + ".html"
        )

        try {
            & $healthScript -ExportHtmlPath $htmlPath | Out-Null

            Test-Path $htmlPath | Should -Be $true

            $html = Get-Content $htmlPath -Raw
            $html | Should -Match '(?i)<html'
            $html | Should -Match '(?i)</html>'
            $html | Should -Match 'http-equiv="refresh"'
            $html | Should -Match 'System Information'
            $html | Should -Match 'Resources'
            $html | Should -Match 'Disks'
            $html | Should -Match 'Services'
        }
        finally {
            Remove-Item $htmlPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "reports Healthy for services that are running by default" {
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

        # Get-Service is already mocked in BeforeEach to return Running for all names.

        $report = & $healthScript -AsObject -ServiceName @("EventLog", "LanmanServer")

        $report.Services[0].HealthStatus | Should -Be "Healthy"
        $report.Services[1].HealthStatus | Should -Be "Healthy"
        $report.OverallStatus | Should -Be "Healthy"
    }

    It "reports Healthy when a service is stopped and expected to be stopped" {
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

        Mock Get-Service {
            [PSCustomObject]@{
                Name = $Name
                Status = [System.ServiceProcess.ServiceControllerStatus]::Stopped
            }
        }

        $report = & $healthScript -AsObject `
            -ServiceName "Spooler" `
            -ExpectedServiceState @{ Spooler = "Stopped" }

        $svc = $report.Services | Where-Object { $_.ServiceName -eq "Spooler" } | Select-Object -First 1
        $svc.Status | Should -Be "Stopped"
        $svc.HealthStatus | Should -Be "Healthy"
        $report.OverallStatus | Should -Be "Healthy"
    }

    It "reports Warning when a service is stopped but expected to run" {
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

        Mock Get-Service {
            [PSCustomObject]@{
                Name = $Name
                Status = [System.ServiceProcess.ServiceControllerStatus]::Stopped
            }
        }

        $report = & $healthScript -AsObject -ServiceName "Spooler"

        $svc = $report.Services | Where-Object { $_.ServiceName -eq "Spooler" } | Select-Object -First 1
        $svc.Status | Should -Be "Stopped"
        $svc.HealthStatus | Should -Be "Warning"
        $report.OverallStatus | Should -Be "Warning"
    }

    It "reports Warning for a paused service regardless of expected state" {
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

        Mock Get-Service {
            [PSCustomObject]@{
                Name = $Name
                Status = [System.ServiceProcess.ServiceControllerStatus]::Paused
            }
        }

        $report = & $healthScript -AsObject `
            -ServiceName "Spooler" `
            -ExpectedServiceState @{ Spooler = "Paused" }

        $svc = $report.Services | Where-Object { $_.ServiceName -eq "Spooler" } | Select-Object -First 1
        $svc.Status | Should -Be "Paused"
        $svc.HealthStatus | Should -Be "Warning"
    }

    It "reports Warning for a service in StartPending regardless of expected state" {
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

        Mock Get-Service {
            [PSCustomObject]@{
                Name = $Name
                Status = [System.ServiceProcess.ServiceControllerStatus]::StartPending
            }
        }

        $report = & $healthScript -AsObject `
            -ServiceName "Spooler" `
            -ExpectedServiceState @{ Spooler = "Running" }

        $svc = $report.Services | Where-Object { $_.ServiceName -eq "Spooler" } | Select-Object -First 1
        $svc.Status | Should -Be "StartPending"
        $svc.HealthStatus | Should -Be "Warning"
    }
    It "rejects an invalid expected service state" {
    {
        & $healthScript -ExpectedServiceState @{
            Spooler = "Stoped"
        }
    } | Should -Throw "*Invalid expected state*"
}

It "accepts a valid expected service state" {
    {
        & $healthScript -ExpectedServiceState @{
            Spooler = "Stopped"
        } -ErrorAction Stop
    } | Should -Not -Throw
}
}
