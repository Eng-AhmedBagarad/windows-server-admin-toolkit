
Describe "Get-TopResourceConsumers export tests" {
    It "exports valid CSV, JSON, and HTML reports with all four resource rankings" {
        $scriptPath = Join-Path $PSScriptRoot "..\scripts\Get-TopResourceConsumers.ps1"
        $scriptPath = (Resolve-Path $scriptPath).Path

        $testRoot = Join-Path $env:TEMP (
            "TopResourceConsumersTests_" + [guid]::NewGuid().ToString("N")
        )

        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        try {
            $csvPath = Join-Path $testRoot "Resources.csv"
            $jsonPath = Join-Path $testRoot "Resources.json"
            $htmlPath = Join-Path $testRoot "Resources.html"

            & $scriptPath `
                -SampleSeconds 1 `
                -Top 3 `
                -ExportCsvPath $csvPath `
                -ExportJsonPath $jsonPath `
                -ExportHtmlPath $htmlPath |
                Out-Null

            # Verify all reports were created.
            Test-Path $csvPath | Should Be $true
            Test-Path $jsonPath | Should Be $true
            Test-Path $htmlPath | Should Be $true

            # Verify CSV contains all four resource types.
            $csv = @(Import-Csv $csvPath)
            ($csv.Count -gt 0) | Should Be $true

            $resourceTypes = @(
                $csv | Select-Object -ExpandProperty ResourceType -Unique
            )
            $resourceTypes.Count | Should Be 4

            ($resourceTypes -contains "CPU") | Should Be $true
($resourceTypes -contains "Memory") | Should Be $true
($resourceTypes -contains "IORead") | Should Be $true
($resourceTypes -contains "IOWrite") | Should Be $true

            # Verify JSON is valid and contains all rankings.
            $json = Get-Content $jsonPath -Raw | ConvertFrom-Json

            @($json.TopCPU).Count | Should BeGreaterThan 0
            @($json.TopMemory).Count | Should BeGreaterThan 0
            @($json.TopIORead).Count | Should BeGreaterThan 0
            @($json.TopIOWrite).Count | Should BeGreaterThan 0

            # Verify HTML contains all four report sections.
            $html = Get-Content $htmlPath -Raw

            $html | Should Match "Top CPU Processes"
            $html | Should Match "Top Memory Processes"
            $html | Should Match "Top Process I/O Readers"
            $html | Should Match "Top Process I/O Writers"
        }
        finally {
            Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
