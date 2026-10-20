#
# .SYNOPSIS
#     Performs read-only network and DNS diagnostics.
#
# .DESCRIPTION
#     Reports local network configuration, gateway reachability, DNS resolution,
#     and TCP connectivity. Designed for safe monitoring without modifying
#     system state.
#
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]
    $ComputerName = @('localhost', '127.0.0.1'),

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int[]]
    $Port = @(80, 443)

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 300)]
    [int]
    $TimeoutSeconds = 5

    [string]
    $ExportCsvPath

    [string]
    $ExportJsonPath

    [string]
    $ExportHtmlPath

    [switch]
    $AsObject
)

function Get-LocalNetworkConfig {
    try {
        $ipConfig = Get-NetIPConfiguration -ErrorAction Stop
        return $ipConfig
    }
    catch {
        Write-Warning "Unable to retrieve network configuration: $($_.Exception.Message)"
        return $null
    }
}

function Get-DefaultGateways {
    $ipConfig = Get-LocalNetworkConfig
    if ($null -eq $ipConfig) { return @() }

    $gateways = @()
    foreach ($interface in $ipConfig) {
        if ($interface.IPv4DefaultGateway) {
            foreach ($gw in $interface.IPv4DefaultGateway) {
                $gateways += [PSCustomObject]@{
                    Address = $gw.NextHop
                    InterfaceAlias = $interface.InterfaceAlias
                    AddressFamily = 'IPv4'
                }
            }
        }
        if ($interface.IPv6DefaultGateway) {
            foreach ($gw in $interface.IPv6DefaultGateway) {
                $gateways += [PSCustomObject]@{
                    Address = $gw.NextHop
                    InterfaceAlias = $interface.InterfaceAlias
                    AddressFamily = 'IPv6'
                }
            }
        }
    }
    return $gateways
}

function Test-GatewayReachability {
    param(
        [string]$GatewayAddress,
        [string]$AddressFamily,
        [int]$TimeoutSeconds
    )
    # Try ICMP first (supplemental)
    $icmpResult = $null
    $icmpLatency = $null
    try {
        $ping = Test-Connection -ComputerName $GatewayAddress -Count 1 -TimeoutSeconds $TimeoutSeconds -ErrorAction SilentlyContinue
        if ($ping) {
            $icmpResult = 'Success'
            $icmpLatency = [math]::Round($ping.ResponseTime, 2)
        }
        else {
            $icmpResult = 'Failed'
        }
    }
    catch {
        $icmpResult = 'Error'
    }

    # Try TCP to a common port (e.g., 80) as a more reliable reachability test
    $tcpResult = $null
    $tcpLatency = $null
    try {
        $tcpTest = Test-NetConnection -ComputerName $GatewayAddress -Port 80 -WarningLevel SilentlyContinue -InformationLevel Quiet -TimeoutSeconds $TimeoutSeconds
        if ($tcpTest.TcpTestSucceeded) {
            $tcpResult = 'Success'
            # Note: Test-NetConnection does not return latency by default in Quiet mode.
            # We can do a separate TCP connection measurement if needed, but for simplicity we skip.
        }
        else {
            $tcpResult = 'Failed'
        }
    }
    catch {
        $tcpResult = 'Error'
    }

    return [PSCustomObject]@{
        GatewayAddress = $GatewayAddress
        AddressFamily = $AddressFamily
        ICMPStatus = $icmpResult
        ICMPLatencyMS = $icmpLatency
        TCPStatus = $tcpResult
        # TCPLatencyMS is not measured here for simplicity; could be added with a custom TCP socket timing.
    }
}

function Test-DNSResolution {
    param(
        [string]$Hostname,
        [int]$TimeoutSeconds
    )
    $addresses = @()
    $status = "Failed"
    $resolvedAddresses = @()
    try {
        $task = [System.Net.Dns]::GetHostAddressesAsync($Hostname)
        $waitResult = $task.Wait(([Timespan]::FromSeconds($TimeoutSeconds)).Milliseconds)
        if ($waitResult) {
            $ips = $task.Result
            foreach ($ip in $ips) {
                $addresses += $ip.IPAddressToString
            }
            if ($addresses.Count -gt 0) {
                $status = "Success"
            } else {
                $status = "Failed"
            }
        } else {
            $status = "Timeout"
        }
    } catch {
        $status = "Error"
    }
    return [PSCustomObject]@{
        Hostname = $Hostname
        Status = $status
        ResolvedAddresses = ($addresses -join ", ")
    }
}function Test-TCPConnectivity {
    param(
        [string]$Hostname,
        [int]$Port,
        [int]$TimeoutSeconds
    )
    $connected = $false
    $latencyMs = $null
    $errorMessage = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($Hostname, $Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        try {
            if (!$waitHandle.WaitOne([Timespan]::FromSeconds($TimeoutSeconds), $false)) {
                $errorMessage = 'Timeout'
                $tcpClient.Close()
                return [PSCustomObject]@{
                    Hostname = $Hostname
                    Port = $Port
                    Connected = $false
                    LatencyMS = $null
                    ErrorMessage = $errorMessage
                }
            }
            $tcpClient.EndConnect($asyncResult)
            $connected = $true
        }
        finally {
            $waitHandle.Close()
        }

        # Measure latency by timing the connection? We already timed the wait, but we can do a separate measurement.
        # For simplicity, we'll skip latency measurement for TCP in this version.
        # We can optionally measure by recording timestamps before and after Connect.
        $tcpClient.Close()
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($tcpClient -and $tcpClient.Connected) { $tcpClient.Close() }
    }

    return [PSCustomObject]@{
        Hostname = $Hostname
        Port = $Port
        Connected = $connected
        LatencyMS = $latencyMs
        ErrorMessage = $errorMessage
    }
}

# Main script body
try {
    $generatedAt = Get-Date

    # 1. Local network configuration
    $networkConfig = Get-LocalNetworkConfig

    # 2. Default gateways
    $gateways = Get-DefaultGateways

    # 3. Gateway reachability
    $gatewayResults = @()
    foreach ($gw in $gateways) {
        $result = Test-GatewayReachability -GatewayAddress $gw.Address -AddressFamily $gw.AddressFamily -TimeoutSeconds $TimeoutSeconds
        $gatewayResults += [PSCustomObject]@{
            GatewayAddress = $gw.Address
            InterfaceAlias = $gw.InterfaceAlias
            AddressFamily = $gw.AddressFamily
            ICMPStatus = $result.ICMPStatus
            ICMPLatencyMS = $result.ICMPLatencyMS
            TCPStatus = $result.TCPStatus
        }
    }

    # 4. DNS resolution
    $dnsResults = @()
    foreach ($name in $ComputerName) {
        $dnsResults += Test-DNSResolution -Hostname $name -TimeoutSeconds $TimeoutSeconds
    }

    # 5. TCP connectivity
    $tcpResults = @()
    foreach ($name in $ComputerName) {
        foreach ($port in $Port) {
            $tcpResults += Test-TCPConnectivity -Hostname $name -Port $port -TimeoutSeconds $TimeoutSeconds
        }
    }

    # Build report object
    $report = [PSCustomObject]@{
        GeneratedAt = $generatedAt
        NetworkConfiguration = $networkConfig
        Gateways = $gateways
        GatewayReachability = $gatewayResults
        DNSResolution = $dnsResults
        TCPConnectivity = $tcpResults
    }

    # Export functionality (similar to existing scripts)
    if ($ExportCsvPath) {
        # We'll create a flat CSV for each relevant section, or choose one?
        # For simplicity, we'll export the TCPConnectivity results as CSV since they are structured.
        # But the requirement says: Optional CSV, JSON, and HTML exports consistent with the existing toolkit.
        # We'll follow the pattern of Get-TopResourceConsumers which exports a CSV with multiple rankings.
        # We'll create a CSV that combines all test results in a flat format.

        $csvRows = @()

        # Add gateway reachability
        foreach ($gw in $gatewayResults) {
            $csvRows += [PSCustomObject]@{
                GeneratedAt = $generatedAt
                Category = 'GatewayReachability'
                GatewayAddress = $gw.GatewayAddress
                InterfaceAlias = $gw.InterfaceAlias
                AddressFamily = $gw.AddressFamily
                ICMPStatus = $gw.ICMPStatus
                ICMPLatencyMS = $gw.ICMPLatencyMS
                TCPStatus = $gw.TCPStatus
            }
        }

        # Add DNS resolution
        foreach ($dns in $dnsResults) {
            $csvRows += [PSCustomObject]@{
                GeneratedAt = $generatedAt
                Category = 'DNSResolution'
                Hostname = $dns.Hostname
                Status = $dns.Status
                ResolvedAddresses = $dns.ResolvedAddresses
            }
        }

        # Add TCP connectivity
        foreach ($tcp in $tcpResults) {
            $csvRows += [PSCustomObject]@{
                GeneratedAt = $generatedAt
                Category = 'TCPConnectivity'
                Hostname = $tcp.Hostname
                Port = $tcp.Port
                Connected = $tcp.Connected
                LatencyMS = $tcp.LatencyMS
                ErrorMessage = $tcp.ErrorMessage
            }
        }

        $csvDirectory = Split-Path -Parent $ExportCsvPath
        if ($csvDirectory -and -not (Test-Path -LiteralPath $csvDirectory -PathType Container)) {
            throw "CSV export directory does not exist: $csvDirectory"
        }

        $csvRows | Export-Csv -LiteralPath $ExportCsvPath -NoTypeInformation -Encoding UTF8
        Write-Verbose "CSV report saved to: $ExportCsvPath"
    }

    if ($ExportJsonPath) {
        $jsonDirectory = Split-Path -Parent $ExportJsonPath
        if ($jsonDirectory -and -not (Test-Path -LiteralPath $jsonDirectory -PathType Container)) {
            throw "JSON export directory does not exist: $jsonDirectory"
        }

        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ExportJsonPath -Encoding UTF8
        Write-Verbose "JSON report saved to: $ExportJsonPath"
    }

    if ($ExportHtmlPath) {
        $htmlStyle = @"
<meta http-equiv="refresh" content="300">
<style>
body { font-family: Arial; margin: 30px; color: #222; }
h1, h2 { color: #174a7e; }
table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #174a7e; color: white; }
tr:nth-child(even) { background: #f2f2f2; }
</style>
"@

        $html = @()
        $html += "<h1>Network Connectivity Report</h1>"
        $html += "<p>Generated: $($report.GeneratedAt)</p>"

        # Network Configuration (simplified)
        if ($report.NetworkConfiguration) {
            $html += "<h2>Network Configuration</h2>"
            $html += ($report.NetworkConfiguration | ConvertTo-Html -Fragment)
        }

        # Gateways
        if ($report.Gateways) {
            $html += "<h2>Default Gateways</h2>"
            $html += ($report.Gateways | ConvertTo-Html -Fragment)
        }

        # Gateway Reachability
        if ($report.GatewayReachability) {
            $html += "<h2>Gateway Reachability</h2>"
            $html += ($report.GatewayReachability | ConvertTo-Html -Fragment)
        }

        # DNS Resolution
        if ($report.DNSResolution) {
            $html += "<h2>DNS Resolution</h2>"
            $html += ($report.DNSResolution | ConvertTo-Html -Fragment)
        }

        # TCP Connectivity
        if ($report.TCPConnectivity) {
            $html += "<h2>TCP Connectivity</h2>"
            $html += ($report.TCPConnectivity | ConvertTo-Html -Fragment)
        }

        $page = ConvertTo-Html -Title "Network Connectivity Report" -Head $htmlStyle -Body ($html -join "`n")
        Set-Content -LiteralPath $ExportHtmlPath -Value $page -Encoding UTF8
        Write-Verbose "HTML report saved to: $ExportHtmlPath"
    }

    if ($AsObject) {
        return $report
    }

    # Default console output
    Write-Host "`n=== NETWORK CONFIGURATION ===" -ForegroundColor Cyan
    if ($networkConfig) {
        $networkConfig | Format-List InterfaceAlias, IPv4Address, IPv6Address
    }
    else {
        Write-Output "Network configuration unavailable."
    }

    Write-Host "`n=== DEFAULT GATEWAYS ===" -ForegroundColor Cyan
    if ($gateways.Count -gt 0) {
        $gateways | Format-Table InterfaceAlias, AddressFamily, Address -AutoSize
    }
    else {
        Write-Output "No default gateways found."
    }

    Write-Host "`n=== GATEWAY REACHABILITY ===" -ForegroundColor Cyan
    if ($gatewayResults.Count -gt 0) {
        $gatewayResults | Format-Table GatewayAddress, InterfaceAlias, AddressFamily, ICMPStatus, ICMPLatencyMS, TCPStatus -AutoSize
    }
    else {
        Write-Output "Gateway reachability tests not performed."
    }

    Write-Host "`n=== DNS RESOLUTION ===" -ForegroundColor Cyan
    if ($dnsResults.Count -gt 0) {
        $dnsResults | Format-Table Hostname, Status, ResolvedAddresses -AutoSize
    }
    else {
        Write-Output "DNS resolution tests not performed."
    }

    Write-Host "`n=== TCP CONNECTIVITY ===" -ForegroundColor Cyan
    if ($tcpResults.Count -gt 0) {
        $tcpResults | Format-Table Hostname, Port, Connected, LatencyMS, ErrorMessage -AutoSize
    }
    else {
        Write-Output "TCP connectivity tests not performed."
    }
}
catch {
    throw "Network connectivity diagnostics failed: $($_.Exception.Message)"
}
