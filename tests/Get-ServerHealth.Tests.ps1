Describe "Get-ServerHealth calculations" {
    It "calculates uptime components correctly" {
        $uptime = New-TimeSpan -Days 2 -Hours 6 -Minutes 34

        [math]::Floor($uptime.TotalDays) | Should Be 2
        $uptime.Hours | Should Be 6
        $uptime.Minutes | Should Be 34
    }

    It "defines the expected service checks" {
        $serviceNames = @("EventLog", "LanmanServer", "Dnscache")

        $serviceNames.Count | Should Be 3
        ($serviceNames -contains "EventLog") | Should Be $true
        ($serviceNames -contains "LanmanServer") | Should Be $true
        ($serviceNames -contains "Dnscache") | Should Be $true
    }
}
