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
$ports = @(3001, 8080, 36568, 9002)
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

# ----- Mount ext4 HDD via WSL (if not already mounted) -----
$hddPath = "\\wsl.localhost\Ubuntu\mnt\wsl\PHYSICALDRIVE1p2\lexicon-storage"
if (-not (Test-Path $hddPath)) {
    Write-Host "`nMounting ext4 HDD..." -ForegroundColor Cyan
    # Use wsl --mount (handles device letter changes between reboots)
    Start-Process -FilePath "wsl" -ArgumentList "--mount", "\\.\PHYSICALDRIVE1", "--partition", "2", "--type", "ext4" -Verb RunAs -Wait -PassThru
    Start-Sleep -Seconds 3
    if (Test-Path $hddPath) {
        Write-Host "  ext4 HDD mounted successfully" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: ext4 HDD mount FAILED! Storage features will not work." -ForegroundColor Red
    }
} else {
    Write-Host "`next4 HDD already mounted" -ForegroundColor Green
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
Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c `"set JAVA_HOME=$env:JAVA_HOME&& cd /d $BASE_DIR\lexiconServer && gradlew.bat bootRun > `"$lexiconLog`" 2>&1`"" `
    -WindowStyle Hidden

Write-Host "  Waiting for LexiconServer to start..." -ForegroundColor Gray
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 2; if (Get-NetTCPConnection -LocalPort 36568 -State Listen -ErrorAction SilentlyContinue) { break } }

$lexiconCheck = Get-NetTCPConnection -LocalPort 36568 -State Listen -ErrorAction SilentlyContinue
if ($lexiconCheck) {
    Write-Host "  LexiconServer started on port 36568" -ForegroundColor Green
} else {
    Write-Host "  WARNING: LexiconServer may still be starting (check logs\lexicon.log)" -ForegroundColor Yellow
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
Write-Host "  Database:       localhost:9002"

Write-Host "`nExternal URLs:" -ForegroundColor Cyan
Write-Host "  Cloudflare:     https://alex-dyakin.com"
Write-Host "  PlayIt Frontend: http://209.25.140.16:1796"
Write-Host "  PlayIt Alchemy:  http://209.25.140.16:1760"
Write-Host "  PlayIt Lexicon:  http://209.25.140.16:1792"

Write-Host "`nLogs:" -ForegroundColor Cyan
Write-Host "  Get-Content -Wait logs\database.log"
Write-Host "  Get-Content -Wait logs\alchemy.log"
Write-Host "  Get-Content -Wait logs\lexicon.log"
Write-Host "  Get-Content -Wait logs\frontend.log"
Write-Host "  Get-Content -Wait logs\cloudflared.log"
Write-Host ""
