#
# .SYNOPSIS
#     Tests for the Test-NetworkConnectivity.ps1 script.
#
# .DESCRIPTION
#     Unit tests for the network diagnostics script using Pester 3.4.0.
#
# NOTE: These tests mock external dependencies to avoid relying on actual network state.
#

# Import the script to test
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\scripts\Test-NetworkConnectivity.ps1'
. $scriptPath

Describe 'Test-NetworkConnectivity - Internal Functions' {

    # Mock Get-NetIPConfiguration for Get-LocalNetworkConfig
    Context 'Get-LocalNetworkConfig' {
        It 'returns network configuration when Get-NetIPConfiguration succeeds' {
            Mock Get-NetIPConfiguration -MockWith { @(
                [PSCustomObject]@{
                    InterfaceAlias = 'Ethernet'
                    IPv4Address = @(@{IPAddress = '192.168.1.100'})
                    IPv6Address = @(@{IPAddress = 'fe80::1234'})
                }
            ) } -Verifiable -ParameterFilter { }

            $result = Get-LocalNetworkConfig
            $result | Should -Not -BeNullOrEmpty
            $result[0].InterfaceAlias | Should -Be 'Ethernet'
            $result[0].IPv4Address.IPAddress | Should -Be '192.168.1.100'
            Verify-MockCalled Get-NetIPConfiguration
        }

        It 'returns null and logs warning when Get-NetIPConfiguration fails' {
            Mock Get-NetIPConfiguration -MockWith { throw 'Network adapter not found' } -Verifiable -ParameterFilter { }
            Mock Write-Warning -MockWith { } -Verifiable

            $result = Get-LocalNetworkConfig
            $result | Should -BeNull
            Verify-MockCalled Write-Warning
        }
    }

    # Mock Get-DefaultGateways
    Context 'Get-DefaultGateways' {
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

            Mock Get-LocalNetworkConfig -MockWith { $mockConfig } -Verifiable

            $gateways = Get-DefaultGateways
            $gateways | Should -Not -BeNullOrEmpty
            $gateways.Count | Should -Be 3  # One IPv4, two IPv6

            # Check IPv4 gateway
            $ipv4 = $gateways | Where-Object { $_.AddressFamily -eq 'IPv4' } | Select-Object -First 1
            $ipv4.Address | Should -Be '192.168.1.1'
            $ipv4.InterfaceAlias | Should -Be 'Ethernet'

            # Check IPv6 gateways
            $ipv6 = $gateways | Where-Object { $_.AddressFamily -eq 'IPv6' } | Sort-Object Address
            $ipv6[0].Address | Should -Be 'fe80::1'
            $ipv6[0].InterfaceAlias | Should -Be 'Ethernet'
            $ipv6[1].Address | Should -Be 'fe80::2'
            $ipv6[1].InterfaceAlias | Should -Be 'WiFi'
            $ipv6[2].Address | Should -Be 'fe80::3'
            $ipv6[2].InterfaceAlias | Should -Be 'WiFi'
        }

        It 'returns empty array when no network configuration' {
            Mock Get-LocalNetworkConfig -MockWith { $null } -Verifiable
            $gateways = Get-DefaultGateways
            $gateways | Should -BeNullOrEmpty
        }
    }

    # Mock Test-Connection and Test-NetConnection for Test-GatewayReachability
    Context 'Test-GatewayReachability' {
        It 'returns Success for ICMP when Test-Connection succeeds' {
            Mock Test-Connection -MockWith { [PSCustomObject]@{
                ResponseTime = 25
            } } -Verifiable -ParameterFilter { $ComputerName -eq '10.0.0.1' -and $Count -eq 1 -and $TimeoutSeconds -eq 5 }
            Mock Test-NetConnection -MockWith { [PSCustomObject]@{ TcpTestSucceeded = $false } } -Verifiable

            $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
            $result.ICMPStatus | Should -Be 'Success'
            $result.ICMPLatencyMS | Should -Be 25
            $result.TCPStatus | Should -Be 'Failed'  # Because we mocked Test-NetConnection to fail
            Verify-MockCalled Test-Connection
            Verify-MockCalled Test-NetConnection
        }

        It 'returns Failed for ICMP when Test-Connection returns nothing' {
            Mock Test-Connection -MockWith { $null } -Verifiable
            Mock Test-NetConnection -MockWith { [PSCustomObject]@{ TcpTestSucceeded = $true } } -Verifiable

            $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
            $result.ICMPStatus | Should -Be 'Failed'
            $result.ICMPLatencyMS | Should -BeNull
            $result.TCPStatus | Should -Be 'Success'
        }

        It 'returns Error when Test-Connection throws' {
            Mock Test-Connection -MockWith { throw 'Network unreachable' } -Verifiable
            Mock Test-NetConnection -MockWith { [PSCustomObject]@{ TcpTestSucceeded = $true } } -Verifiable

            $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
            $result.ICMPStatus | Should -Be 'Error'
            $result.TCPStatus | Should -Be 'Success'
        }

        It 'returns Error when Test-NetConnection throws' {
            Mock Test-Connection -MockWith { [PSCustomObject]@{ ResponseTime = 10 } } -Verifiable
            Mock Test-NetConnection -MockWith { throw 'Timeout' } -Verifiable

            $result = Test-GatewayReachability -GatewayAddress '10.0.0.1' -AddressFamily 'IPv4' -TimeoutSeconds 5
            $result.ICMPStatus | Should -Be 'Success'
            $result.TCPStatus | Should -Be 'Error'
        }
    }

    # Mock [System.Net.Dns]::GetHostAddresses for Test-DNSResolution
    Context 'Test-DNSResolution' {
        It 'returns Success when DNS resolution returns addresses' {
            Mock -CommandName '[System.Net.Dns]::GetHostAddresses' -MockWith @(
                [PSCustomObject]@{
                    IPAddressToString = '93.184.216.34'
                },
                [PSCustomObject]@{
                    IPAddressToString = '2606:2800:220:1:248:1893:25c8:1946'
                }
            ) -Verifiable -ParameterFilter { $Hostname -eq 'example.com' }

            $result = Test-DNSResolution -Hostname 'example.com' -TimeoutSeconds 5
            $result.Status | Should -Be 'Success'
            $result.ResolvedAddresses | Should -Be '93.184.216.34,2606:2800:220:1:248:1893:25c8:1946'
            Verify-MockCalled '[System.Net.Dns]::GetHostAddresses'
        }

        It 'returns Failed when DNS resolution returns no addresses' {
            Mock -CommandName '[System.Net.Dns]::GetHostAddresses' -MockWith @() -Verifiable
            $result = Test-DNSResolution -Hostname 'nonexistent.example' -TimeoutSeconds 5
            $result.Status | Should -Be 'Failed'
            $result.ResolvedAddresses | Should -Be ''
        }

        It 'returns Error when DNS resolution throws' {
            Mock -CommandName '[System.Net.Dns]::GetHostAddresses' -MockWith { throw 'No such host is known' } -Verifiable
            $result = Test-DNSResolution -Hostname 'invalid' -TimeoutSeconds 5
            $result.Status | Should -Be 'Error'
        }
    }


        It 'returns Timeout when DNS resolution times out' {
            # Create a task that never completes
            $delayedTask = [System.Threading.Tasks.Task]::Delay([System.Threading.Timeout]::Infinite)
            Mock -CommandName '[System.Net.Dns]::GetHostAddressesAsync' -MockWith { $delayedTask } -Verifiable -ParameterFilter { $Hostname -eq 'example.com' }
            $result = Test-DNSResolution -Hostname 'example.com' -TimeoutSeconds 1
            $result.Status | Should -Be 'Timeout'
            Verify-MockCalled '[System.Net.Dns]::GetHostAddressesAsync'
        }
    # Mock TCP client for Test-TCPConnectivity
    Context 'Test-TCPConnectivity' {
        It 'returns Connected when TCP connection succeeds' {
            $mockTcpClient = [System.Net.Sockets.TcpClient]::new()
            $mockAsyncResult = [System.IAsyncResult]::new()  # We'll need to mock properly
            # Instead of complex mocking, we'll simulate by mocking the BeginConnect and EndConnect
            Mock -CommandName 'System.Net.Sockets.TcpClient::new' -MockWith {
                $client = [System.Net.Sockets.TcpClient]::new()
                $client | Add-Member -NotePropertyName 'Connected' -NotePropertyValue $true -PassThru
            } -Verifiable
            Mock -CommandName 'System.Net.Sockets.TcpClient::BeginConnect' -MockWith {
                param($host, $port, $callback, $state)
                # Return a completed async result
                $ares = [System.Threading.Tasks.Task]::FromResult($null)
                $ares
            } -Verifiable
            Mock -CommandName 'System.Net.Sockets.TcpClient::EndConnect' -MockWith { } -Verifiable
            Mock -CommandName 'System.Net.Sockets.TcpClient::Close' -MockWith { } -Verifiable
            Mock -CommandName '[System.Threading.WaitHandle]::WaitOne' -MockWith { $true } -Verifiable  # Simulate immediate success

            $result = Test-TCPConnectivity -Hostname 'example.com' -Port 80 -TimeoutSeconds 5
            $result.Connected | Should -Be $true
            $result.ErrorMessage | Should -BeNullOrEmpty
        }

        It 'returns Timeout when connection attempt times out' {
            Mock -CommandName '[System.Threading.WaitHandle]::WaitOne' -MockWith { $false } -Verifiable  # Simulate timeout
            Mock -CommandName 'System.Net.Sockets.TcpClient::new' -MockWith {
                $client = [System.Net.Sockets.TcpClient]::new()
                $client | Add-Member -NotePropertyName 'Connected' -NotePropertyValue $false -PassThru
            } -Verifiable
            Mock -CommandName 'System.Net.Sockets.TcpClient::Close' -MockWith { } -Verifiable

            $result = Test-TCPConnectivity -Hostname 'example.com' -Port 80 -TimeoutSeconds 5
            $result.Connected | Should -Be $false
            $result.ErrorMessage | Should -Be 'Timeout'
        }

        It 'returns Error when TCP client throws exception' {
            Mock -CommandName 'System.Net.Sockets.TcpClient::new' -MockWith { throw 'No such host' } -Verifiable
            $result = Test-TCPConnectivity -Hostname 'invalid' -Port 80 -TimeoutSeconds 5
            $result.Connected | Should -Be $false
            $result.ErrorMessage | Should -Match 'No such host'
        }
    }
}

Describe 'Test-NetworkConnectivity - Main Script Behavior' {

    It 'returns a report object when -AsObject is used' {
        # Mock all external dependencies to return predictable results
        Mock Get-LocalNetworkConfig -MockWith { @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
            }
        ) }
        Mock Get-DefaultGateways -MockWith { @(
            [PSCustomObject]@{ Address = '192.168.1.1'; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4' }
        ) }
        Mock Test-GatewayReachability -MockWith {
            [PSCustomObject]@{
                GatewayAddress = '192.168.1.1'
                AddressFamily = 'IPv4'
                ICMPStatus = 'Success'
                ICMPLatencyMS = 2
                TCPStatus = 'Success'
            }
        }
        Mock Test-DNSResolution -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Status = 'Success'
                ResolvedAddresses = '127.0.0.1'
            }
        }
        Mock Test-TCPConnectivity -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Port = 80
                Connected = $true
                LatencyMS = $null
                ErrorMessage = $null
            }
        }

        # Invoke the script with -AsObject
        $result = & $scriptPath -AsObject -ComputerName @('localhost') -Port @(80) -TimeoutSeconds 2

        $result | Should -Not -BeNullOrEmpty
        $result.GeneratedAt | Should -Not -BeNullOrEmpty
        $result.NetworkConfiguration | Should -Not -BeNullOrEmpty
        $result.Gateways | Should -Not -BeNullOrEmpty
        $result.GatewayReachability | Should -Not -BeNullOrEmpty
        $result.DNSResolution | Should -Not -BeNullOrEmpty
        $result.TCPConnectivity | Should -Not -BeNullOrEmpty
    }

    It 'exports CSV when ExportCsvPath is provided' {
        # Mock dependencies
        Mock Get-LocalNetworkConfig -MockWith { @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
            }
        ) }
        Mock Get-DefaultGateways -MockWith { @(
            [PSCustomObject]@{ Address = '192.168.1.1'; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4' }
        ) }
        Mock Test-GatewayReachability -MockWith {
            [PSCustomObject]@{
                GatewayAddress = '192.168.1.1'
                AddressFamily = 'IPv4'
                ICMPStatus = 'Success'
                ICMPLatencyMS = 2
                TCPStatus = 'Success'
            }
        }
        Mock Test-DNSResolution -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Status = 'Success'
                ResolvedAddresses = '127.0.0.1'
            }
        }
        Mock Test-TCPConnectivity -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Port = 80
                Connected = $true
                LatencyMS = $null
                ErrorMessage = $null
            }
        }

        # Create a temporary file for export
        $tempFile = [IO.Path]::GetTempFileName()
        try {
            & $scriptPath -ExportCsvPath $tempFile -ComputerName @('localhost') -Port @(80) -TimeoutSeconds 2

            # Check that the file exists and has content
            $exported = Import-Csv -Path $tempFile
            $exported | Should -Not -BeNullOrEmpty
            $exported.Category | Should -Contain 'GatewayReachability'
            $exported.Category | Should -Contain 'DNSResolution'
            $exported.Category | Should -Contain 'TCPConnectivity'
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }

    It 'exports JSON when ExportJsonPath is provided' {
        # Mock dependencies (same as above)
        Mock Get-LocalNetworkConfig -MockWith { @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
            }
        ) }
        Mock Get-DefaultGateways -MockWith { @(
            [PSCustomObject]@{ Address = '192.168.1.1'; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4' }
        ) }
        Mock Test-GatewayReachability -MockWith {
            [PSCustomObject]@{
                GatewayAddress = '192.168.1.1'
                AddressFamily = 'IPv4'
                ICMPStatus = 'Success'
                ICMPLatencyMS = 2
                TCPStatus = 'Success'
            }
        }
        Mock Test-DNSResolution -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Status = 'Success'
                ResolvedAddresses = '127.0.0.1'
            }
        }
        Mock Test-TCPConnectivity -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Port = 80
                Connected = $true
                LatencyMS = $null
                ErrorMessage = $null
            }
        }

        $tempFile = [IO.Path]::GetTempFileName()
        try {
            & $scriptPath -ExportJsonPath $tempFile -ComputerName @('localhost') -Port @(80) -TimeoutSeconds 2

            $jsonContent = Get-Content -Path $tempFile -Raw
            $jsonObject = $jsonContent | ConvertFrom-Json
            $jsonObject | Should -Not -BeNullOrEmpty
            $jsonObject.GeneratedAt | Should -Not -BeNullOrEmpty
            $jsonObject.Gateways | Should -Not -BeNullOrEmpty
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }

    It 'exports HTML when ExportHtmlPath is provided' {
        # Mock dependencies (same as above)
        Mock Get-LocalNetworkConfig -MockWith { @(
            [PSCustomObject]@{
                InterfaceAlias = 'Ethernet'
                IPv4Address = @(@{IPAddress = '192.168.1.100'})
                IPv6Address = @()
            }
        ) }
        Mock Get-DefaultGateways -MockWith { @(
            [PSCustomObject]@{ Address = '192.168.1.1'; InterfaceAlias = 'Ethernet'; AddressFamily = 'IPv4' }
        ) }
        Mock Test-GatewayReachability -MockWith {
            [PSCustomObject]@{
                GatewayAddress = '192.168.1.1'
                AddressFamily = 'IPv4'
                ICMPStatus = 'Success'
                ICMPLatencyMS = 2
                TCPStatus = 'Success'
            }
        }
        Mock Test-DNSResolution -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Status = 'Success'
                ResolvedAddresses = '127.0.0.1'
            }
        }
        Mock Test-TCPConnectivity -MockWith {
            [PSCustomObject]@{
                Hostname = 'localhost'
                Port = 80
                Connected = $true
                LatencyMS = $null
                ErrorMessage = $null
            }
        }

        $tempFile = [IO.Path]::GetTempFileName()
        try {
            & $scriptPath -ExportHtmlPath $tempFile -ComputerName @('localhost') -Port @(80) -TimeoutSeconds 2

            $htmlContent = Get-Content -Path $tempFile -Raw
            $htmlContent | Should -Contain '<h1>Network Connectivity Report</h1>'
            $htmlContent | Should -Contain '<h2>Gateway Reachability</h2>'
            $htmlContent | Should -Contain '<h2>DNS Resolution</h2>'
            $htmlContent | Should -Contain '<h2>TCP Connectivity</h2>'
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        }
    }
}
