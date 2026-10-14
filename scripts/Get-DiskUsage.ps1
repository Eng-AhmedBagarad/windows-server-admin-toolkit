<#
.SYNOPSIS
    Reports local disk capacity and utilization.

.DESCRIPTION
    Collects drive capacity, free space, and used-space percentage.
    Read-only: does not modify disks or files.
#>

[CmdletBinding()]
param()

try {
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop

    if (-not $drives) {
        Write-Warning "No local fixed drives were found."
        return
    }

    $report = foreach ($drive in $drives) {
        if ($null -eq $drive.Size -or $drive.Size -le 0) {
            Write-Warning "Skipping $($drive.DeviceID): capacity information is unavailable."
            continue
        }

        $usedBytes = $drive.Size - $drive.FreeSpace

        [PSCustomObject]@{
            Drive          = $drive.DeviceID
            VolumeName     = $drive.VolumeName
            TotalGB        = [math]::Round($drive.Size / 1GB, 2)
            UsedGB         = [math]::Round($usedBytes / 1GB, 2)
            FreeGB         = [math]::Round($drive.FreeSpace / 1GB, 2)
            UsedPercent    = [math]::Round(($usedBytes / $drive.Size) * 100, 2)
        }
    }

    if ($report) {
        $report | Format-Table -AutoSize
    }
}
catch {
    Write-Error "Disk usage collection failed: $($_.Exception.Message)"
}
