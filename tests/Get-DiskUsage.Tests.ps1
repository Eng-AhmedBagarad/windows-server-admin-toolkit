Describe "Get-DiskUsage script behavior" {
    BeforeEach {
        $diskScript = Join-Path $PSScriptRoot "..\scripts\Get-DiskUsage.ps1"
        $diskScript = Resolve-Path $diskScript
    }

    It "returns Healthy for a disk below the warning threshold" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 30GB
            }
        } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }

        $result = @(& $diskScript)

        $result.Count | Should -Be 1
        $result[0].Drive | Should -Be "X:"
        $result[0].UsedGB | Should -Be 70
        $result[0].UsedPercent | Should -Be 70
        $result[0].HealthStatus | Should -Be "Healthy"
    }

    It "returns Warning at the warning threshold" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 20GB
            }
        } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }

        $result = @(& $diskScript)

        $result[0].UsedPercent | Should -Be 80
        $result[0].HealthStatus | Should -Be "Warning"
    }

    It "returns Critical at the critical threshold" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 10GB
            }
        } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }

        $result = @(& $diskScript)

        $result[0].UsedPercent | Should -Be 90
        $result[0].HealthStatus | Should -Be "Critical"
    }

    It "supports custom thresholds" {
        Mock Get-CimInstance {
            [PSCustomObject]@{
                DeviceID = "X:"
                VolumeName = "Test"
                Size = 100GB
                FreeSpace = 25GB
            }
        } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }

        $result = @(
            & $diskScript -WarningThreshold 70 -CriticalThreshold 85
        )

        $result[0].HealthStatus | Should -Be "Warning"
    }

    It "rejects invalid threshold ordering" {
        {
            & $diskScript -WarningThreshold 90 -CriticalThreshold 80
        } | Should -Throw
    }

    It "warns and returns nothing when no local fixed drives are found" {
        Mock Get-CimInstance { } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }
        Mock Write-Warning { }

        $result = @(& $diskScript)

        $result.Count | Should -Be 0
        Assert-MockCalled Write-Warning -Exactly 1 -Scope It
    }

    It "skips disks with unavailable capacity information" {
        Mock Get-CimInstance {
            @(
                [PSCustomObject]@{
                    DeviceID = "X:"
                    VolumeName = "Test"
                    Size = 100GB
                    FreeSpace = 30GB
                },
                [PSCustomObject]@{
                    DeviceID = "Y:"
                    VolumeName = "Unknown"
                    Size = $null
                    FreeSpace = $null
                }
            )
        } -ParameterFilter { $ClassName -eq "Win32_LogicalDisk" }
        Mock Write-Warning { }

        $result = @(& $diskScript)

        $result.Count | Should -Be 1
        $result[0].Drive | Should -Be "X:"
        Assert-MockCalled Write-Warning -Exactly 1 -Scope It
    }
}
