#
# .SYNOPSIS
#     Tests for Invoke-ScheduledHealthCheck.ps1 orchestration and validation logic.
#
# .DESCRIPTION
#     Uses a temporary test fixture containing a copy of Invoke-ScheduledHealthCheck.ps1
#     and a controllable stub for Get-ServerHealth.ps1. The real health script is never
#     executed. All temporary files live outside the repository and are removed in AfterAll.
#

Describe 'Invoke-ScheduledHealthCheck orchestration' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ("InvokeScheduledHealthCheckTests_" + [guid]::NewGuid().ToString("N"))
        $scriptsDir = Join-Path $tempRoot "scripts"
        $reportsDir = Join-Path $tempRoot "reports"

        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

        $realScript = Join-Path $PSScriptRoot "..\scripts\Invoke-ScheduledHealthCheck.ps1"
        $fixtureScript = Join-Path $scriptsDir "Invoke-ScheduledHealthCheck.ps1"
        Copy-Item -Path $realScript -Destination $fixtureScript

        $stubPath = Join-Path $scriptsDir "Get-ServerHealth.ps1"
        Set-Content -Path $stubPath -Value @'
[CmdletBinding()]
param(
    [string]$ExportJsonPath,
    [string]$ExportCsvPath,
    [string]$ExportHtmlPath
)

$scenario = $env:TEST_SCENARIO

switch ($scenario) {
    'missing-json' { break }
    'empty-json' { [System.IO.File]::WriteAllBytes($ExportJsonPath, [byte[]]::new(0)) }
    'invalid-json' { Set-Content -Path $ExportJsonPath -Value '{ invalid' -Encoding UTF8 }
    'missing-overallstatus' {
        $json = @{ System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    'missing-system' {
        $json = @{ OverallStatus = 'Healthy' } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    'status-mismatch' {
        $json = @{ OverallStatus = 'Critical'; System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    default {
        $json = @{ OverallStatus = 'Healthy'; System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
}

switch ($scenario) {
    'missing-csv' { break }
    'empty-csv' { Set-Content -Path $ExportCsvPath -Value 'Category,Status' -Encoding UTF8 }
    'missing-overall-row' {
        $csv = @(
            [PSCustomObject]@{ Category = 'CPU'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
    'status-mismatch' {
        $csv = @(
            [PSCustomObject]@{ Category = 'Overall'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
    default {
        $csv = @(
            [PSCustomObject]@{ Category = 'Overall'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
}

switch ($scenario) {
    'missing-html' { break }
    'missing-html-title' {
        Set-Content -Path $ExportHtmlPath -Value '<html><body>No title here</body></html>' -Encoding UTF8
    }
    default {
        Set-Content -Path $ExportHtmlPath -Value '<html><body><h1>Server Health Report</h1></body></html>' -Encoding UTF8
    }
}
'@ -Encoding UTF8

        $script:FixtureScript = $fixtureScript
        $script:FixtureReportsDir = $reportsDir
        $script:FixtureScriptsDir = $scriptsDir
        $script:FixtureTempRoot = $tempRoot
        $script:StubPath = $stubPath
        $script:OriginalTestScenario = $env:TEST_SCENARIO
    }

    BeforeEach {
        $env:TEST_SCENARIO = 'valid'

        Get-ChildItem -Path $script:FixtureReportsDir -File -ErrorAction SilentlyContinue | Remove-Item -Force

        # Recreate the stub (may have been removed by the "missing health script" test)
        Set-Content -Path $script:StubPath -Value @'
[CmdletBinding()]
param(
    [string]$ExportJsonPath,
    [string]$ExportCsvPath,
    [string]$ExportHtmlPath
)

$scenario = $env:TEST_SCENARIO

switch ($scenario) {
    'missing-json' { break }
    'empty-json' { [System.IO.File]::WriteAllBytes($ExportJsonPath, [byte[]]::new(0)) }
    'invalid-json' { Set-Content -Path $ExportJsonPath -Value '{ invalid' -Encoding UTF8 }
    'missing-overallstatus' {
        $json = @{ System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    'missing-system' {
        $json = @{ OverallStatus = 'Healthy' } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    'status-mismatch' {
        $json = @{ OverallStatus = 'Critical'; System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
    default {
        $json = @{ OverallStatus = 'Healthy'; System = @{} } | ConvertTo-Json -Depth 5
        Set-Content -Path $ExportJsonPath -Value $json -Encoding UTF8
    }
}

switch ($scenario) {
    'missing-csv' { break }
    'empty-csv' { Set-Content -Path $ExportCsvPath -Value 'Category,Status' -Encoding UTF8 }
    'missing-overall-row' {
        $csv = @(
            [PSCustomObject]@{ Category = 'CPU'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
    'status-mismatch' {
        $csv = @(
            [PSCustomObject]@{ Category = 'Overall'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
    default {
        $csv = @(
            [PSCustomObject]@{ Category = 'Overall'; Status = 'Healthy' }
        )
        $csv | Export-Csv -Path $ExportCsvPath -NoTypeInformation -Encoding UTF8
    }
}

switch ($scenario) {
    'missing-html' { break }
    'missing-html-title' {
        Set-Content -Path $ExportHtmlPath -Value '<html><body>No title here</body></html>' -Encoding UTF8
    }
    default {
        Set-Content -Path $ExportHtmlPath -Value '<html><body><h1>Server Health Report</h1></body></html>' -Encoding UTF8
    }
}
'@ -Encoding UTF8

        Mock Add-Content { }
        Mock Write-Error { }
    }

    AfterEach {
        $env:TEST_SCENARIO = $script:OriginalTestScenario
    }

    AfterAll {
        Remove-Item -Path $script:FixtureTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'validates matching JSON, CSV, and HTML reports successfully' {
        $env:TEST_SCENARIO = 'valid'

        { & $script:FixtureScript } | Should -Not -Throw

        Assert-MockCalled Add-Content -Exactly 1 -Scope It
    }

    It 'throws when the health script is missing' {
        Remove-Item -Path $script:StubPath -Force -ErrorAction SilentlyContinue

        { & $script:FixtureScript } | Should -Throw 'Health script not found*'
    }

    It 'throws when a report is missing' {
        $env:TEST_SCENARIO = 'missing-json'

        { & $script:FixtureScript } | Should -Throw 'Expected report was not created*'
    }

    It 'throws when a report is empty' {
        $env:TEST_SCENARIO = 'empty-json'

        { & $script:FixtureScript } | Should -Throw 'Report is empty*'
    }

    It 'throws when JSON is invalid' {
        $env:TEST_SCENARIO = 'invalid-json'

        { & $script:FixtureScript } | Should -Throw
    }

    It 'throws when OverallStatus is missing from JSON' {
        $env:TEST_SCENARIO = 'missing-overallstatus'

        { & $script:FixtureScript } | Should -Throw 'JSON report has no overall health status*'
    }

    It 'throws when System is missing from JSON' {
        $env:TEST_SCENARIO = 'missing-system'

        { & $script:FixtureScript } | Should -Throw 'JSON report has no system information*'
    }

    It 'throws when CSV is empty' {
        $env:TEST_SCENARIO = 'empty-csv'

        { & $script:FixtureScript } | Should -Throw 'CSV report contains no data rows*'
    }

    It 'throws when CSV has no Overall row' {
        $env:TEST_SCENARIO = 'missing-overall-row'

        { & $script:FixtureScript } | Should -Throw 'CSV report has no Overall row*'
    }

    It 'throws when JSON and CSV statuses do not match' {
        $env:TEST_SCENARIO = 'status-mismatch'

        { & $script:FixtureScript } | Should -Throw 'JSON and CSV overall health statuses do not match*'
    }

    It 'throws when HTML is missing the expected title' {
        $env:TEST_SCENARIO = 'missing-html-title'

        { & $script:FixtureScript } | Should -Throw 'HTML report is missing its expected title*'
    }

    It 'logs failure before rethrowing the error' {
        $env:TEST_SCENARIO = 'invalid-json'

        { & $script:FixtureScript } | Should -Throw

        Assert-MockCalled Add-Content -Exactly 1 -Scope It
    }
}
