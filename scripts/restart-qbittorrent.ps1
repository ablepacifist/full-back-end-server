# Restarts qBittorrent on aragorn with the config Lexicon's torrent downloads need.
#
# Must be run at the desktop (RustDesk/TeamViewer), in the interactive session, because the
# \\wsl.localhost\... media path is only reliably visible there, and because qBittorrent is a
# GUI app. Proton VPN has to be connected first: qBittorrent is bound to the tunnel address,
# so without it the listen socket never opens.
#
# Why a script: qBittorrent rewrites qBittorrent.ini from memory when it exits, so settings
# have to be applied while it is closed, between the stop and the start. Doing that by hand
# is how the save path ended up corrupted once already.
#
#   powershell -ExecutionPolicy Bypass -File scripts\restart-qbittorrent.ps1
#
# Docs: computer-documentation/programs/lexicon-torrents.md

$ErrorActionPreference = 'Stop'

$ini      = Join-Path $env:APPDATA 'qBittorrent\qBittorrent.ini'
$exe      = 'C:\Program Files\qBittorrent\qbittorrent.exe'
$logFile  = Join-Path $env:LOCALAPPDATA 'qBittorrent\logs\qbittorrent.log'
$webUiUrl = 'http://127.0.0.1:8083/api/v2/app/webapiVersion'
$storage  = '//wsl.localhost/Ubuntu/mnt/wsl/PHYSICALDRIVE1p2/lexicon-storage'

function Write-Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Write-Good($text) { Write-Host "   OK   $text" -ForegroundColor Green }
function Write-Bad($text)  { Write-Host "   BAD  $text" -ForegroundColor Red }

# ── 1. Proton VPN must be up, or the bind cannot succeed ────────────────────────────────
Write-Step 'Proton VPN'
$tunnel = $null
$protonIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -eq 'ProtonVPN' } | Select-Object -First 1
if ($protonIp) { $tunnel = [string]$protonIp.IPAddress }
if (-not $tunnel) {
    Write-Bad 'the ProtonVPN adapter has no IPv4 address.'
    Write-Host '        Connect Proton VPN first (split tunnelling: Include only -> qbittorrent.exe),'
    Write-Host '        then run this again. Starting qBittorrent now would just stall its torrents.'
    exit 1
}
Write-Good "tunnel address $tunnel"

# ── 2. Close qBittorrent, letting it save its own state ────────────────────────────────
Write-Step 'Closing qBittorrent'
$running = Get-Process qbittorrent -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Good 'was not running'
} else {
    foreach ($proc in $running) { $null = $proc.CloseMainWindow() }
    for ($i = 0; $i -lt 30 -and (Get-Process qbittorrent -ErrorAction SilentlyContinue); $i++) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process qbittorrent -ErrorAction SilentlyContinue) {
        # Closing to the tray rather than exiting is a qBittorrent option, so this is normal.
        Write-Host '        window close did not exit it; stopping the process'
        Stop-Process -Name qbittorrent -Force
        Start-Sleep -Seconds 2
    }
    if (Get-Process qbittorrent -ErrorAction SilentlyContinue) {
        Write-Bad 'could not close qBittorrent; close it by hand and run this again.'
        exit 1
    }
    Write-Good 'closed'
}

# ── 3. Apply the settings, now that nothing can overwrite them ─────────────────────────
Write-Step 'Settings'

# Section-aware, line-based: keeps every key qBittorrent wrote for itself.
function Set-IniKey {
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)

    $header = "[$Section]"
    $out = New-Object System.Collections.Generic.List[string]
    $inSection = $false
    $done = $false
    $sawSection = $false

    foreach ($line in $Lines) {
        if ($line -match '^\[.+\]\s*$') {
            if ($inSection -and -not $done) {
                $out.Add("$Key=$Value"); $done = $true     # key missing: add at section end
            }
            $inSection = ($line.Trim() -eq $header)
            if ($inSection) { $sawSection = $true }
            $out.Add($line)
            continue
        }
        if ($inSection -and $line -match "^\s*$([regex]::Escape($Key))\s*=") {
            if (-not $done) { $out.Add("$Key=$Value"); $done = $true }
            continue                                       # drop the old value (and duplicates)
        }
        $out.Add($line)
    }
    if ($inSection -and -not $done) { $out.Add("$Key=$Value"); $done = $true }
    if (-not $sawSection) { $out.Add($header); $out.Add("$Key=$Value") }
    return $out.ToArray()
}

function Get-IniKey {
    param([string[]]$Lines, [string]$Section, [string]$Key)

    $header = "[$Section]"
    $inSection = $false
    foreach ($line in $Lines) {
        if ($line -match '^\[.+\]\s*$') { $inSection = ($line.Trim() -eq $header); continue }
        if ($inSection -and $line -match "^\s*$([regex]::Escape($Key))\s*=(.*)$") {
            return $Matches[1]
        }
    }
    return $null
}

if (-not (Test-Path $ini)) {
    Write-Bad "no $ini - launch qBittorrent once first so it writes one."
    exit 1
}

$backup = "$ini.bak"
Copy-Item $ini $backup -Force
$lines = Get-Content $ini

# qBittorrent 5.3 moved every Web UI setting out of [Preferences] (where they were spelled
# "WebUI\Enabled") into a section of their own, [WebUI] ("Enabled"). Keys left in the old
# place are read by nothing and report nothing: the Web UI simply never starts, with no line
# in the log either way. Carry the credentials over to the new section before the old keys
# are dropped - the password hash is not reproducible from here.
$user = Get-IniKey -Lines $lines -Section 'WebUI' -Key 'Username'
if (-not $user) { $user = Get-IniKey -Lines $lines -Section 'Preferences' -Key 'WebUI\Username' }
$pass = Get-IniKey -Lines $lines -Section 'WebUI' -Key 'Password_PBKDF2'
if (-not $pass) { $pass = Get-IniKey -Lines $lines -Section 'Preferences' -Key 'WebUI\Password_PBKDF2' }

if (-not $user -or -not $pass) {
    Write-Bad 'no Web UI username/password found in qBittorrent.ini.'
    Write-Host '        Set them in qBittorrent (Options -> Web UI) to match QBITTORRENT_USERNAME'
    Write-Host '        and QBITTORRENT_PASSWORD in the root .env. Backup: ' -NoNewline
    Write-Host $backup
    exit 1
}

# Leak safety: bind to whatever Proton is actually using right now. The tunnel address is
# usually stable on WireGuard, but a change here is what silently stalls every torrent.
$wanted = [ordered]@{
    'BitTorrent|Session\InterfaceAddress'  = $tunnel
    'BitTorrent|Session\Interface'         = ''
    'BitTorrent|Session\InterfaceName'     = ''
    # Forward slashes on purpose: Qt eats backslash escapes when it rewrites this file.
    'BitTorrent|Session\DefaultSavePath'   = "$storage/torrents/complete"
    'BitTorrent|Session\TempPath'          = "$storage/torrents/incomplete"
    'BitTorrent|Session\TempPathEnabled'   = 'true'
    # The Proton forward replaces UPnP. Session\UPnP is a dead key in 5.3.0; this is the one.
    'Network|PortForwardingEnabled'        = 'false'
    # Loopback-only Web UI: how the Lexicon server drives qBittorrent. Never published.
    'WebUI|Enabled'                        = 'true'
    'WebUI|Address'                        = '127.0.0.1'
    'WebUI|Port'                           = '8083'
    'WebUI|Username'                       = $user
    'WebUI|Password_PBKDF2'                = $pass
    'WebUI|LocalHostAuth'                  = 'true'
    'WebUI|CSRFProtection'                 = 'true'
    'WebUI|ClickjackingProtection'         = 'true'
    'WebUI|HostHeaderValidation'           = 'true'
}

foreach ($entry in $wanted.GetEnumerator()) {
    $section, $key = $entry.Key.Split('|', 2)
    $lines = Set-IniKey -Lines $lines -Section $section -Key $key -Value $entry.Value
}

# Drop the dead keys so the file stops implying settings that do nothing:
# Session\UPnP (gone in 5.3.0) and the whole legacy [Preferences] WebUI\ block.
$lines = $lines | Where-Object { $_ -notmatch '^\s*Session\\UPnP\s*=' }
$cleaned = New-Object System.Collections.Generic.List[string]
$inPrefs = $false
foreach ($line in $lines) {
    if ($line -match '^\[.+\]\s*$') { $inPrefs = ($line.Trim() -eq '[Preferences]') }
    elseif ($inPrefs -and $line -match '^\s*WebUI\\') { continue }
    $cleaned.Add($line)
}
$lines = $cleaned.ToArray()

Set-Content -Path $ini -Value $lines -Encoding ascii
Write-Good "written (backup at $backup)"

# ── 4. Make sure the save directories exist, on the media volume ───────────────────────
Write-Step 'Save directories'
$null = wsl.exe -d Ubuntu -- sh -c "mkdir -p /mnt/wsl/PHYSICALDRIVE1p2/lexicon-storage/torrents/complete /mnt/wsl/PHYSICALDRIVE1p2/lexicon-storage/torrents/incomplete"
if ($LASTEXITCODE -eq 0) { Write-Good 'torrents/complete and torrents/incomplete present' }
else { Write-Bad 'could not create them - is the WSL media mount up?' }

# ── 5. Start it ────────────────────────────────────────────────────────────────────────
Write-Step 'Starting qBittorrent'
if (-not (Test-Path $exe)) { Write-Bad "no $exe"; exit 1 }
$logLinesBefore = 0
if (Test-Path $logFile) { $logLinesBefore = (Get-Content $logFile).Count }
Start-Process -FilePath $exe | Out-Null

# A 403 is a pass: it means the Web UI answered and wants a login, which is exactly what
# the server will do. Treating it as a failure is what hid a working Web UI once already.
$webApi = $null
$webUiUp = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    try {
        $resp = Invoke-WebRequest -Uri $webUiUrl -TimeoutSec 2 -UseBasicParsing
        $webApi = $resp.Content; $webUiUp = $true; break
    } catch {
        if ($_.Exception.Response) { $webUiUp = $true; break }
    }
}

# ── 6. Verify ──────────────────────────────────────────────────────────────────────────
Write-Step 'Verify'
if (Get-Process qbittorrent -ErrorAction SilentlyContinue) { Write-Good 'process is up' }
else { Write-Bad 'it exited again' }

if ($webApi)       { Write-Good "Web UI answering on 8083 (Web API $webApi)" }
elseif ($webUiUp)  { Write-Good 'Web UI listening on 8083 (login required, as expected)' }
else               { Write-Bad 'Web UI not answering on 127.0.0.1:8083 - see the log lines below' }

if (Test-Path $logFile) {
    # Only this run's lines: stale UPnP/bind lines from earlier runs read as false alarms.
    $recent = Get-Content $logFile | Select-Object -Skip $logLinesBefore

    $listen = $recent | Select-String 'Successfully listening on IP' | Select-Object -Last 1
    if ($listen -and $listen -match [regex]::Escape($tunnel)) { Write-Good "bound to $tunnel" }
    elseif ($listen) { Write-Bad "listening, but not on $tunnel : $listen" }
    else { Write-Bad 'no "Successfully listening" line yet' }

    $upnp = $recent | Select-String 'UPnP/NAT-PMP support' | Select-Object -Last 1
    if (-not $upnp)            { Write-Good 'port forwarding off (no UPnP line)' }
    elseif ($upnp -match 'OFF'){ Write-Good 'UPnP off' }
    else                       { Write-Bad "$upnp" }

    $webErr = $recent | Select-String 'WebUI|Web UI'
    if ($webErr) {
        Write-Host "`n   -- Web UI log lines --" -ForegroundColor DarkGray
        $webErr | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    }

    Write-Host "`n   -- last log lines --" -ForegroundColor DarkGray
    $recent | Select-String 'listening|external IP|interface|WebUI|Web UI|UPnP' |
        Select-Object -Last 8 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
}

Write-Host "`nNow reload the Torrent tab on the website, or reopen the Android add-media screen."
Write-Host "The Lexicon server does not need restarting; it re-checks qBittorrent on every poll.`n"
