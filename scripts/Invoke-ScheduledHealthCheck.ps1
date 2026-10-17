$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$reportDir = Join-Path $projectRoot "reports"
$healthScript = Join-Path $PSScriptRoot "Get-ServerHealth.ps1"

if (!(Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$json = Join-Path $reportDir "latest-server-health.json"
$csv  = Join-Path $reportDir "latest-server-health.csv"
$html = Join-Path $reportDir "latest-server-health.html"
$log  = Join-Path $reportDir "scheduled-health-check.log"

try {
    & $healthScript `
        -ExportJsonPath $json `
        -ExportCsvPath $csv `
        -ExportHtmlPath $html | Out-Null

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Health script returned exit code $LASTEXITCODE"
    }

    Add-Content -LiteralPath $log -Encoding UTF8 -Value (
        "{0} SUCCESS Reports updated." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    )
}
catch {
    Add-Content -LiteralPath $log -Encoding UTF8 -Value (
        "{0} ERROR {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message
    )
    throw
}
