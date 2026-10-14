
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

    [switch]$AsObject
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

# CPU: average two samples
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

# RAM
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
        Resource = "CPU"
        UsagePercent = $cpuPercent
        HealthStatus = $cpuStatus
    }
    [PSCustomObject]@{
        Resource = "RAM"
        UsagePercent = $ramUsedPercent
        HealthStatus = $ramStatus
    }
)

# Disk data is collected by the standalone disk script
$disks = @()
$diskCollectionFailed = $false

try {
    $disks = @(
        & "$PSScriptRoot\Get-DiskUsage.ps1" `
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

# Selected services: defaults are examples, not universal role requirements
$services = foreach ($name in $ServiceName) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        [PSCustomObject]@{
            ServiceName = $name
            Status = "NotFound"
            HealthStatus = "Unknown"
        }
    }
    else {
        $serviceStatus = $service.Status.ToString()

        if ($serviceStatus -eq "Running") {
            $healthStatus = "Healthy"
        }
        else {
            $healthStatus = "Warning"
        }

        [PSCustomObject]@{
            ServiceName = $service.Name
            Status = $serviceStatus
            HealthStatus = $healthStatus
        }
    }
}

# Overall status: Critical takes precedence over Warning
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
    GeneratedAt = Get-Date
    OverallStatus = $overallStatus
    System = $system
    Resources = $resources
    Memory = [PSCustomObject]@{
        TotalGB = $ramTotalGB
        UsedGB = $ramUsedGB
        AvailableGB = $ramAvailableGB
        UsedPercent = $ramUsedPercent
    }
    Disks = $disks
    Services = @($services)
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
