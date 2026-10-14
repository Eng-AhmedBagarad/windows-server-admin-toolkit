[CmdletBinding()]
param()

try {
    $computer = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $uptime = (Get-Date) - $computer.LastBootUpTime

    $systemInfo = [PSCustomObject]@{
        ComputerName    = $computer.CSName
        OperatingSystem = $computer.Caption
        Version         = $computer.Version
        LastBootTime    = $computer.LastBootUpTime
        UptimeDays      = [math]::Floor($uptime.TotalDays)
        UptimeHours     = $uptime.Hours
        UptimeMinutes   = $uptime.Minutes
    }

    $serviceNames = @("EventLog", "LanmanServer", "Dnscache")

    $services = foreach ($name in $serviceNames) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue

        if ($null -ne $service) {
            [PSCustomObject]@{
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                Status      = $service.Status.ToString()
            }
        }
        else {
            [PSCustomObject]@{
                ServiceName = $name
                DisplayName = "Unavailable on this system"
                Status      = "NotFound"
            }
        }
    }

    Write-Output "=== System Information ==="
    $systemInfo | Format-List

    Write-Output "=== Selected Windows Services ==="
    $services | Format-Table -AutoSize
}
catch {
    Write-Error "Server health collection failed: $($_.Exception.Message)"
}
