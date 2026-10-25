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
    $Port = @(80, 443),

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 300)]
    [int]
    $TimeoutSeconds = 5,

    [string]
    $ExportCsvPath,

    [string]
    $ExportJsonPath,

    [string]
    $ExportHtmlPath,

    [switch]
    $AsObject
)

#region Dependency Wrappers (for testability)


function Resolve-DnsName {
    param(
        [string]$Hostname,
        [int]$TimeoutSeconds
    )

    $task = [System.Net.Dns]::GetHostAddressesAsync($Hostname)
    $waitResult = $task.Wait(
        [TimeSpan]::FromSeconds($TimeoutSeconds).TotalMilliseconds
    )

    if (-not $waitResult) {
        throw [System.TimeoutException]::new(
            "DNS resolution timed out for '$Hostname' after $TimeoutSeconds seconds."
        )
    }

    return $task.GetAwaiter().GetResult()
}


function Test-TcpConnection {
    param(
        [string]$Hostname,
        [int]$Port,
        [int]$TimeoutSeconds
    )
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($Hostname, $Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        try {
            if (-not $waitHandle.WaitOne([Timespan]::FromSeconds($TimeoutSeconds), $false)) {
                $tcpClient.Close()
                return @{ Connected = $false; ErrorMessage = 'Timeout' }
            }
            $tcpClient.EndConnect($asyncResult)
            $connected = $true
        }
        finally {
            $waitHandle.Close()
        }
        $tcpClient.Close()
        return @{ Connected = $true; ErrorMessage = $null }
    }
    catch {
        if ($tcpClient -and $tcpClient.Connected) { $tcpClient.Close() }
        return @{ Connected = $false; ErrorMessage = $_.Exception.Message }
    }
}

function Test-ICMPPing {
    param(
        [string]$ComputerName,
        [int]$Count,
        [int]$TimeoutSeconds
    )
    try {
        $result = Test-Connection -ComputerName $ComputerName -Count $Count -ErrorAction SilentlyContinue
        if ($result) {
            return @{ Success = $true; ResponseTime = [math]::Round($result.ResponseTime, 2) }
        }
        return @{ Success = $false; ResponseTime = $null }
    }
    catch {
        return @{ Success = $false; ResponseTime = $null; Error = $_.Exception.Message }
    }
}


function Test-TCPPort {
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$TimeoutSeconds
    )

    try {
        $result = Test-TcpConnection `
            -Hostname $ComputerName `
            -Port $Port `
            -TimeoutSeconds $TimeoutSeconds

        $errorMessage = $result.ErrorMessage

        return @{
            TcpTestSucceeded = [bool]$result.Connected
            Error = if ($errorMessage -and $errorMessage -ne 'Timeout') {
                $errorMessage
            } else {
                $null
            }
        }
    }
    catch {
        return @{
            TcpTestSucceeded = $false
            Error = $_.Exception.Message
        }
    }
}


#endregion

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
                    Address         = $gw.NextHop
                    InterfaceAlias  = $interface.InterfaceAlias
                    AddressFamily   = 'IPv4'
                }
            }
        }
        if ($interface.IPv6DefaultGateway) {
            foreach ($gw in $interface.IPv6DefaultGateway) {
                $gateways += [PSCustomObject]@{
                    Address         = $gw.NextHop
                    InterfaceAlias  = $interface.InterfaceAlias
                    AddressFamily   = 'IPv6'
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
    $icmpResult = $null
    $icmpLatency = $null
    $ping = Test-ICMPPing -ComputerName $GatewayAddress -Count 1 -TimeoutSeconds $TimeoutSeconds
    if ($ping.Success) {
        $icmpResult = 'Success'
        $icmpLatency = $ping.ResponseTime
    }
    elseif ($ping.Error) {
        $icmpResult = 'Error'
    }
    else {
        $icmpResult = 'Failed'
    }

    $tcpTest = Test-TCPPort -ComputerName $GatewayAddress -Port 80 -TimeoutSeconds $TimeoutSeconds
    $tcpResult = if ($tcpTest.TcpTestSucceeded) { 'Success' } elseif ($tcpTest.Error) { 'Error' } else { 'Failed' }
    return [PSCustomObject]@{
        GatewayAddress  = $GatewayAddress
        AddressFamily   = $AddressFamily
        ICMPStatus      = $icmpResult
        ICMPLatencyMS   = $icmpLatency
        TCPStatus       = $tcpResult
    }
}

function Test-DNSResolution {
    param(
        [string]$Hostname,
        [int]$TimeoutSeconds
    )
    $addresses = @()
    $status = "Failed"
    try {
        $ips = Resolve-DnsName -Hostname $Hostname -TimeoutSeconds $TimeoutSeconds
        if ($ips.Count -gt 0) {
            foreach ($ip in $ips) {
                $addresses += $ip.IPAddressToString
            }
            $status = "Success"
        }
        else {
            $status = "Failed"
        }
    }
    catch {
        if ($_.Exception -is [System.TimeoutException]) {
            $status = "Timeout"
        }
        else {
            $status = "Error"
        }
    }
    return [PSCustomObject]@{
        Hostname           = $Hostname
        Status             = $status
        ResolvedAddresses  = ($addresses -join ", ")
    }
}

function Test-TCPConnectivity {
    param(
        [string]$Hostname,
        [int]$Port,
        [int]$TimeoutSeconds
    )
    $result = Test-TcpConnection -Hostname $Hostname -Port $Port -TimeoutSeconds $TimeoutSeconds
    return [PSCustomObject]@{
        Hostname     = $Hostname
        Port         = $Port
        Connected    = $result.Connected
        LatencyMS    = $null
        ErrorMessage = $result.ErrorMessage
    }
}

#region Main Logic (exposed for testing)

function Invoke-NetworkDiagnostics {
    param(
        [string[]]$ComputerName,
        [int[]]$Port,
        [int]$TimeoutSeconds,
        [string]$ExportCsvPath,
        [string]$ExportJsonPath,
        [string]$ExportHtmlPath,
        [switch]$AsObject
    )

    $generatedAt = Get-Date

    $networkConfig = Get-LocalNetworkConfig
    $gateways = Get-DefaultGateways

    $gatewayResults = @()
    foreach ($gw in $gateways) {
        $result = Test-GatewayReachability -GatewayAddress $gw.Address -AddressFamily $gw.AddressFamily -TimeoutSeconds $TimeoutSeconds
        $gatewayResults += [PSCustomObject]@{
            GatewayAddress  = $gw.Address
            InterfaceAlias  = $gw.InterfaceAlias
            AddressFamily   = $gw.AddressFamily
            ICMPStatus      = $result.ICMPStatus
            ICMPLatencyMS   = $result.ICMPLatencyMS
            TCPStatus       = $result.TCPStatus
        }
    }

    $dnsResults = @()
    foreach ($name in $ComputerName) {
        $dnsResults += Test-DNSResolution -Hostname $name -TimeoutSeconds $TimeoutSeconds
    }

    $tcpResults = @()
    foreach ($name in $ComputerName) {
        foreach ($targetPort in $Port) {
            $tcpResults += Test-TCPConnectivity -Hostname $name -Port $targetPort -TimeoutSeconds $TimeoutSeconds
        }
    }

    $report = [PSCustomObject]@{
        GeneratedAt          = $generatedAt
        NetworkConfiguration = $networkConfig
        Gateways             = $gateways
        GatewayReachability  = $gatewayResults
        DNSResolution        = $dnsResults
        TCPConnectivity      = $tcpResults
    }

    if ($ExportCsvPath) {
        $csvRows = @()

        # Define common schema for all CSV rows to ensure Export-Csv includes all columns
        # Export-Csv uses the first object's properties as schema, so we ensure all objects have all possible properties
        $commonProperties = @(
            'GeneratedAt', 'Category',
            'GatewayAddress', 'InterfaceAlias', 'AddressFamily', 'ICMPStatus', 'ICMPLatencyMS', 'TCPStatus',
            'Hostname', 'Status', 'ResolvedAddresses',
            'Port', 'Connected', 'LatencyMS', 'ErrorMessage'
        )

        foreach ($gw in $gatewayResults) {
            $row = [PSCustomObject]@{
                GeneratedAt     = $generatedAt
                Category        = 'GatewayReachability'
                GatewayAddress  = $gw.GatewayAddress
                InterfaceAlias  = $gw.InterfaceAlias
                AddressFamily   = $gw.AddressFamily
                ICMPStatus      = $gw.ICMPStatus
                ICMPLatencyMS   = $gw.ICMPLatencyMS
                TCPStatus       = $gw.TCPStatus
                Hostname        = $null
                Status          = $null
                ResolvedAddresses = $null
                Port            = $null
                Connected       = $null
                LatencyMS       = $null
                ErrorMessage    = $null
            }
            $csvRows += $row | Select-Object $commonProperties
        }

        foreach ($dns in $dnsResults) {
            $row = [PSCustomObject]@{
                GeneratedAt       = $generatedAt
                Category          = 'DNSResolution'
                GatewayAddress    = $null
                InterfaceAlias    = $null
                AddressFamily     = $null
                ICMPStatus        = $null
                ICMPLatencyMS     = $null
                TCPStatus         = $null
                Hostname          = $dns.Hostname
                Status            = $dns.Status
                ResolvedAddresses = $dns.ResolvedAddresses
                Port              = $null
                Connected         = $null
                LatencyMS         = $null
                ErrorMessage      = $null
            }
            $csvRows += $row | Select-Object $commonProperties
        }

        foreach ($tcp in $tcpResults) {
            $row = [PSCustomObject]@{
                GeneratedAt   = $generatedAt
                Category      = 'TCPConnectivity'
                GatewayAddress = $null
                InterfaceAlias = $null
                AddressFamily  = $null
                ICMPStatus     = $null
                ICMPLatencyMS  = $null
                TCPStatus      = $null
                Hostname       = $tcp.Hostname
                Status         = $null
                ResolvedAddresses = $null
                Port           = $tcp.Port
                Connected      = $tcp.Connected
                LatencyMS      = $tcp.LatencyMS
                ErrorMessage   = $tcp.ErrorMessage
            }
            $csvRows += $row | Select-Object $commonProperties
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
        $htmlStyleLines = @(
            '<meta http-equiv="refresh" content="300">'
            '<style>'
            'body { font-family: Arial; margin: 30px; color: #222; }'
            'h1, h2 { color: #174a7e; }'
            'table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }'
            'th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }'
            'th { background: #174a7e; color: white; }'
            'tr:nth-child(even) { background: #f2f2f2; }'
            '</style>'
        )
        $htmlStyle = $htmlStyleLines -join "`n"

        $html = @()
        $html += "<h1>Network Connectivity Report</h1>"
        $html += "<p>Generated: $($report.GeneratedAt)</p>"

        if ($report.NetworkConfiguration) {
            $html += "<h2>Network Configuration</h2>"
            $html += ($report.NetworkConfiguration | ConvertTo-Html -Fragment)
        }

        if ($report.Gateways) {
            $html += "<h2>Default Gateways</h2>"
            $html += ($report.Gateways | ConvertTo-Html -Fragment)
        }

        if ($report.GatewayReachability) {
            $html += "<h2>Gateway Reachability</h2>"
            $html += ($report.GatewayReachability | ConvertTo-Html -Fragment)
        }

        if ($report.DNSResolution) {
            $html += "<h2>DNS Resolution</h2>"
            $html += ($report.DNSResolution | ConvertTo-Html -Fragment)
        }

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

    # When not -AsObject, still return the report for pipeline use
    return $report
}

#endregion

# Main script body (only executes when invoked directly, not when dot-sourced for testing)
# $global:TestMode is set by test file before dot-sourcing to prevent main body execution during tests
# Check CommandType to distinguish direct invocation (ExternalScript) from dot-sourcing
$isEntryPoint = ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') -and ($PSCommandPath -eq $MyInvocation.MyCommand.Definition)
$isTestMode = $global:TestMode
if (-not $isTestMode -and $isEntryPoint) {
    try {
        $report = Invoke-NetworkDiagnostics `
            -ComputerName $ComputerName `
            -Port $Port `
            -TimeoutSeconds $TimeoutSeconds `
            -ExportCsvPath $ExportCsvPath `
            -ExportJsonPath $ExportJsonPath `
            -ExportHtmlPath $ExportHtmlPath `
            -AsObject

        if ($AsObject) {
            # Return report object without console output
            return $report
        }

        # Console output for direct invocation (human-readable)
        Write-Host "`n=== NETWORK CONFIGURATION ===" -ForegroundColor Cyan
        if ($report.NetworkConfiguration) {
            $report.NetworkConfiguration | Format-List InterfaceAlias, IPv4Address, IPv6Address
        }
        else {
            Write-Output "Network configuration unavailable."
        }

        Write-Host "`n=== DEFAULT GATEWAYS ===" -ForegroundColor Cyan
        if (@($report.Gateways).Count -gt 0) {
            $report.Gateways | Format-Table InterfaceAlias, AddressFamily, Address -AutoSize
        }
        else {
            Write-Output "No default gateways found."
        }

        Write-Host "`n=== GATEWAY REACHABILITY ===" -ForegroundColor Cyan
        if ($report.GatewayReachability.Count -gt 0) {
            $report.GatewayReachability | Format-Table GatewayAddress, InterfaceAlias, AddressFamily, ICMPStatus, ICMPLatencyMS, TCPStatus -AutoSize
        }
        else {
            Write-Output "Gateway reachability tests not performed."
        }

        Write-Host "`n=== DNS RESOLUTION ===" -ForegroundColor Cyan
        if ($report.DNSResolution.Count -gt 0) {
            $report.DNSResolution | Format-Table Hostname, Status, ResolvedAddresses -AutoSize
        }
        else {
            Write-Output "DNS resolution tests not performed."
        }

        Write-Host "`n=== TCP CONNECTIVITY ===" -ForegroundColor Cyan
        if ($report.TCPConnectivity.Count -gt 0) {
            $report.TCPConnectivity | Format-Table Hostname, Port, Connected, LatencyMS, ErrorMessage -AutoSize
        }
        else {
            Write-Output "TCP connectivity tests not performed."
        }
    }
    catch {
        throw "Network connectivity diagnostics failed: $($_.Exception.Message)"
    }
}


