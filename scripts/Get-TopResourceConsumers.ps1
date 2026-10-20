[CmdletBinding()]
param(
    [ValidateRange(1, 10)]
    [int]$SampleSeconds = 2,

    [ValidateRange(1, 50)]
    [int]$Top = 10,

    [string]$ExportCsvPath,
    [string]$ExportJsonPath,
    [string]$ExportHtmlPath
)

$ErrorActionPreference = 'Stop'

# Capture the initial process CPU and I/O counters.
$logicalProcessors = [Environment]::ProcessorCount
$sampleTimer = [System.Diagnostics.Stopwatch]::StartNew()
$firstSample = @{}

Get-CimInstance Win32_Process | ForEach-Object {
    $firstSample[[int]$_.ProcessId] = @{
        CPU = [double]$_.KernelModeTime + [double]$_.UserModeTime
        ReadBytes = [double]$_.ReadTransferCount
        WriteBytes = [double]$_.WriteTransferCount
    }
}

Start-Sleep -Seconds $SampleSeconds

# Refresh process details after the sampling interval.
$servicesByProcess = @{}
Get-CimInstance Win32_Service | ForEach-Object {
    $processId = [int]$_.ProcessId

    if ($processId -gt 0) {
        if (-not $servicesByProcess.ContainsKey($processId)) {
            $servicesByProcess[$processId] = [System.Collections.Generic.List[string]]::new()
        }

        $servicesByProcess[$processId].Add([string]$_.Name)
    }
}

$secondSample = Get-CimInstance Win32_Process
$sampleTimer.Stop()
$elapsedSeconds = [Math]::Max(0.1, $sampleTimer.Elapsed.TotalSeconds)
$processes = foreach ($process in $secondSample) {
    $processId = [int]$process.ProcessId

    if ($processId -eq 0) {
        continue
    }

    $previous = $firstSample[$processId]

    $cpuPercent = $null
    $readMBPerSec = $null
    $writeMBPerSec = $null

    if ($null -ne $previous) {
        $currentCpu = [double]$process.KernelModeTime + [double]$process.UserModeTime
        $cpuDelta = [Math]::Max(0, $currentCpu - $previous.CPU)

        # CIM CPU times are in 100-nanosecond units.
        $cpuSeconds = $cpuDelta / 10000000
        $cpuPercent = [Math]::Round(
            ($cpuSeconds / $elapsedSeconds / $logicalProcessors) * 100,
            2
        )

        $readDelta = [Math]::Max(
            0,
            [double]$process.ReadTransferCount - $previous.ReadBytes
        )
        $writeDelta = [Math]::Max(
            0,
            [double]$process.WriteTransferCount - $previous.WriteBytes
        )

        $readMBPerSec = [Math]::Round(
            $readDelta / 1MB / $elapsedSeconds,
            3
        )
        $writeMBPerSec = [Math]::Round(
            $writeDelta / 1MB / $elapsedSeconds,
            3
        )
    }

    $serviceNames = ''
    if ($servicesByProcess.ContainsKey($processId)) {
        $serviceNames = $servicesByProcess[$processId] -join ', '
    }

    $workingSetMB = $null
    try {
        $liveProcess = Get-Process -Id $processId -ErrorAction Stop
        $workingSetMB = [Math]::Round($liveProcess.WorkingSet64 / 1MB, 2)
    }
    catch {
        # A process can exit between the CIM query and Get-Process.
    }

    [PSCustomObject]@{
        ProcessName   = [IO.Path]::GetFileNameWithoutExtension([string]$process.Name)
        ProcessId     = $processId
        CPUPercent    = $cpuPercent
        MemoryMB      = $workingSetMB
        IOReadMBPerSec  = $readMBPerSec
        IOWriteMBPerSec = $writeMBPerSec
        ThreadCount   = [int]$process.ThreadCount
        HandleCount   = [int]$process.HandleCount
        Services      = $serviceNames
        ExecutablePath = [string]$process.ExecutablePath
    }
}

$processes = @($processes | Sort-Object ProcessName)

$report = [PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    GeneratedAt  = Get-Date
    SampleSeconds = $SampleSeconds
    LogicalProcessors = $logicalProcessors
    Notes = @(
        'CPUPercent is normalized across all logical processors; it may differ from Task Manager per-process CPU display.'
        'Process I/O rates are cumulative process I/O counters, not direct physical disk throughput.'
        'Processes started during sampling may have unavailable CPU and I/O rates.'
        'Windows does not provide reliable per-process network traffic through this script.'
    )
    TopCPU = @($processes | Where-Object { $null -ne $_.CPUPercent } |
        Sort-Object CPUPercent -Descending | Select-Object -First $Top)
    TopMemory = @($processes | Where-Object { $null -ne $_.MemoryMB } |
        Sort-Object MemoryMB -Descending | Select-Object -First $Top)
    TopIORead = @($processes | Where-Object { $null -ne $_.IOReadMBPerSec } |
        Sort-Object IOReadMBPerSec -Descending | Select-Object -First $Top)
    TopIOWrite = @($processes | Where-Object { $null -ne $_.IOWriteMBPerSec } |
        Sort-Object IOWriteMBPerSec -Descending | Select-Object -First $Top)
}

Write-Host "`n=== TOP CPU PROCESSES ===" -ForegroundColor Cyan
$report.TopCPU |
    Format-Table ProcessName, ProcessId, CPUPercent, MemoryMB, Services -AutoSize

Write-Host "`n=== TOP MEMORY PROCESSES ===" -ForegroundColor Cyan
$report.TopMemory |
    Format-Table ProcessName, ProcessId, MemoryMB, CPUPercent, Services -AutoSize

Write-Host "`n=== TOP PROCESS I/O READERS ===" -ForegroundColor Cyan
$report.TopIORead |
    Format-Table ProcessName, ProcessId, IOReadMBPerSec, Services -AutoSize

Write-Host "`n=== TOP PROCESS I/O WRITERS ===" -ForegroundColor Cyan
$report.TopIOWrite |
    Format-Table ProcessName, ProcessId, IOWriteMBPerSec, Services -AutoSize

if ($ExportCsvPath) {
    $rankings = @(
        @{ ResourceType = 'CPU'; Processes = $report.TopCPU }
        @{ ResourceType = 'Memory'; Processes = $report.TopMemory }
        @{ ResourceType = 'IORead'; Processes = $report.TopIORead }
        @{ ResourceType = 'IOWrite'; Processes = $report.TopIOWrite }
    )

    $csvRows = foreach ($ranking in $rankings) {
        foreach ($process in $ranking.Processes) {
            [PSCustomObject]@{
                ResourceType   = $ranking.ResourceType
                ProcessName    = $process.ProcessName
                ProcessId      = $process.ProcessId
                CPUPercent     = $process.CPUPercent
                MemoryMB       = $process.MemoryMB
                IOReadMBPerSec = $process.IOReadMBPerSec
                IOWriteMBPerSec = $process.IOWriteMBPerSec
                Services       = $process.Services -join '; '
            }
        }
    }

    $csvRows | Export-Csv -Path $ExportCsvPath -NoTypeInformation
    Write-Host "Resource consumer CSV exported to: $ExportCsvPath"
}
if ($ExportJsonPath) {
    $report | ConvertTo-Json -Depth 5 |
        Set-Content -Path $ExportJsonPath -Encoding UTF8
    Write-Host "JSON report exported to: $ExportJsonPath"
}

if ($ExportHtmlPath) {
    $html = @"
<html>
<head>
<meta charset="utf-8">
<title>Top Resource Consumers - $env:COMPUTERNAME</title>
<style>
body { font-family: Arial, sans-serif; margin: 24px; }
table { border-collapse: collapse; margin-bottom: 24px; width: 100%; }
th, td { border: 1px solid #ccc; padding: 7px; text-align: left; }
th { background: #eee; }
</style>
</head>
<body>
<h1>Top Resource Consumers</h1>
<p>Computer: $env:COMPUTERNAME | Generated: $(Get-Date)</p>
<h2>Top CPU Processes</h2>
$($report.TopCPU | ConvertTo-Html -Fragment)
<h2>Top Memory Processes</h2>
$($report.TopMemory | ConvertTo-Html -Fragment)
<h2>Top Process I/O Readers</h2>
$($report.TopIORead | ConvertTo-Html -Fragment)
<h2>Top Process I/O Writers</h2>
$($report.TopIOWrite | ConvertTo-Html -Fragment)
</body>
</html>
"@
    Set-Content -Path $ExportHtmlPath -Value $html -Encoding UTF8
    Write-Host "HTML report exported to: $ExportHtmlPath"
}

# Return the complete report for pipelines and automation.
$report



