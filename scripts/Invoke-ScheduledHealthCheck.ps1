[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$reportDir = Join-Path $projectRoot "reports"
$healthScript = Join-Path $PSScriptRoot "Get-ServerHealth.ps1"

$json = Join-Path $reportDir "latest-server-health.json"
$csv  = Join-Path $reportDir "latest-server-health.csv"
$html = Join-Path $reportDir "latest-server-health.html"
$log  = Join-Path $reportDir "scheduled-health-check.log"

if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

function Write-HealthCheckLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $entry = "{0} {1} {2}" -f (
        Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ), $Level, $Message

    Add-Content -LiteralPath $log -Encoding UTF8 -Value $entry `
        -ErrorAction Stop
}

try {
    if (-not (Test-Path -LiteralPath $healthScript -PathType Leaf)) {
        throw "Health script not found: $healthScript"
    }

    & $healthScript `
        -ExportJsonPath $json `
        -ExportCsvPath $csv `
        -ExportHtmlPath $html `
        -ErrorAction Stop | Out-Null

    # Do not report success if any expected report is missing or empty.
    foreach ($path in @($json, $csv, $html)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected report was not created: $path"
        }

        if ((Get-Item -LiteralPath $path).Length -le 0) {
            throw "Report is empty: $path"
        }
    }

    # Validate JSON structure and overall status.
    $report = Get-Content -LiteralPath $json -Raw |
        ConvertFrom-Json -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace([string]$report.OverallStatus)) {
        throw "JSON report has no overall health status."
    }

    if ($null -eq $report.System) {
        throw "JSON report has no system information."
    }

    # Validate CSV data and status consistency.
    $csvRows = @(Import-Csv -LiteralPath $csv -ErrorAction Stop)

    if ($csvRows.Count -eq 0) {
        throw "CSV report contains no data rows."
    }

    $overallRows = @(
        $csvRows | Where-Object { $_.Category -eq "Overall" }
    )

    if ($overallRows.Count -eq 0) {
        throw "CSV report has no Overall row."
    }

    if ([string]$overallRows[0].Status -ne [string]$report.OverallStatus) {
        throw "JSON and CSV overall health statuses do not match."
    }

    # Validate the HTML report's expected content.
    $htmlContent = Get-Content -LiteralPath $html -Raw `
        -ErrorAction Stop

    if ($htmlContent -notmatch 'Server Health Report') {
        throw "HTML report is missing its expected title."
    }

    Write-HealthCheckLog -Level "SUCCESS" -Message (
        "Reports generated and validated. OverallStatus={0}" -f
        $report.OverallStatus
    )
}
catch {
    $errorMessage = $_.Exception.Message

    try {
        Write-HealthCheckLog -Level "ERROR" -Message $errorMessage
    }
    catch {
        Write-Error "Could not write the failure to the health-check log: $($_.Exception.Message)"
    }

    throw $errorMessage
}
