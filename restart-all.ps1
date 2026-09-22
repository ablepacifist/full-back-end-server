# Restart all Lexicon services on Windows
# Usage: .\restart-all.ps1
#        .\restart-all.ps1 -DryRun   (resolve and print the registry config, start nothing)

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Refresh PATH (picks up Java/Node if recently installed)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Set JAVA_HOME
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

# Get base directory
$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# ----- Destination registry (the ONE place ports/hosts/IPs come from) -------
# See scripts/env.ps1 and .env.example. Every module (Java, Lexi, the web
# clients, Android) reads the same $BASE_DIR\.env; this loads it for the
# orchestration script itself. MASTER_ENV_FILE is exported so every child
# process this script starts finds the same file regardless of its own
# working directory, per each module's own layered-config loader.
. (Join-Path $BASE_DIR "scripts\env.ps1")
$cfg = Get-RegistryConfig -BaseDir $BASE_DIR
$env:MASTER_ENV_FILE = Join-Path $BASE_DIR ".env"

if ($DryRun) {
    Write-Host "`n=== Resolved destination registry (dry run - nothing started) ===" -ForegroundColor Cyan
    foreach ($key in $cfg.Keys) {
        $val = $cfg[$key]
        if ($key -match 'TOKEN|SECRET|PASSWORD|VAPID_PRIVATE') { $val = "<masked>" }
        Write-Host ("  {0,-24} = {1}" -f $key, $val)
    }
    Write-Host ""
    Test-CloudflaredIngress -Cfg $cfg
    Write-Host "`n(dry run: no services were stopped or started)" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n=== Restarting Full Back-End Server ===" -ForegroundColor Cyan

# ----- Stop all services -----
Write-Host "`nStopping all services..." -ForegroundColor Red

# Kill Java processes (alchemy, lexicon, pokemon, hsqldb)
Get-Process -Name "java" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Stopping java PID $($_.Id)..." -ForegroundColor Yellow
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

# Kill node/serve/python processes on our ports (8765 is Lexi's voice daemon, a python process)
$ports = @(
    [int]$cfg.FRONTEND_PORT, [int]$cfg.ALCHEMY_PORT, [int]$cfg.POKEMON_PORT,
    [int]$cfg.LEXICON_PORT, [int]$cfg.DB_PORT, [int]$cfg.LEXI_PORT
)
foreach ($port in $ports) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        foreach ($c in $conn) {
            Write-Host "  Stopping PID $($c.OwningProcess) on port $port..." -ForegroundColor Yellow
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-Sleep -Seconds 3

# Create logs directory
$logsDir = Join-Path $BASE_DIR "logs"
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null

# ----- Start WSL and keep it alive (Java needs it for UNC path resolution) -----
Write-Host "`nEnsuring WSL Ubuntu is running..." -ForegroundColor Cyan
# Shutdown first to clear stale state, then start fresh
wsl --shutdown 2>$null
Start-Sleep -Seconds 2
Start-Process wsl -ArgumentList "-d","Ubuntu","--","sleep","infinity" -WindowStyle Hidden
Start-Sleep -Seconds 3
$wslCheck = wsl -d Ubuntu -e bash -c "echo OK" 2>&1
if ($wslCheck -match "OK") {
    Write-Host "  WSL Ubuntu active" -ForegroundColor Green
} else {
    Write-Host "  WARNING: WSL Ubuntu may not be running!" -ForegroundColor Red
}

# ----- Mount all ext4 media HDDs via WSL (auto-detects any drive, any partition) -----
Write-Host "`nScanning for ext4 media drives to mount into WSL..." -ForegroundColor Cyan

$linuxDataGuid = "{0fc63daf-8483-4772-8e79-3d69d8477de4}"  # GPT "Linux filesystem data" type
$candidateDisks = Get-Disk | Where-Object { -not $_.IsSystem }  # excludes the Windows OS disk

foreach ($disk in $candidateDisks) {
    $linuxPartitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
        Where-Object { $_.GptType -eq $linuxDataGuid }

    if (-not $linuxPartitions) {
        Write-Host "  Disk $($disk.Number) ($($disk.FriendlyName)): no ext4/Linux partition found, skipping" -ForegroundColor Gray
        continue
    }

    foreach ($part in $linuxPartitions) {
        $mountPath = "\\wsl.localhost\Ubuntu\mnt\wsl\PHYSICALDRIVE$($disk.Number)p$($part.PartitionNumber)"
        if (Test-Path $mountPath) {
            Write-Host "  Disk $($disk.Number) partition $($part.PartitionNumber) already mounted" -ForegroundColor Green
            continue
        }
        Write-Host "  Mounting Disk $($disk.Number) partition $($part.PartitionNumber) (ext4)..." -ForegroundColor Cyan
        Start-Process -FilePath "wsl" -ArgumentList "--mount", "\\.\PHYSICALDRIVE$($disk.Number)", "--partition", "$($part.PartitionNumber)", "--type", "ext4" -Verb RunAs -Wait -PassThru
        Start-Sleep -Seconds 3
        if (Test-Path $mountPath) {
            Write-Host "  Mounted successfully at $mountPath" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: mount FAILED for Disk $($disk.Number) partition $($part.PartitionNumber)" -ForegroundColor Red
        }
    }
}

# ----- Start HSQLDB -----
Write-Host "`nStarting HSQLDB..." -ForegroundColor Cyan
$hsqldbLog = Join-Path $logsDir "database.log"
Start-Process -FilePath "java" `
    -ArgumentList "-cp", "lib\hsqldb.jar", "org.hsqldb.server.Server", "--database.0", "file:alchemydb", "--dbname.0", "mydb", "--port", "$($cfg.DB_PORT)" `
    -WorkingDirectory (Join-Path $BASE_DIR "alchemyServer") `
    -RedirectStandardOutput $hsqldbLog `
    -RedirectStandardError (Join-Path $logsDir "database-err.log") `
    -WindowStyle Hidden

Write-Host "  Waiting for database..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Verify HSQLDB is running
$dbCheck = Get-NetTCPConnection -LocalPort $cfg.DB_PORT -State Listen -ErrorAction SilentlyContinue
if ($dbCheck) {
    Write-Host "  HSQLDB started on port $($cfg.DB_PORT)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: HSQLDB may not have started!" -ForegroundColor Red
}

# ----- Start AlchemyServer -----
# Reads $BASE_DIR\.env itself now (spring.config.import: module .env < ../.env
# < $env:MASTER_ENV_FILE, see alchemyServer/src/main/resources/application.properties)
# — nothing needs to be injected here beyond JAVA_HOME and the inherited
# MASTER_ENV_FILE set above.
Write-Host "`nStarting AlchemyServer..." -ForegroundColor Cyan
$alchemyLog = Join-Path $logsDir "alchemy.log"
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"set JAVA_HOME=$env:JAVA_HOME&& cd /d $BASE_DIR\alchemyServer && gradlew.bat bootRun > `"$alchemyLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for AlchemyServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort $cfg.ALCHEMY_PORT -State Listen -ErrorAction SilentlyContinue) { break } }

$alchemyCheck = Get-NetTCPConnection -LocalPort $cfg.ALCHEMY_PORT -State Listen -ErrorAction SilentlyContinue
if ($alchemyCheck) {
    Write-Host "  AlchemyServer started on port $($cfg.ALCHEMY_PORT)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: AlchemyServer may still be starting (check logs\alchemy.log)" -ForegroundColor Yellow
}

# ----- Start LexiconServer -----
# Same story as Alchemy: reads $BASE_DIR\.env itself via spring.config.import.
Write-Host "`nStarting LexiconServer..." -ForegroundColor Cyan
$lexiconLog = Join-Path $logsDir "lexicon.log"

Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"set JAVA_HOME=$env:JAVA_HOME&& cd /d $BASE_DIR\lexiconServer && gradlew.bat bootRun > `"$lexiconLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for LexiconServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort $cfg.LEXICON_PORT -State Listen -ErrorAction SilentlyContinue) { break } }

$lexiconCheck = Get-NetTCPConnection -LocalPort $cfg.LEXICON_PORT -State Listen -ErrorAction SilentlyContinue
if ($lexiconCheck) {
    Write-Host "  LexiconServer started on port $($cfg.LEXICON_PORT)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: LexiconServer may still be starting (check logs\lexicon.log)" -ForegroundColor Yellow
}

# ----- Start Lexi (voice daemon) -----
# Turns a recorded clip into a spoken answer: speech-to-text here on aragon, the text to
# Obrenna on alison, and the reply spoken with Piper. LexiconServer's /api/voice endpoints
# relay to it, which is what makes the website's voice assistant page work.
#
# Runs in --stt mode so the Pi / alison can reach /stt over the LAN (the browser /turn app
# has no /stt endpoint). Bind host/port come from the registry (LEXI_HOST/LEXI_PORT); every
# call is guarded by the bearer tool token, and the Windows firewall rule for 8765 is already
# in place. Lexi reads the same $BASE_DIR\.env itself (see Lexi/lexi/config.py), so the
# secrets in .tool_token/.agent_token stay local to the Lexi directory and nothing secret
# needs to be passed on this command line.
# Note: the venv python.exe is a launcher that spawns the real interpreter, so two python
# processes (parent + child) for one Lexi is normal, not a double launch.
Write-Host "`nStarting Lexi (voice daemon)..." -ForegroundColor Cyan
$lexiDir = Join-Path $BASE_DIR "Lexi"
$lexiPython = Join-Path $lexiDir ".venv\Scripts\python.exe"
$lexiLog = Join-Path $logsDir "lexi.log"

if (Test-Path $lexiPython) {
    Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c `"cd /d $lexiDir && `"$lexiPython`" -m lexi.server --stt --host $($cfg.LEXI_HOST) --port $($cfg.LEXI_PORT) > `"$lexiLog`" 2>&1`"" `
        -WindowStyle Hidden

    Write-Host "  Waiting for Lexi to start..." -ForegroundColor Gray
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; if (Get-NetTCPConnection -LocalPort $cfg.LEXI_PORT -State Listen -ErrorAction SilentlyContinue) { break } }

    if (Get-NetTCPConnection -LocalPort $cfg.LEXI_PORT -State Listen -ErrorAction SilentlyContinue) {
        # The speech models load on the first request, not now, so the first voice turn
        # after a restart is slower than the ones after it.
        Write-Host "  Lexi started on port $($cfg.LEXI_PORT) (--stt, $($cfg.LEXI_HOST))" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Lexi did not start (check logs\lexi.log)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Lexi: no virtualenv at Lexi\.venv, skipping" -ForegroundColor Yellow
    Write-Host "    Create it with: cd Lexi; python -m venv .venv; .venv\Scripts\pip install -e `".[engines]`"" -ForegroundColor DarkGray
}

# ----- Start PokemonServer -----
Write-Host "`nStarting PokemonServer..." -ForegroundColor Cyan
$pokemonLog  = Join-Path $logsDir "pokemon.log"
$pokemonJar  = Join-Path $BASE_DIR "pokemon\pokemon\pokemonServer\build\libs\pokemonServer-1.0.0.jar"
$pokemonSrc  = Join-Path $BASE_DIR "pokemon\pokemon\pokemonServer\src"
$pokemonBuild = Join-Path $BASE_DIR "pokemon\pokemon\pokemonServer"

$rebuildNeeded = $false
if (-not (Test-Path $pokemonJar)) {
    $rebuildNeeded = $true
    Write-Host "  No JAR found - building..." -ForegroundColor Yellow
} else {
    $jarTime = (Get-Item $pokemonJar).LastWriteTime
    $newerFile = Get-ChildItem -Path $pokemonSrc -Recurse -Include "*.java","*.properties" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $jarTime } | Select-Object -First 1
    if ($newerFile) {
        $rebuildNeeded = $true
        Write-Host "  Source changes detected ($($newerFile.Name)) - rebuilding JAR..." -ForegroundColor Yellow
        Remove-Item $pokemonJar -Force -ErrorAction SilentlyContinue
    }
}

if ($rebuildNeeded) {
    Push-Location $pokemonBuild
    & ".\gradlew.bat" clean build 2>&1 | Out-Null
    Pop-Location
    if (Test-Path $pokemonJar) {
        Write-Host "  JAR built successfully" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: JAR build may have failed - check source for errors" -ForegroundColor Red
    }
}

# Reads $BASE_DIR\.env itself now (spring.config.import, same as the other two
# Spring servers) — run from its own directory so its "../../../.env" layer
# resolves, with $env:MASTER_ENV_FILE (set above) as the reliable fallback
# regardless of working directory.
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"cd /d $pokemonBuild && java -jar `"$pokemonJar`" > `"$pokemonLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for PokemonServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort $cfg.POKEMON_PORT -State Listen -ErrorAction SilentlyContinue) { break } }

$pokemonCheck = Get-NetTCPConnection -LocalPort $cfg.POKEMON_PORT -State Listen -ErrorAction SilentlyContinue
if ($pokemonCheck) {
    Write-Host "  PokemonServer started on port $($cfg.POKEMON_PORT)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: PokemonServer may still be starting (check logs\pokemon.log)" -ForegroundColor Yellow
}

# ----- Start Frontend -----
Write-Host "`nStarting Frontend..." -ForegroundColor Cyan
$frontendDir = Join-Path $BASE_DIR "Lexicon"
$frontendBuildDir = Join-Path $frontendDir "build"
$frontendLog = Join-Path $logsDir "frontend.log"

# Build if there's no build folder, OR if .env changed more recently than the
# last build (destinations.json is baked in at build time by
# scripts/sync-destinations.js, wired as a prebuild step — a stale build
# would otherwise keep serving old ports/hostnames after a registry change).
$rootEnvFile = Join-Path $BASE_DIR ".env"
$needsFrontendBuild = -not (Test-Path $frontendBuildDir)
if (-not $needsFrontendBuild -and (Test-Path $rootEnvFile)) {
    $envMtime = (Get-Item $rootEnvFile).LastWriteTime
    $buildMtime = (Get-Item $frontendBuildDir).LastWriteTime
    if ($envMtime -gt $buildMtime) {
        Write-Host "  .env changed since the last build - rebuilding so the new destinations take effect" -ForegroundColor Yellow
        $needsFrontendBuild = $true
    }
}
if ($needsFrontendBuild) {
    Write-Host "  Building React app..." -ForegroundColor Yellow
    Push-Location $frontendDir
    npm run build 2>&1 | Out-Null
    Pop-Location
}

Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"cd /d $frontendDir && npx serve -s build -l tcp://0.0.0.0:$($cfg.FRONTEND_PORT) > `"$frontendLog`" 2>&1`"" `
    -WindowStyle Hidden

Start-Sleep -Seconds 5

$frontendCheck = Get-NetTCPConnection -LocalPort $cfg.FRONTEND_PORT -State Listen -ErrorAction SilentlyContinue
if ($frontendCheck) {
    Write-Host "  Frontend started on port $($cfg.FRONTEND_PORT)" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Frontend may still be starting (check logs\frontend.log)" -ForegroundColor Yellow
}

# ----- Cloudflare Tunnel (Windows Service — auto-start, auto-restart on failure) -----
$cfService = Get-Service -Name "Cloudflared" -ErrorAction SilentlyContinue
if ($cfService) {
    Write-Host "`nRestarting Cloudflare Tunnel service..." -ForegroundColor Cyan

    # The service runs as LocalSystem and reads config from the system profile.
    # Sync our user-profile config into that location every restart so changes stick.
    $userCfConfig = "C:\Users\HP\.cloudflared\config.yml"
    $sysCfConfig  = "C:\Windows\System32\config\systemprofile\.cloudflared\config.yml"
    if (Test-Path $userCfConfig) {
        Start-Process powershell -ArgumentList "-Command",("Copy-Item '$userCfConfig' '$sysCfConfig' -Force") -Verb RunAs -Wait -ErrorAction SilentlyContinue
        Write-Host "  Synced cloudflared config to LocalSystem profile" -ForegroundColor Gray
    }

    # cloudflared's ingress can't itself read .env (Cloudflare's own format),
    # so this is the one place that can drift silently from the registry.
    Test-CloudflaredIngress -Cfg $cfg

    if ($cfService.Status -ne 'Stopped') {
        Start-Process sc.exe -ArgumentList "stop","Cloudflared" -Verb RunAs -Wait -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    Start-Process sc.exe -ArgumentList "start","Cloudflared" -Verb RunAs -Wait -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    $cfService = Get-Service -Name "Cloudflared"
    if ($cfService.Status -eq 'Running') {
        Write-Host "  Cloudflare Tunnel service running" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Cloudflare Tunnel service status: $($cfService.Status)" -ForegroundColor Red
    }
} else {
    Write-Host "`nCloudflare Tunnel: service not installed, skipping" -ForegroundColor Yellow
}

# ----- Start PlayIt Tunnel (redundancy only) -----
$playit = "C:\Program Files\playit_gg\bin\playit.exe"
if (Test-Path $playit) {
    # Kill existing playit (both the service-launched and any manually started copy)
    Get-Process -Name "playit" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    Write-Host "`nStarting PlayIt Tunnel..." -ForegroundColor Cyan
    $playitLog = Join-Path $logsDir "playit.log"
    # "start" runs the agent headless; the bare exe (no subcommand) launches
    # playit's interactive TUI dashboard, which - when stdout is redirected to
    # a file instead of a real terminal - fills the log with raw ANSI escape
    # codes indefinitely (this grew logs\playit.log to 50+MB). The stored
    # secret (see: playit.exe secret-path) is reused automatically; nothing
    # secret is passed on this command line.
    Start-Process -FilePath $playit `
        -ArgumentList "start" `
        -RedirectStandardOutput $playitLog `
        -RedirectStandardError (Join-Path $logsDir "playit-err.log") `
        -WindowStyle Hidden
    Start-Sleep -Seconds 3
    Write-Host "  PlayIt Tunnel started" -ForegroundColor Green
} else {
    Write-Host "`nPlayIt: not found, skipping" -ForegroundColor Yellow
}

# ----- Summary -----
Write-Host "`n=== All services started! ===" -ForegroundColor Green

# ----- Start Watchdog -----
# Kill any existing watchdog process first
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -eq 'powershell' -and $_.Id -ne $PID
} | ForEach-Object {
    try {
        $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmdLine -and $cmdLine -match 'watchdog\.ps1') {
            Write-Host "  Stopping old watchdog PID $($_.Id)..." -ForegroundColor Yellow
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

$watchdogScript = Join-Path $BASE_DIR "watchdog.ps1"
if (Test-Path $watchdogScript) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogScript`"" -WindowStyle Hidden
    Write-Host "`nWatchdog started (checks every 30s, auto-restarts on failure)" -ForegroundColor Green
}

Write-Host "`nLocal URLs:" -ForegroundColor Cyan
Write-Host "  Frontend:       http://localhost:$($cfg.FRONTEND_PORT)"
Write-Host "  AlchemyServer:  http://localhost:$($cfg.ALCHEMY_PORT)"
Write-Host "  LexiconServer:  http://localhost:$($cfg.LEXICON_PORT)"
Write-Host "  PokemonServer:  http://localhost:$($cfg.POKEMON_PORT)"
Write-Host "  Database:       localhost:$($cfg.DB_PORT)"
Write-Host "  Lexi (STT):     http://localhost:$($cfg.LEXI_PORT)  (bound to $($cfg.LEXI_HOST), token-guarded /stt for the Pi / alison)"

Write-Host "`nExternal URLs (Cloudflare Tunnel - primary, works from any location):" -ForegroundColor Cyan
Write-Host "  Frontend:       $($cfg.PUBLIC_FRONTEND_URL)"
Write-Host "  LexiconServer:  $($cfg.PUBLIC_LEXICON_URL)"
Write-Host "  AlchemyServer:  $($cfg.PUBLIC_ALCHEMY_URL)"
Write-Host "  PokemonServer:  $($cfg.PUBLIC_POKEMON_URL)"

Write-Host "`nPlayIt fallback (secondary, kept for redundancy - IPs are tunnel-session-assigned and may be stale; confirm on the playit.gg dashboard):" -ForegroundColor DarkGray
Write-Host "  PlayIt Frontend: http://$($cfg.PLAYIT_HOST):$($cfg.PLAYIT_FRONTEND_PORT)" -ForegroundColor DarkGray
Write-Host "  PlayIt Alchemy:  http://$($cfg.PLAYIT_HOST):$($cfg.PLAYIT_ALCHEMY_PORT)" -ForegroundColor DarkGray
Write-Host "  PlayIt Lexicon:  http://$($cfg.PLAYIT_HOST):$($cfg.PLAYIT_LEXICON_PORT)" -ForegroundColor DarkGray
Write-Host "  PlayIt Pokemon:  http://$($cfg.PLAYIT_HOST):$($cfg.PLAYIT_POKEMON_PORT)" -ForegroundColor DarkGray

Write-Host "`nLogs:" -ForegroundColor Cyan
Write-Host "  Get-Content -Wait logs\database.log"
Write-Host "  Get-Content -Wait logs\alchemy.log"
Write-Host "  Get-Content -Wait logs\lexicon.log"
Write-Host "  Get-Content -Wait logs\lexi.log"
Write-Host "  Get-Content -Wait logs\pokemon.log"
Write-Host "  Get-Content -Wait logs\frontend.log"
Write-Host "  Get-Content -Wait logs\playit.log"
Write-Host ""
