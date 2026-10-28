
<#
.SYNOPSIS
    Collects and reports system health.

.DESCRIPTION
    Reports CPU, RAM, disk capacity, OS, uptime, and selected services.
    Read-only. No system configuration is changed.
#>

[CmdletBinding()]
param(
    [ValidateRange(0, 100)]
    [double]$CPUWarningThreshold = 80,

    [ValidateRange(0, 100)]
    [double]$CPUCriticalThreshold = 95,

    [ValidateRange(0, 100)]
    [double]$RAMWarningThreshold = 80,

    [ValidateRange(0, 100)]
    [double]$RAMCriticalThreshold = 90,

    [ValidateRange(0, 100)]
    [double]$DiskWarningThreshold = 80,

    [ValidateRange(0, 100)]
    [double]$DiskCriticalThreshold = 90,

    [string[]]$ServiceName = @("EventLog", "LanmanServer", "Dnscache"),

    [hashtable]$ExpectedServiceState = @{},

    [switch]$AsObject,

    [string]$ExportJsonPath,
    [string]$ExportCsvPath,
    [string]$ExportHtmlPath
)

$thresholdPairs = @(
    @($CPUWarningThreshold, $CPUCriticalThreshold),
    @($RAMWarningThreshold, $RAMCriticalThreshold),
    @($DiskWarningThreshold, $DiskCriticalThreshold)
)

foreach ($pair in $thresholdPairs) {
    if ($pair[1] -le $pair[0]) {
        throw "Each critical threshold must be greater than its warning threshold."
    }
}

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
}
catch {
    throw "Cannot collect operating system information: $($_.Exception.Message)"
}

$uptime = (Get-Date) - $os.LastBootUpTime

$system = [PSCustomObject]@{
    ComputerName    = $os.CSName
    OperatingSystem = $os.Caption
    Version         = $os.Version
    LastBootTime    = $os.LastBootUpTime
    UptimeDays      = [math]::Floor($uptime.TotalDays)
    UptimeHours     = $uptime.Hours
    UptimeMinutes   = $uptime.Minutes
}

# CPU: average two samples.
$cpuPercent = $null
$cpuStatus = "Unknown"

try {
    $samples = Get-Counter '\Processor(_Total)\% Processor Time' `
        -SampleInterval 1 -MaxSamples 2 -ErrorAction Stop |
        Select-Object -ExpandProperty CounterSamples

    $cpuPercent = [math]::Round(
        ($samples | Measure-Object -Property CookedValue -Average).Average,
        2
    )

    if ($cpuPercent -ge $CPUCriticalThreshold) {
        $cpuStatus = "Critical"
    }
    elseif ($cpuPercent -ge $CPUWarningThreshold) {
        $cpuStatus = "Warning"
    }
    else {
        $cpuStatus = "Healthy"
    }
}
catch {
    Write-Warning "CPU collection failed: $($_.Exception.Message)"
}

# RAM.
$totalKB = $os.TotalVisibleMemorySize
$availableKB = $os.FreePhysicalMemory
$usedKB = $totalKB - $availableKB

if ($totalKB -gt 0) {
    $ramUsedPercent = [math]::Round(($usedKB / $totalKB) * 100, 2)
    $ramTotalGB = [math]::Round($totalKB / 1MB, 2)
    $ramUsedGB = [math]::Round($usedKB / 1MB, 2)
    $ramAvailableGB = [math]::Round($availableKB / 1MB, 2)

    if ($ramUsedPercent -ge $RAMCriticalThreshold) {
        $ramStatus = "Critical"
    }
    elseif ($ramUsedPercent -ge $RAMWarningThreshold) {
        $ramStatus = "Warning"
    }
    else {
        $ramStatus = "Healthy"
    }
}
else {
    $ramUsedPercent = $null
    $ramTotalGB = $null
    $ramUsedGB = $null
    $ramAvailableGB = $null
    $ramStatus = "Unknown"
}

$resources = @(
    [PSCustomObject]@{
        Resource     = "CPU"
        UsagePercent = $cpuPercent
        HealthStatus = $cpuStatus
    }
    [PSCustomObject]@{
        Resource     = "RAM"
        UsagePercent = $ramUsedPercent
        HealthStatus = $ramStatus
    }
)

# Disk data is collected by the standalone disk script.
$disks = @()
$diskCollectionFailed = $false

try {
    $diskScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-DiskUsage.ps1'

    $disks = @(
        & $diskScript `
            -WarningThreshold $DiskWarningThreshold `
            -CriticalThreshold $DiskCriticalThreshold `
            -ErrorAction Stop
    )

    if ($disks.Count -eq 0) {
        $diskCollectionFailed = $true
        Write-Warning "No disk data was returned."
    }
}
catch {
    $diskCollectionFailed = $true
    Write-Warning "Disk collection failed: $($_.Exception.Message)"
}

# Selected services: defaults are examples, not universal role requirements.
$services = foreach ($name in $ServiceName) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        [PSCustomObject]@{
            ServiceName = $name
            Status      = "NotFound"
            HealthStatus = "Unknown"
        }
    }
    else {
        $serviceStatus = $service.Status.ToString()

        # Transitional and paused states are always a warning, regardless of expectation.
        $transitionalStates = @("StartPending", "StopPending", "ContinuePending", "PausePending", "Paused")
        if ($transitionalStates -contains $serviceStatus) {
            $healthStatus = "Warning"
        }
        else {
            $expectedState = if ($ExpectedServiceState.ContainsKey($name)) {
                $ExpectedServiceState[$name]
            }
            else {
                "Running"
            }

            if ($serviceStatus -eq $expectedState) {
                $healthStatus = "Healthy"
            }
            else {
                $healthStatus = "Warning"
            }
        }

        [PSCustomObject]@{
            ServiceName  = $service.Name
            Status       = $serviceStatus
            HealthStatus = $healthStatus
        }
    }
}

# Overall status: Critical takes precedence over Warning.
$allStatuses = @($cpuStatus, $ramStatus)
$allStatuses += @($disks | ForEach-Object { $_.HealthStatus })
$allStatuses += @($services | ForEach-Object { $_.HealthStatus })

if ($diskCollectionFailed) {
    $allStatuses += "Unknown"
}

if ($allStatuses -contains "Critical") {
    $overallStatus = "Critical"
}
elseif ($allStatuses -contains "Warning") {
    $overallStatus = "Warning"
}
elseif ($allStatuses -contains "Unknown") {
    $overallStatus = "Unknown"
}
else {
    $overallStatus = "Healthy"
}

$report = [PSCustomObject]@{
    GeneratedAt   = Get-Date
    OverallStatus = $overallStatus
    System        = $system
    Resources     = $resources
    Memory        = [PSCustomObject]@{
        TotalGB     = $ramTotalGB
        UsedGB      = $ramUsedGB
        AvailableGB = $ramAvailableGB
        UsedPercent = $ramUsedPercent
    }
    Disks    = $disks
    Services = @($services)
}

# Export JSON.
if (-not [string]::IsNullOrWhiteSpace($ExportJsonPath)) {
    $jsonDirectory = Split-Path -Parent $ExportJsonPath

    if ($jsonDirectory -and -not (Test-Path -LiteralPath $jsonDirectory -PathType Container)) {
        throw "JSON export directory does not exist: $jsonDirectory"
    }

    $report |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $ExportJsonPath -Encoding UTF8 -ErrorAction Stop

    Write-Verbose "JSON report saved to: $ExportJsonPath"
}

# Export CSV.
if (-not [string]::IsNullOrWhiteSpace($ExportCsvPath)) {
    $csvDirectory = Split-Path -Parent $ExportCsvPath

    if ($csvDirectory -and -not (Test-Path -LiteralPath $csvDirectory -PathType Container)) {
        throw "CSV export directory does not exist: $csvDirectory"
    }

    $csvRows = @()

    $csvRows += [PSCustomObject]@{
        GeneratedAt   = $report.GeneratedAt
        ComputerName  = $system.ComputerName
        OverallStatus = $report.OverallStatus
        Category      = "Overall"
        Name          = "Overall Health"
        Status        = $report.OverallStatus
        UsagePercent  = $null
        Details       = ""
    }

    $csvRows += [PSCustomObject]@{
        GeneratedAt   = $report.GeneratedAt
        ComputerName  = $system.ComputerName
        OverallStatus = $report.OverallStatus
        Category      = "System"
        Name          = $system.OperatingSystem
        Status        = "Information"
        UsagePercent  = $null
        Details       = "Version=$($system.Version); UptimeDays=$($system.UptimeDays)"
    }

    foreach ($resource in $resources) {
        $csvRows += [PSCustomObject]@{
            GeneratedAt   = $report.GeneratedAt
            ComputerName  = $system.ComputerName
            OverallStatus = $report.OverallStatus
            Category      = "Resource"
            Name          = $resource.Resource
            Status        = $resource.HealthStatus
            UsagePercent  = $resource.UsagePercent
            Details       = ""
        }
    }

    foreach ($disk in $disks) {
        $csvRows += [PSCustomObject]@{
            GeneratedAt   = $report.GeneratedAt
            ComputerName  = $system.ComputerName
            OverallStatus = $report.OverallStatus
            Category      = "Disk"
            Name          = $disk.Drive
            Status        = $disk.HealthStatus
            UsagePercent  = $disk.UsedPercent
            Details       = "TotalGB=$($disk.TotalGB); FreeGB=$($disk.FreeGB)"
        }
    }

    foreach ($service in $services) {
        $csvRows += [PSCustomObject]@{
            GeneratedAt   = $report.GeneratedAt
            ComputerName  = $system.ComputerName
            OverallStatus = $report.OverallStatus
            Category      = "Service"
            Name          = $service.ServiceName
            Status        = $service.HealthStatus
            UsagePercent  = $null
            Details       = "ServiceStatus=$($service.Status)"
        }
    }

    $csvRows |
        Export-Csv -LiteralPath $ExportCsvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Verbose "CSV report saved to: $ExportCsvPath"
}

# Export HTML.
if (-not [string]::IsNullOrWhiteSpace($ExportHtmlPath)) {
    $htmlDirectory = Split-Path -Parent $ExportHtmlPath

    if ($htmlDirectory -and -not (Test-Path -LiteralPath $htmlDirectory -PathType Container)) {
        throw "HTML export directory does not exist: $htmlDirectory"
    }

    $htmlStyle = @"
<meta http-equiv="refresh" content="300">
<style>
body { font-family: Arial, sans-serif; margin: 30px; color: #222; }
h1, h2 { color: #174a7e; }
table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #174a7e; color: white; }
tr:nth-child(even) { background: #f2f2f2; }
</style>
"@

    $html = @()
    $html += "<h1>Server Health Report</h1>"
    $html += "<p>Generated: $($report.GeneratedAt)</p>"
    $html += "<h2>Overall Status: $($report.OverallStatus)</h2>"
    $html += "<h2>System Information</h2>"
    $html += ($report.System | ConvertTo-Html -Fragment)
    $html += "<h2>Resources</h2>"
    $html += ($report.Resources | ConvertTo-Html -Fragment)
    $html += "<h2>Disks</h2>"
    $html += ($report.Disks | ConvertTo-Html -Fragment)
    $html += "<h2>Services</h2>"
    $html += ($report.Services | ConvertTo-Html -Fragment)

    $page = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Server Health Report</title>
$htmlStyle
</head>
<body>
$($html -join "`n")
</body>
</html>
"@

    Set-Content -LiteralPath $ExportHtmlPath -Value $page -Encoding UTF8 -ErrorAction Stop

    Write-Verbose "HTML report saved to: $ExportHtmlPath"
}

if ($AsObject) {
    $report
    return
}

Write-Output "=== Overall Health: $overallStatus ==="
Write-Output "Generated: $($report.GeneratedAt)"
Write-Output "`n=== System Information ==="
$system | Format-List

Write-Output "=== Resource Utilization ==="
$resources | Format-Table -AutoSize

Write-Output "=== Disk Health ==="
if ($disks.Count -gt 0) {
    $disks | Format-Table Drive, TotalGB, UsedGB, FreeGB, UsedPercent, HealthStatus -AutoSize
}
else {
    Write-Output "Disk data unavailable."
}

Write-Output "=== Selected Service Health ==="
$services | Format-Table -AutoSize
