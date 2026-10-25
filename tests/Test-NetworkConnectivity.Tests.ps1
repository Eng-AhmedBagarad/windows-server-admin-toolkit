#
# .SYNOPSIS
#     Tests for the Test-NetworkConnectivity.ps1 script.
#
# .DESCRIPTION
#     Unit tests for the network diagnostics script using Pester 5.7.1.
#     Tests dot-source the script (which defines functions but skips main body via guard).
#

BeforeAll {
    # Save original TestMode state to restore after tests
    $global:OriginalTestMode = $null
    $global:HadTestMode = $false
    if (Test-Path variable:global:TestMode) {
        $global:OriginalTestMode = $global:TestMode
        $global:HadTestMode = $true
    }

    # Set test mode flag in global scope so it's visible when dot-sourcing from BeforeAll
    $global:TestMode = $true

    # Import NetTCPIP module to make Get-NetIPConfiguration available
    if (Get-Module -ListAvailable -Name NetTCPIP) {
        Import-Module NetTCPIP
    }

    $scriptPath = Join-Path $PSScriptRoot '..\scripts\Test-NetworkConnectivity.ps1'
    $scriptPath = Resolve-Path $scriptPath
    # Dot-source the script - the guard checks $global:TestMode to prevent main body execution when dot-sourced for testing.
    . $scriptPath

    # Save original functions before defining mocks
    $OriginalTestICMPPing = Get-Command Test-ICMPPing -CommandType Function
    $OriginalTestTCPPort = Get-Command Test-TCPPort -CommandType Function
    $OriginalResolveDnsName = Get-Command Resolve-DnsName -CommandType Function
    $OriginalTestTcpConnection = Get-Command Test-TcpConnection -CommandType Function
    $OriginalGetNetIPConfiguration = Get-Command Get-NetIPConfiguration -CommandType Function

    # Define mocks for wrapper functions after dot-sourcing so they override the real functions
    # These mocks use a GLOBAL configuration variable $global:TestMockConfig to return different values per test
    $global:TestMockConfig = @{}

    function Test-ICMPPing {
        param([string]$ComputerName, [int]$Count, [int]$TimeoutSeconds)
        $key = 'Test-ICMPPing_{0}_{1}_{2}' -f $ComputerName, $Count, $TimeoutSeconds
        if ($global:TestMockConfig.ContainsKey($key)) {
            $val = $global:TestMockConfig[$key]
            if ($val -is [ScriptBlock]) { return & $val }
            return $val
        }
        # Fallback to original implementation
        & $OriginalTestICMPPing @PSBoundParameters
    }

    function Test-TCPPort {
        param([string]$ComputerName, [int]$Port, [int]$TimeoutSeconds)
        $key = 'Test-TCPPort_{0}_{1}_{2}' -f $ComputerName, $Port, $TimeoutSeconds
        if ($global:TestMockConfig.ContainsKey($key)) {
            $val = $global:TestMockConfig[$key]
            if ($val -is [ScriptBlock]) { return & $val }
            return $val
        }
        # Fallback to original implementation
        & $OriginalTestTCPPort @PSBoundParameters
    }

    function Resolve-DnsName {
        param([string]$Hostname, [int]$TimeoutSeconds)
        $key = 'Resolve-DnsName_{0}_{1}' -f $Hostname, $TimeoutSeconds
        if ($global:TestMockConfig.ContainsKey($key)) {
            $val = $global:TestMockConfig[$key]
            if ($val -is [ScriptBlock]) { return & $val }
            return $val
        }
        & $OriginalResolveDnsName @PSBoundParameters
    }

    function Test-TcpConnection {
        param([string]$Hostname, [int]$Port, [int]$TimeoutSeconds)
        $key = 'Test-TcpConnection_{0}_{1}_{2}' -f $Hostname, $Port, $TimeoutSeconds
        if ($global:TestMockConfig.ContainsKey($key)) {
            $val = $global:TestMockConfig[$key]
            if ($val -is [ScriptBlock]) { return & $val }
            return $val
        }
        & $OriginalTestTcpConnection @PSBoundParameters
    }

    function Get-NetIPConfiguration {
        if ($global:TestMockConfig.ContainsKey('Get-NetIPConfiguration')) {
            $val = $global:TestMockConfig['Get-NetIPConfiguration']
            if ($val -is [ScriptBlock]) {
                return & $val
            }
            return $val
        }
        # Fallback to original implementation
        & $OriginalGetNetIPConfiguration @PSBoundParameters
    }
}

Describe 'Test-NetworkConnectivity - Get-LocalNetworkConfig' {
    BeforeEach {
        $global:TestMockConfig.Clear()
        Mock Write-Warning { }
    }

    It 'returns network configuration when Get-NetIPConfiguration succeeds' {
        $global:TestMockConfig['Get-NetIPConfiguration'] = @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @(@{IPAddress = 'fe80::1234'})
            }
        )

        $result = Get-LocalNetworkConfig
        $result | Should -Not -BeNullOrEmpty
        $result[0].InterfaceAlias | Should -Be 'Ethernet'
        $result[0].IPv4Address.IPAddress | Should -Be '192.168.1.100'
    }

    It 'returns null and logs warning when Get-NetIPConfiguration fails' {
        $global:TestMockConfig['Get-NetIPConfiguration'] = { throw 'Network adapter not found' }

        $result = Get-LocalNetworkConfig
        $result | Should -BeNull
        Assert-MockCalled Write-Warning -Exactly 1 -Scope It
    }
}

Describe 'Test-NetworkConnectivity - Get-DefaultGateways' {
    BeforeEach {
        Mock Get-LocalNetworkConfig { }
    }

    It 'extracts IPv4 and IPv6 gateways from network configuration' {
        $mockConfig = @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4DefaultGateway = @(@{NextHop = '192.168.1.1'})
                IPv6DefaultGateway = @(@{NextHop = 'fe80::1'})
            },
            [PSCustomObject]@{
                InterfaceAlias = 'WiFi'
                IPv4DefaultGateway = @()
                IPv6DefaultGateway = @(@{NextHop = 'fe80::2'}, @{NextHop = 'fe80::3'})
            }
        )

        Mock Get-LocalNetworkConfig { $mockConfig }

        $gateways = Get-DefaultGateways
        $gateways | Should -Not -BeNullOrEmpty
        $gateways.Count | Should -Be 4

        $ipv4 = $gateways | Where-Object { $_.AddressFamily -eq 'IPv4' } | Select-Object -First 1
        $ipv4.Address | Should -Be '192.168.1.1'
        $ipv4.InterfaceAlias | Should -Be 'Ethernet'

        $ipv6 = $gateways | Where-Object { $_.AddressFamily -eq 'IPv6' } | Sort-Object Address
        $ipv6[0].Address | Should -Be 'fe80::1'
        $ipv6[0].InterfaceAlias | Should -Be 'Ethernet'
        $ipv6[1].Address | Should -Be 'fe80::2'
        $ipv6[1].InterfaceAlias | Should -Be 'WiFi'
        $ipv6[2].Address | Should -Be 'fe80::3'
        $ipv6[2].InterfaceAlias | Should -Be 'WiFi'
    }

    It 'returns empty array when no network configuration' {
        Mock Get-LocalNetworkConfig { $null }
        $gateways = Get-DefaultGateways
        $gateways | Should -BeNullOrEmpty
    }

    It 'returns empty array when interfaces have no default gateways' {
        Mock Get-LocalNetworkConfig {
            @(
                [PSCustomObject]@{
                    InterfaceAlias = 'Ethernet'
                    IPv4DefaultGateway = @()
                    IPv6DefaultGateway = @()
                }
            )
        }
        $gateways = Get-DefaultGateways
        $gateways | Should -BeNullOrEmpty
    }
}

Describe 'Test-NetworkConnectivity - Test-GatewayReachability' {
    BeforeEach {
        $global:TestMockConfig.Clear()
    }

    It 'returns Success for ICMP when Test-ICMPPing succeeds' {
        $global:TestMockConfig['Test-ICMPPing_10.0.0.1_1_5'] = [PSCustomObject]@{ Success = $true; ResponseTime = 25; Error = $null }
        $global:TestMockConfig['Test-TCPPort_10.0.0.1_80_5'] = [PSCustomObject]@{ TcpTestSucceeded = $false; Error = $null }

        $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
        $result.ICMPStatus | Should -Be 'Success'
        $result.ICMPLatencyMS | Should -Be 25
        $result.TCPStatus | Should -Be 'Failed'
    }

    It 'returns Failed for ICMP when Test-ICMPPing returns nothing' {
        $global:TestMockConfig['Test-ICMPPing_10.0.0.1_1_5'] = [PSCustomObject]@{ Success = $false; ResponseTime = $null; Error = $null }
        $global:TestMockConfig['Test-TCPPort_10.0.0.1_80_5'] = [PSCustomObject]@{ TcpTestSucceeded = $true; Error = $null }

        $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
        $result.ICMPStatus | Should -Be 'Failed'
        $result.ICMPLatencyMS | Should -BeNull
        $result.TCPStatus | Should -Be 'Success'
    }

    It 'returns Error for ICMP when Test-ICMPPing returns error' {
        $global:TestMockConfig['Test-ICMPPing_10.0.0.1_1_5'] = [PSCustomObject]@{ Success = $false; ResponseTime = $null; Error = 'Network unreachable' }
        $global:TestMockConfig['Test-TCPPort_10.0.0.1_80_5'] = [PSCustomObject]@{ TcpTestSucceeded = $true; Error = $null }

        $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
        $result.ICMPStatus | Should -Be 'Error'
        $result.TCPStatus | Should -Be 'Success'
    }

    It 'returns Error for TCP when Test-TCPPort returns error' {
        $global:TestMockConfig['Test-ICMPPing_10.0.0.1_1_5'] = [PSCustomObject]@{ Success = $true; ResponseTime = 10; Error = $null }
        $global:TestMockConfig['Test-TCPPort_10.0.0.1_80_5'] = [PSCustomObject]@{ TcpTestSucceeded = $false; Error = 'Timeout' }

        $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
        $result.ICMPStatus | Should -Be 'Success'
        $result.TCPStatus | Should -Be 'Error'
    }
}

Describe 'Test-NetworkConnectivity - Test-DNSResolution' {
    BeforeEach {
        $global:TestMockConfig.Clear()
    }

    It 'returns Success when DNS resolution returns addresses' {
        $global:TestMockConfig['Resolve-DnsName_example.com_5'] = @(
            [PSCustomObject]@{ IPAddressToString = '93.184.216.34' },
            [PSCustomObject]@{ IPAddressToString = '2606:2800:220:1:248:1893:25c8:1946' }
        )

        $result = Test-DNSResolution -Hostname 'example.com' -TimeoutSeconds 5
        $result.Status | Should -Be 'Success'
        $result.ResolvedAddresses | Should -Be '93.184.216.34, 2606:2800:220:1:248:1893:25c8:1946'
    }

    It 'returns Failed when DNS resolution returns no addresses' {
        $global:TestMockConfig['Resolve-DnsName_nonexistent.example_5'] = @()

        $result = Test-DNSResolution -Hostname 'nonexistent.example' -TimeoutSeconds 5
        $result.Status | Should -Be 'Failed'
        $result.ResolvedAddresses | Should -Be ''
    }

    It 'returns Error when DNS resolution throws' {
        $global:TestMockConfig['Resolve-DnsName_invalid_5'] = { throw 'No such host is known' }

        $result = Test-DNSResolution -Hostname 'invalid' -TimeoutSeconds 5
        $result.Status | Should -Be 'Error'
    }

    It 'returns Failed when DNS resolution times out' {
        $global:TestMockConfig['Resolve-DnsName_example.com_1'] = @()

        $result = Test-DNSResolution -Hostname 'example.com' -TimeoutSeconds 1
        $result.Status | Should -Be 'Failed'
    }
}

Describe 'Test-NetworkConnectivity - Test-TCPConnectivity' {
    BeforeEach {
        $global:TestMockConfig.Clear()
    }

    It 'returns Connected when TCP connection succeeds' {
        $global:TestMockConfig['Test-TcpConnection_example.com_80_5'] = @{ Connected = $true; ErrorMessage = $null }

        $result = Test-TCPConnectivity -Hostname 'example.com' -Port 80 -TimeoutSeconds 5
        $result.Connected | Should -Be $true
        $result.ErrorMessage | Should -BeNullOrEmpty
    }

    It 'returns Timeout when connection attempt times out' {
        $global:TestMockConfig['Test-TcpConnection_example.com_80_5'] = @{ Connected = $false; ErrorMessage = 'Timeout' }

        $result = Test-TCPConnectivity -Hostname 'example.com' -Port 80 -TimeoutSeconds 5
        $result.Connected | Should -Be $false
        $result.ErrorMessage | Should -Be 'Timeout'
    }

    It 'returns Error when TCP client throws exception' {
        $global:TestMockConfig['Test-TcpConnection_invalid_80_5'] = @{ Connected = $false; ErrorMessage = 'No such host' }

        $result = Test-TCPConnectivity -Hostname 'invalid' -Port 80 -TimeoutSeconds 5
        $result.Connected | Should -Be $false
        $result.ErrorMessage | Should -Match 'No such host'
    }
}

Describe 'Test-NetworkConnectivity - End-to-End (Invoke-NetworkDiagnostics)' {
    BeforeEach {
        $global:TestMockConfig.Clear()

        # Mock Get-NetIPConfiguration for Get-LocalNetworkConfig
        $global:TestMockConfig['Get-NetIPConfiguration'] = @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
                IPv4DefaultGateway = @(@{NextHop = '192.168.1.1'})
                IPv6DefaultGateway = @()
            }
        )

        # Mock wrapper functions for full integration test
        $global:TestMockConfig['Test-ICMPPing_192.168.1.1_1_2'] = [PSCustomObject]@{ Success = $true; ResponseTime = 2; Error = $null }
        $global:TestMockConfig['Test-TCPPort_192.168.1.1_80_2'] = [PSCustomObject]@{ TcpTestSucceeded = $true; Error = $null }
        $global:TestMockConfig['Resolve-DnsName_localhost_2'] = @(
            [PSCustomObject]@{ IPAddressToString = '127.0.0.1' },
            [PSCustomObject]@{ IPAddressToString = '::1' }
        )
        $global:TestMockConfig['Test-TcpConnection_localhost_80_2'] = @{ Connected = $true; ErrorMessage = $null }
    }

    It 'returns a complete report object with all sections populated' {
        $result = Invoke-NetworkDiagnostics `
            -ComputerName @('localhost') `
            -Port @(80) `
            -TimeoutSeconds 2 `
            -AsObject

        $result | Should -Not -BeNullOrEmpty
        $result.GeneratedAt | Should -Not -BeNullOrEmpty
        $result.NetworkConfiguration | Should -Not -BeNullOrEmpty
        $result.Gateways | Should -Not -BeNullOrEmpty
        $result.GatewayReachability | Should -Not -BeNullOrEmpty
        $result.DNSResolution | Should -Not -BeNullOrEmpty
        $result.TCPConnectivity | Should -Not -BeNullOrEmpty

        $result.Gateways[0].Address | Should -Be '192.168.1.1'
        $result.GatewayReachability[0].ICMPStatus | Should -Be 'Success'
        $result.DNSResolution[0].ResolvedAddresses | Should -Be '127.0.0.1, ::1'
        $result.TCPConnectivity[0].Connected | Should -Be $true
    }

    It 'exports CSV with all three categories and correct row data' {
        $tempFile = [IO.Path]::GetTempFileName()
        try {
            Invoke-NetworkDiagnostics `
                -ComputerName @('localhost') `
                -Port @(80) `
                -TimeoutSeconds 2 `
                -ExportCsvPath $tempFile

            $exported = Import-Csv -Path $tempFile
            $exported | Should -Not -BeNullOrEmpty

            $categories = $exported.Category | Select-Object -Unique
            $categories | Should -Contain 'GatewayReachability'
            $categories | Should -Contain 'DNSResolution'
            $categories | Should -Contain 'TCPConnectivity'

            $gwRows = @($exported | Where-Object { $_.Category -eq 'GatewayReachability' })
            $gwRows[0].GatewayAddress | Should -Be '192.168.1.1'
            $gwRows[0].ICMPStatus | Should -Be 'Success'

            $dnsRows = @($exported | Where-Object { $_.Category -eq 'DNSResolution' })
            $dnsRows[0].Hostname | Should -Be 'localhost'
            $dnsRows[0].Status | Should -Be 'Success'

            $tcpRows = @($exported | Where-Object { $_.Category -eq 'TCPConnectivity' })
            $tcpRows[0].Port | Should -Be '80'
            $tcpRows[0].Connected | Should -Be 'True'
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }

    It 'exports JSON with complete report structure and mocked data' {
        $tempFile = [IO.Path]::GetTempFileName()
        try {
            Invoke-NetworkDiagnostics `
                -ComputerName @('localhost') `
                -Port @(80) `
                -TimeoutSeconds 2 `
                -ExportJsonPath $tempFile

            $jsonContent = Get-Content -Path $tempFile -Raw
            $jsonObject = $jsonContent | ConvertFrom-Json

            $jsonObject | Should -Not -BeNullOrEmpty
            $jsonObject.GeneratedAt | Should -Not -BeNullOrEmpty
            $jsonObject.Gateways | Should -Not -BeNullOrEmpty
            $jsonObject.Gateways[0].Address | Should -Be '192.168.1.1'
            $jsonObject.GatewayReachability[0].ICMPStatus | Should -Be 'Success'
            $jsonObject.DNSResolution[0].ResolvedAddresses | Should -Be '127.0.0.1, ::1'
            $jsonObject.TCPConnectivity[0].Connected | Should -Be $true
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }

    It 'exports HTML with all five report sections and mocked data' {
        $tempFile = [IO.Path]::GetTempFileName()
        try {
            Invoke-NetworkDiagnostics `
                -ComputerName @('localhost') `
                -Port @(80) `
                -TimeoutSeconds 2 `
                -ExportHtmlPath $tempFile

            $htmlContent = Get-Content -Path $tempFile -Raw

            $htmlContent | Should -Match '(?i)<h1>Network Connectivity Report</h1>'
            $htmlContent | Should -Match '(?i)<h2>Network Configuration</h2>'
            $htmlContent | Should -Match '(?i)<h2>Default Gateways</h2>'
            $htmlContent | Should -Match '(?i)<h2>Gateway Reachability</h2>'
            $htmlContent | Should -Match '(?i)<h2>DNS Resolution</h2>'
            $htmlContent | Should -Match '(?i)<h2>TCP Connectivity</h2>'

            $htmlContent | Should -Match '192\.168\.1\.1'
            $htmlContent | Should -Match '127\.0\.0\.1'
            $htmlContent | Should -Match 'Success'
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }

    It 'handles empty gateways gracefully in report' {
        # Override Get-NetIPConfiguration to return no gateways
        $global:TestMockConfig['Get-NetIPConfiguration'] = @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
                IPv4DefaultGateway = @()
                IPv6DefaultGateway = @()
            }
        )

        $result = Invoke-NetworkDiagnostics `
            -ComputerName @('localhost') `
            -Port @(80) `
            -TimeoutSeconds 2 `
            -AsObject

        $result.Gateways | Should -BeNullOrEmpty
        $result.GatewayReachability | Should -BeNullOrEmpty
        $result.DNSResolution | Should -Not -BeNullOrEmpty
        $result.TCPConnectivity | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-NetworkConnectivity - Direct Invocation (Script Main Body)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..\scripts\Test-NetworkConnectivity.ps1'
        $scriptPath = Resolve-Path $scriptPath
        $global:ScriptPath = $scriptPath
    }

    BeforeEach {
        # Temporarily disable TestMode so the script's guard allows main body execution
        # The outer AfterAll will restore the original TestMode value after all tests complete
        $global:TestMode = $false
    }

    It 'returns single report object with -AsObject and emits no console headings' {
        # Invoke directly (&) to satisfy guard's ExternalScript check.
        # Capture only success stream; no Write-Host output expected with -AsObject.
        $output = & $global:ScriptPath -ComputerName localhost -Port 80 -TimeoutSeconds 2 -AsObject

        $output | Should -Not -BeNullOrEmpty
        $output.GetType().FullName | Should -Be 'System.Management.Automation.PSCustomObject'
        $output.GeneratedAt | Should -Not -BeNullOrEmpty
        $output.PSObject.Properties.Name | Should -Contain 'NetworkConfiguration'
        $output.PSObject.Properties.Name | Should -Contain 'Gateways'
        $output.PSObject.Properties.Name | Should -Contain 'GatewayReachability'
        $output.PSObject.Properties.Name | Should -Contain 'DNSResolution'
        $output.PSObject.Properties.Name | Should -Contain 'TCPConnectivity'

        # Verify no console headings in output (Write-Host should not be emitted with -AsObject)
        $output | Should -Not -Match '=== NETWORK CONFIGURATION ==='
        $output | Should -Not -Match '=== DEFAULT GATEWAYS ==='
        $output | Should -Not -Match '=== GATEWAY REACHABILITY ==='
        $output | Should -Not -Match '=== DNS RESOLUTION ==='
        $output | Should -Not -Match '=== TCP CONNECTIVITY ==='
    }

    It 'displays diagnostic headings without -AsObject' {
        # Use Start-Transcript to capture all host output including Write-Host,
        # which bypasses PowerShell streams and cannot be captured via redirection.
        $transcriptPath = Join-Path $env:TEMP ("net-diag-" + [guid]::NewGuid().ToString("N") + ".txt")
        Start-Transcript -Path $transcriptPath | Out-Null
        try {
            & $global:ScriptPath -ComputerName localhost -Port 80 -TimeoutSeconds 2 | Out-Null
        }
        finally {
            Stop-Transcript | Out-Null
            $transcriptContent = Get-Content -Path $transcriptPath -Raw

            # Verify console headings are present in transcript
            $transcriptContent | Should -Match '=== NETWORK CONFIGURATION ==='
            $transcriptContent | Should -Match '=== DEFAULT GATEWAYS ==='
            $transcriptContent | Should -Match '=== GATEWAY REACHABILITY ==='
            $transcriptContent | Should -Match '=== DNS RESOLUTION ==='
            $transcriptContent | Should -Match '=== TCP CONNECTIVITY ==='
            Remove-Item $transcriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

AfterAll {
    # Restore original TestMode state
    if ($global:HadTestMode) {
        $global:TestMode = $global:OriginalTestMode
    }
    else {
        Remove-Variable -Name TestMode -Scope Global -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name OriginalTestMode -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name HadTestMode -Scope Global -ErrorAction SilentlyContinue
}