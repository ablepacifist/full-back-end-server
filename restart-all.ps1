# Restart all Lexicon services on Windows
# Usage: .\restart-all.ps1

$ErrorActionPreference = "Continue"

# Refresh PATH (picks up Java/Node if recently installed)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Set JAVA_HOME
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot"
$env:Path = "$env:JAVA_HOME\bin;$env:Path"

# Get base directory
$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n=== Restarting Full Back-End Server ===" -ForegroundColor Cyan

# ----- Stop all services -----
Write-Host "`nStopping all services..." -ForegroundColor Red

# Kill Java processes (alchemy, lexicon, hsqldb)
Get-Process -Name "java" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  Stopping java PID $($_.Id)..." -ForegroundColor Yellow
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

# Kill node/serve processes on our ports
$ports = @(3001, 8080, 8090, 36568, 9002)
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
    -ArgumentList "-cp", "lib\hsqldb.jar", "org.hsqldb.server.Server", "--database.0", "file:alchemydb", "--dbname.0", "mydb", "--port", "9002" `
    -WorkingDirectory (Join-Path $BASE_DIR "alchemyServer") `
    -RedirectStandardOutput $hsqldbLog `
    -RedirectStandardError (Join-Path $logsDir "database-err.log") `
    -WindowStyle Hidden

Write-Host "  Waiting for database..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Verify HSQLDB is running
$dbCheck = Get-NetTCPConnection -LocalPort 9002 -State Listen -ErrorAction SilentlyContinue
if ($dbCheck) {
    Write-Host "  HSQLDB started on port 9002" -ForegroundColor Green
} else {
    Write-Host "  WARNING: HSQLDB may not have started!" -ForegroundColor Red
}

# ----- Start AlchemyServer -----
Write-Host "`nStarting AlchemyServer..." -ForegroundColor Cyan
$alchemyLog = Join-Path $logsDir "alchemy.log"
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"set JAVA_HOME=$env:JAVA_HOME&& cd /d $BASE_DIR\alchemyServer && gradlew.bat bootRun > `"$alchemyLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for AlchemyServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue) { break } }

$alchemyCheck = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($alchemyCheck) {
    Write-Host "  AlchemyServer started on port 8080" -ForegroundColor Green
} else {
    Write-Host "  WARNING: AlchemyServer may still be starting (check logs\alchemy.log)" -ForegroundColor Yellow
}

# ----- Start LexiconServer -----
Write-Host "`nStarting LexiconServer..." -ForegroundColor Cyan
$lexiconLog = Join-Path $logsDir "lexicon.log"

# Load .env file for VAPID keys and other secrets
$envFile = Join-Path $BASE_DIR ".env"
$envVars = ""
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $envVars += "set $($_)&& "
    }
}

Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"set JAVA_HOME=$env:JAVA_HOME&& ${envVars}cd /d $BASE_DIR\lexiconServer && gradlew.bat bootRun > `"$lexiconLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for LexiconServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort 36568 -State Listen -ErrorAction SilentlyContinue) { break } }

$lexiconCheck = Get-NetTCPConnection -LocalPort 36568 -State Listen -ErrorAction SilentlyContinue
if ($lexiconCheck) {
    Write-Host "  LexiconServer started on port 36568" -ForegroundColor Green
} else {
    Write-Host "  WARNING: LexiconServer may still be starting (check logs\lexicon.log)" -ForegroundColor Yellow
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
$pokemonEnvVars = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) { $pokemonEnvVars[$parts[0].Trim()] = $parts[1].Trim() }
    }
}
$pokemonEnvStr = ($pokemonEnvVars.GetEnumerator() | ForEach-Object { "set $($_.Key)=$($_.Value)&&" }) -join ' '
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"${pokemonEnvStr}java -jar `"$pokemonJar`" > `"$pokemonLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for PokemonServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue) { break } }

$pokemonCheck = Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue
if ($pokemonCheck) {
    Write-Host "  PokemonServer started on port 8090" -ForegroundColor Green
} else {
    Write-Host "  WARNING: PokemonServer may still be starting (check logs\pokemon.log)" -ForegroundColor Yellow
}

# ----- Start Frontend -----
Write-Host "`nStarting Frontend..." -ForegroundColor Cyan
$frontendDir = Join-Path $BASE_DIR "Lexicon"
$frontendLog = Join-Path $logsDir "frontend.log"

# Build if no build folder
if (-not (Test-Path (Join-Path $frontendDir "build"))) {
    Write-Host "  Building React app first..." -ForegroundColor Yellow
    Push-Location $frontendDir
    npm run build 2>&1 | Out-Null
    Pop-Location
}

Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"cd /d $frontendDir && npx serve -s build -l tcp://0.0.0.0:3001 > `"$frontendLog`" 2>&1`"" `
    -WindowStyle Hidden

Start-Sleep -Seconds 5

$frontendCheck = Get-NetTCPConnection -LocalPort 3001 -State Listen -ErrorAction SilentlyContinue
if ($frontendCheck) {
    Write-Host "  Frontend started on port 3001" -ForegroundColor Green
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

# ----- Start PlayIt Tunnel -----
$playit = "C:\Program Files\playit_gg\bin\playit.exe"
if (Test-Path $playit) {
    # Kill existing playit
    Get-Process -Name "playit" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "`nStarting PlayIt Tunnel..." -ForegroundColor Cyan
    $playitLog = Join-Path $logsDir "playit.log"
    Start-Process -FilePath $playit `
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
Write-Host "  Frontend:       http://localhost:3001"
Write-Host "  AlchemyServer:  http://localhost:8080"
Write-Host "  LexiconServer:  http://localhost:36568"
Write-Host "  PokemonServer:  http://localhost:8090"
Write-Host "  Database:       localhost:9002"

Write-Host "`nExternal URLs (Cloudflare Tunnel - primary, works from any location):" -ForegroundColor Cyan
Write-Host "  Frontend:       https://alex-dyakin.com"
Write-Host "  LexiconServer:  https://api.alex-dyakin.com"
Write-Host "  AlchemyServer:  https://alchemy.alex-dyakin.com"
Write-Host "  PokemonServer:  https://poke.alex-dyakin.com"

Write-Host "`nPlayIt fallback (secondary - IPs are tunnel-session-assigned and may be stale, especially after a move):" -ForegroundColor DarkGray
Write-Host "  PlayIt Frontend: http://209.25.140.16:1796" -ForegroundColor DarkGray
Write-Host "  PlayIt Alchemy:  http://209.25.140.16:1760" -ForegroundColor DarkGray
Write-Host "  PlayIt Lexicon:  http://209.25.140.16:1792" -ForegroundColor DarkGray

Write-Host "`nLogs:" -ForegroundColor Cyan
Write-Host "  Get-Content -Wait logs\database.log"
Write-Host "  Get-Content -Wait logs\alchemy.log"
Write-Host "  Get-Content -Wait logs\lexicon.log"
Write-Host "  Get-Content -Wait logs\frontend.log"
Write-Host "  Get-Content -Wait logs\cloudflared.log"
Write-Host ""
