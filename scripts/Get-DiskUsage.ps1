
<#
.SYNOPSIS
    Collects local fixed-disk capacity and health information.

.DESCRIPTION
    Returns structured disk objects for reporting and automation.
    Read-only: does not modify disks or files.
#>

[CmdletBinding()]
param(
    [ValidateRange(0, 100)]
    [double]$WarningThreshold = 80,

    [ValidateRange(0, 100)]
    [double]$CriticalThreshold = 90
)

if ($CriticalThreshold -le $WarningThreshold) {
    throw "CriticalThreshold must be greater than WarningThreshold."
}

try {
    $drives = @(
        Get-CimInstance -ClassName Win32_LogicalDisk `
            -Filter "DriveType = 3" `
            -ErrorAction Stop
    )

    if ($drives.Count -eq 0) {
        Write-Warning "No local fixed drives were found."
        return
    }

    foreach ($drive in $drives) {
        if ($null -eq $drive.Size -or
            $drive.Size -le 0 -or
            $null -eq $drive.FreeSpace) {
            Write-Warning "Skipping $($drive.DeviceID): capacity information is unavailable."
            continue
        }

        $usedBytes = $drive.Size - $drive.FreeSpace
        $usedPercent = [math]::Round(
            ($usedBytes / $drive.Size) * 100,
            2
        )

        if ($usedPercent -ge $CriticalThreshold) {
            $status = "Critical"
        }
        elseif ($usedPercent -ge $WarningThreshold) {
            $status = "Warning"
        }
        else {
            $status = "Healthy"
        }

        [PSCustomObject]@{
            Drive       = $drive.DeviceID
            VolumeName  = $drive.VolumeName
            TotalGB     = [math]::Round($drive.Size / 1GB, 2)
            UsedGB      = [math]::Round($usedBytes / 1GB, 2)
            FreeGB      = [math]::Round($drive.FreeSpace / 1GB, 2)
            UsedPercent = $usedPercent
            HealthStatus = $status
        }
    }
}
catch {
    throw "Disk usage collection failed: $($_.Exception.Message)"
}
