Describe "Get-DiskUsage calculations" {
    It "calculates used space correctly" {
        $size = 100GB
        $free = 25GB
        $used = $size - $free

        $usedGB = [math]::Round($used / 1GB, 2)
        $usedPercent = [math]::Round(($used / $size) * 100, 2)

        $usedGB | Should Be 75
        $usedPercent | Should Be 75
    }

    It "handles a completely free drive" {
        $size = 100GB
        $free = 100GB
        $usedPercent = [math]::Round((($size - $free) / $size) * 100, 2)

        $usedPercent | Should Be 0
    }
}
