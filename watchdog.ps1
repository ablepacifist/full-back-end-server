# Watchdog: monitors Lexicon services and auto-restarts if any go down
# Usage: Start in background via restart-all.ps1 or manually:
#   Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File watchdog.ps1" -WindowStyle Hidden

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$logsDir = Join-Path $BASE_DIR "logs"
$logFile = Join-Path $logsDir "watchdog.log"
$checkInterval = 30  # seconds between checks

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Out-File -Append -FilePath $logFile
}

function Test-Port($port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

# Auto-detects the ext4 media drive by GPT partition type GUID instead of a
# fixed PHYSICALDRIVE/partition number, so this survives Windows re-enumerating
# disks after the machine is physically moved/reseated (same approach as
# restart-all.ps1's mount step).
$linuxDataGuid = "{0fc63daf-8483-4772-8e79-3d69d8477de4}"  # GPT "Linux filesystem data" type

function Find-LexiconStoragePath {
    $candidateDisks = Get-Disk | Where-Object { -not $_.IsSystem }
    foreach ($disk in $candidateDisks) {
        $linuxPartitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.GptType -eq $linuxDataGuid }
        foreach ($part in $linuxPartitions) {
            $mountPath = "\\wsl.localhost\Ubuntu\mnt\wsl\PHYSICALDRIVE$($disk.Number)p$($part.PartitionNumber)\lexicon-storage"
            if (Test-Path $mountPath) {
                return $mountPath
            }
        }
    }
    return $null
}

function Mount-LexiconStorageDisks {
    $candidateDisks = Get-Disk | Where-Object { -not $_.IsSystem }
    foreach ($disk in $candidateDisks) {
        $linuxPartitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.GptType -eq $linuxDataGuid }
        foreach ($part in $linuxPartitions) {
            $mountPath = "\\wsl.localhost\Ubuntu\mnt\wsl\PHYSICALDRIVE$($disk.Number)p$($part.PartitionNumber)"
            if (Test-Path $mountPath) { continue }
            Start-Process -FilePath "wsl" -ArgumentList "--mount", "\\.\PHYSICALDRIVE$($disk.Number)", "--partition", "$($part.PartitionNumber)", "--type", "ext4" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
    }
}

New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
Write-Log "Watchdog started. Checking every ${checkInterval}s."

while ($true) {
    Start-Sleep -Seconds $checkInterval

    $needsRestart = $false

    # Check ext4 HDD
    if (-not (Find-LexiconStoragePath)) {
        Write-Log "ALERT: ext4 HDD not accessible - triggering full restart"
        $needsRestart = $true
    }

    # Check WSL is alive (Java needs it for UNC path resolution)
    $wslRunning = wsl -d Ubuntu -e bash -c "echo OK" 2>&1
    if ($wslRunning -notmatch "OK") {
        Write-Log "ALERT: WSL Ubuntu not running - restarting"
        wsl --shutdown 2>$null
        Start-Sleep 2
        Start-Process wsl -ArgumentList "-d","Ubuntu","--","sleep","infinity" -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Write-Log "WSL Ubuntu restarted"
    }

    # Check HDD mount (may be lost after WSL restart)
    if (-not (Find-LexiconStoragePath)) {
        Write-Log "ALERT: HDD not accessible - remounting via wsl --mount"
        Mount-LexiconStorageDisks
        Start-Sleep 3
        if (Find-LexiconStoragePath) {
            Write-Log "HDD remounted successfully"
        } else {
            Write-Log "WARNING: HDD remount failed"
        }
    }

    # Check Cloudflare Tunnel (Windows Service)
    $cfService = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
    if ($cfService -and $cfService.Status -ne 'Running') {
        Write-Log "ALERT: Cloudflared service is $($cfService.Status) - restarting service"
        Start-Process sc.exe -ArgumentList "start","Cloudflared" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        $cfService = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
        if ($cfService.Status -eq 'Running') {
            Write-Log "Cloudflared service restarted successfully"
        } else {
            Write-Log "WARNING: Cloudflared still not running after restart attempt"
        }
    }

    # Check critical ports
    $services = @(
        @{ Name = "HSQLDB";        Port = 9002  },
        @{ Name = "AlchemyServer"; Port = 8080  },
        @{ Name = "LexiconServer"; Port = 36568 },
        @{ Name = "Frontend";      Port = 3001  }
    )

    foreach ($svc in $services) {
        if (-not (Test-Port $svc.Port)) {
            Write-Log "ALERT: $($svc.Name) not listening on port $($svc.Port) - triggering full restart"
            $needsRestart = $true
        }
    }

    # Check PlayIt tunnel
    $playitProc = Get-Process -Name "playit" -ErrorAction SilentlyContinue
    if (-not $playitProc) {
        Write-Log "ALERT: PlayIt not running - restarting"
        $playit = "C:\Program Files\playit_gg\bin\playit.exe"
        if (Test-Path $playit) {
            Start-Process -FilePath $playit -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Write-Log "PlayIt restarted"
        }
    }

    if ($needsRestart) {
        Write-Log "Running restart-all.ps1 ..."
        try {
            & "$BASE_DIR\restart-all.ps1" 2>&1 | Out-File -Append -FilePath $logFile
            Write-Log "restart-all.ps1 completed"
        } catch {
            Write-Log "ERROR running restart-all.ps1: $_"
        }
        # Wait extra time after restart before next check
        Start-Sleep -Seconds 60
    }
}
