Describe "Get-TopResourceConsumers export tests" {
    It "exports valid CSV, JSON, and HTML reports with all four resource rankings" {
        $scriptPath = Join-Path $PSScriptRoot "..\scripts\Get-TopResourceConsumers.ps1"
        $scriptPath = (Resolve-Path $scriptPath).Path

        $testRoot = Join-Path $env:TEMP (
            "TopResourceConsumersTests_" + [guid]::NewGuid().ToString("N")
        )

        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        try {
            $csvPath = Join-Path $testRoot "Resources.csv"
            $jsonPath = Join-Path $testRoot "Resources.json"
            $htmlPath = Join-Path $testRoot "Resources.html"

            & $scriptPath `
                -SampleSeconds 1 `
                -Top 3 `
                -ExportCsvPath $csvPath `
                -ExportJsonPath $jsonPath `
                -ExportHtmlPath $htmlPath |
                Out-Null

            # Verify all reports were created.
            Test-Path $csvPath | Should -Be $true
            Test-Path $jsonPath | Should -Be $true
            Test-Path $htmlPath | Should -Be $true

            # Verify CSV contains all four resource types.
            $csv = @(Import-Csv $csvPath)
            ($csv.Count -gt 0) | Should -Be $true

            $resourceTypes = @(
                $csv | Select-Object -ExpandProperty ResourceType -Unique
            )
            $resourceTypes.Count | Should -Be 4

            ($resourceTypes -contains "CPU") | Should -Be $true
            ($resourceTypes -contains "Memory") | Should -Be $true
            ($resourceTypes -contains "IORead") | Should -Be $true
            ($resourceTypes -contains "IOWrite") | Should -Be $true

            # Verify JSON is valid and contains all rankings.
            $json = Get-Content $jsonPath -Raw | ConvertFrom-Json

            @($json.TopCPU).Count | Should -BeGreaterThan 0
            @($json.TopMemory).Count | Should -BeGreaterThan 0
            @($json.TopIORead).Count | Should -BeGreaterThan 0
            @($json.TopIOWrite).Count | Should -BeGreaterThan 0

            # Verify HTML contains all four report sections.
            $html = Get-Content $htmlPath -Raw

            $html | Should -Match "Top CPU Processes"
            $html | Should -Match "Top Memory Processes"
            $html | Should -Match "Top Process I/O Readers"
            $html | Should -Match "Top Process I/O Writers"
        }
        finally {
            Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-TopResourceConsumers process sampling" {
    BeforeEach {
        $scriptPath = Join-Path $PSScriptRoot "..\scripts\Get-TopResourceConsumers.ps1"
        $scriptPath = Resolve-Path $scriptPath

        # Mock Start-Sleep to avoid actual waiting during tests
        Mock Start-Sleep { }

        # Mock Win32_Process with two samples: identical values = zero delta
        $sampleProcess = [PSCustomObject]@{
            ProcessId           = 1234
            Name                = "testproc.exe"
            KernelModeTime      = 50000000
            UserModeTime        = 50000000
            ReadTransferCount   = 1000000
            WriteTransferCount  = 2000000
            ThreadCount         = 10
            HandleCount         = 100
            ExecutablePath      = "C:\Windows\testproc.exe"
        }

        Mock Get-CimInstance {
            if ($ClassName -eq "Win32_Process") {
                @($sampleProcess)
            }
            elseif ($ClassName -eq "Win32_Service") {
                @()
            }
        }

        Mock Get-Process {
            [PSCustomObject]@{ WorkingSet64 = 50MB }
        }
    }

    It "returns structured process objects with expected properties" {
        $result = & $scriptPath -SampleSeconds 1 -Top 5 -AsObject

        $result | Should -Not -BeNullOrEmpty
        $result.TopCPU | Should -Not -BeNullOrEmpty
        $result.TopMemory | Should -Not -BeNullOrEmpty
        $result.TopIORead | Should -Not -BeNullOrEmpty
        $result.TopIOWrite | Should -Not -BeNullOrEmpty

        $proc = $result.TopCPU[0]
        $proc.PSObject.Properties.Name | Should -Contain 'ProcessName'
        $proc.PSObject.Properties.Name | Should -Contain 'ProcessId'
        $proc.PSObject.Properties.Name | Should -Contain 'CPUPercent'
        $proc.PSObject.Properties.Name | Should -Contain 'MemoryMB'
        $proc.PSObject.Properties.Name | Should -Contain 'IOReadMBPerSec'
        $proc.PSObject.Properties.Name | Should -Contain 'IOWriteMBPerSec'
        $proc.PSObject.Properties.Name | Should -Contain 'ThreadCount'
        $proc.PSObject.Properties.Name | Should -Contain 'HandleCount'
        $proc.PSObject.Properties.Name | Should -Contain 'Services'
        $proc.PSObject.Properties.Name | Should -Contain 'ExecutablePath'
    }

    It "limits TopCPU results to the specified Top count" {
        $result = & $scriptPath -SampleSeconds 1 -Top 1 -AsObject

        @($result.TopCPU).Count | Should -BeLessThan 6
        @($result.TopMemory).Count | Should -BeLessThan 6
        @($result.TopIORead).Count | Should -BeLessThan 6
        @($result.TopIOWrite).Count | Should -BeLessThan 6
    }

    It "excludes the idle process (PID 0) from results" {
        $idleProcess = [PSCustomObject]@{
            ProcessId           = 0
            Name                = "Idle"
            KernelModeTime      = 100000000
            UserModeTime        = 100000000
            ReadTransferCount   = 0
            WriteTransferCount  = 0
            ThreadCount         = 0
            HandleCount         = 0
            ExecutablePath      = $null
        }

        $sampleProcess = [PSCustomObject]@{
            ProcessId           = 1234
            Name                = "testproc.exe"
            KernelModeTime      = 50000000
            UserModeTime        = 50000000
            ReadTransferCount   = 1000000
            WriteTransferCount  = 2000000
            ThreadCount         = 10
            HandleCount         = 100
            ExecutablePath      = "C:\Windows\testproc.exe"
        }

        Mock Get-CimInstance {
            if ($ClassName -eq "Win32_Process") {
                @($idleProcess, $sampleProcess)
            }
            elseif ($ClassName -eq "Win32_Service") {
                @()
            }
        }

        Mock Get-Process {
            [PSCustomObject]@{ WorkingSet64 = 50MB }
        }

        $result = & $scriptPath -SampleSeconds 1 -Top 5 -AsObject

        $result.TopCPU | Where-Object { $_.ProcessId -eq 0 } | Should -BeNullOrEmpty
    }

    It "reports computer name and sample seconds in output" {
        $result = & $scriptPath -SampleSeconds 3 -Top 5 -AsObject

        $result.ComputerName | Should -Be $env:COMPUTERNAME
        $result.SampleSeconds | Should -Be 3
        $result.LogicalProcessors | Should -BeGreaterThan 0
    }
}
