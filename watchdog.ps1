# Watchdog: monitors Lexicon services and auto-restarts if any go down
# Usage: Start in background via restart-all.ps1 or manually:
#   Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File watchdog.ps1" -WindowStyle Hidden

$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$logsDir = Join-Path $BASE_DIR "logs"
$logFile = Join-Path $logsDir "watchdog.log"
$checkInterval = 30  # seconds between checks

# Destination registry (the ONE place ports/hosts come from) - see scripts/env.ps1.
. (Join-Path $BASE_DIR "scripts\env.ps1")
$env:MASTER_ENV_FILE = Join-Path $BASE_DIR ".env"

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

    # Re-read the registry each loop so an edit to .env takes effect on the
    # watchdog's own next check without needing a restart of the watchdog itself.
    $cfg = Get-RegistryConfig -BaseDir $BASE_DIR

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
        @{ Name = "HSQLDB";        Port = [int]$cfg.DB_PORT },
        @{ Name = "AlchemyServer"; Port = [int]$cfg.ALCHEMY_PORT },
        @{ Name = "LexiconServer"; Port = [int]$cfg.LEXICON_PORT },
        @{ Name = "PokemonServer"; Port = [int]$cfg.POKEMON_PORT },
        @{ Name = "Frontend";      Port = [int]$cfg.FRONTEND_PORT }
    )

    foreach ($svc in $services) {
        if (-not (Test-Port $svc.Port)) {
            Write-Log "ALERT: $($svc.Name) not listening on port $($svc.Port) - triggering full restart"
            $needsRestart = $true
        }
    }

    # Check Lexi (voice daemon).
    # Restarted on its own rather than added to the port list above: those trigger a full
    # restart-all, and taking the website, media server and tunnels down because a voice
    # daemon died would be a far worse outage than the one being fixed.
    $lexiPython = Join-Path $BASE_DIR "Lexi\.venv\Scripts\python.exe"
    if ((Test-Path $lexiPython) -and -not (Test-Port $cfg.LEXI_PORT)) {
        Write-Log "ALERT: Lexi not listening on port $($cfg.LEXI_PORT) - restarting it"
        $lexiDir = Join-Path $BASE_DIR "Lexi"
        $lexiLog = Join-Path $logsDir "lexi.log"
        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c `"cd /d $lexiDir && `"$lexiPython`" -m lexi.server --stt --host $($cfg.LEXI_HOST) --port $($cfg.LEXI_PORT) >> `"$lexiLog`" 2>&1`"" `
            -WindowStyle Hidden -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 10
        if (Test-Port $cfg.LEXI_PORT) {
            Write-Log "Lexi restarted"
        } else {
            Write-Log "WARNING: Lexi still not listening after restart attempt (see logs\lexi.log)"
        }
    }

    # Check PlayIt tunnel (redundancy only)
    $playitProc = Get-Process -Name "playit" -ErrorAction SilentlyContinue
    if (-not $playitProc) {
        Write-Log "ALERT: PlayIt not running - restarting"
        $playit = "C:\Program Files\playit_gg\bin\playit.exe"
        if (Test-Path $playit) {
            # "start" runs headless; the bare exe launches an interactive TUI that
            # fills the redirected log with ANSI escape codes (see restart-all.ps1).
            $playitLog = Join-Path $logsDir "playit.log"
            Start-Process -FilePath $playit -ArgumentList "start" `
                -RedirectStandardOutput $playitLog `
                -RedirectStandardError (Join-Path $logsDir "playit-err.log") `
                -WindowStyle Hidden -ErrorAction SilentlyContinue
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
