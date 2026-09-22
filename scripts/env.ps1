# Shared destination-registry loader for the orchestration scripts
# (restart-all.ps1, watchdog.ps1). Dot-source this file:
#   . (Join-Path $BASE_DIR "scripts\env.ps1")
#   $cfg = Get-RegistryConfig -BaseDir $BASE_DIR
#
# Reads $BASE_DIR\.env (KEY=value, one per line, '#' comments, no quoting)
# and returns a hashtable with every key found, plus safe fallback defaults
# (mirroring .env.example) for any key the file doesn't define, so a script
# still runs when .env is missing. This is the ONE place these scripts parse
# .env — every port/host literal in restart-all.ps1 and watchdog.ps1 should
# come from the returned hashtable, not be repeated as a literal.

function Get-RegistryConfig {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir
    )

    # Fallback defaults — used only for a key that is absent from .env, so
    # the script degrades gracefully rather than failing outright.
    $cfg = [ordered]@{
        LAN_HOST                      = "192.168.1.4"
        ALISON_LAN_IP                 = "192.168.1.2"
        PI_LAN_IP                     = "192.168.1.8"
        BILBO_LAN_IP                  = "192.168.1.11"
        FRONTEND_PORT                 = "3001"
        LEXICON_PORT                  = "36568"
        ALCHEMY_PORT                  = "8080"
        POKEMON_PORT                  = "8090"
        SERVER_ADDRESS                = "0.0.0.0"
        DATABASE_URL                  = "jdbc:hsqldb:hsql://localhost:9002/mydb"
        LEXI_HOST                     = "0.0.0.0"
        LEXI_PORT                     = "8765"
        BRAIN_LAN_PORT                = "9080"
        PUBLIC_FRONTEND_URL           = "https://alex-dyakin.com"
        PUBLIC_LEXICON_URL            = "https://api.alex-dyakin.com"
        PUBLIC_ALCHEMY_URL            = "https://alchemy.alex-dyakin.com"
        PUBLIC_POKEMON_URL            = "https://poke.alex-dyakin.com"
        PUBLIC_BRIDGE_URL             = "https://voice.alex-dyakin.com"
        PUBLIC_BRAIN_URL              = "https://llm.alex-dyakin.com"
        PLAYIT_HOST                   = "209.25.140.16"
        PLAYIT_FRONTEND_PORT          = "1796"
        PLAYIT_ALCHEMY_PORT           = "1760"
        PLAYIT_LEXICON_PORT           = "1792"
        PLAYIT_POKEMON_PORT           = "1790"
    }

    $envFile = Join-Path $BaseDir ".env"
    if (Test-Path $envFile) {
        Get-Content $envFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -eq "" -or $line.StartsWith("#")) { return }
            $idx = $line.IndexOf("=")
            if ($idx -lt 1) { return }
            $key = $line.Substring(0, $idx).Trim()
            $val = $line.Substring($idx + 1).Trim()
            if ($key) { $cfg[$key] = $val }
        }
    }

    # Derived value: HSQLDB port, parsed out of DATABASE_URL
    # (jdbc:hsqldb:hsql://host:port/name) rather than kept as a separate key.
    $dbPort = "9002"
    if ($cfg.DATABASE_URL -match ":(\d+)/[^/]+$") { $dbPort = $Matches[1] }
    $cfg["DB_PORT"] = $dbPort

    return $cfg
}

# Warn (does not fail) when the live Cloudflare tunnel ingress ports don't
# match the registry — the ingress file can't itself read from .env (a
# Cloudflare limitation, not this repo's), so this is the drift check.
function Test-CloudflaredIngress {
    param([hashtable]$Cfg)

    $cfConfig = "C:\Users\HP\.cloudflared\config.yml"
    if (-not (Test-Path $cfConfig)) { return }

    $expected = @{
        ("http://127.0.0.1:" + $Cfg.FRONTEND_PORT) = "frontend"
        ("http://127.0.0.1:" + $Cfg.LEXICON_PORT)  = "lexicon"
        ("http://127.0.0.1:" + $Cfg.ALCHEMY_PORT)  = "alchemy"
        ("http://127.0.0.1:" + $Cfg.POKEMON_PORT)  = "pokemon"
    }
    $ingressServices = Get-Content $cfConfig | Where-Object { $_ -match '^\s*service:\s*(\S+)' } | ForEach-Object {
        if ($_ -match '^\s*service:\s*(\S+)') { $Matches[1] }
    }
    foreach ($url in $expected.Keys) {
        if ($ingressServices -notcontains $url) {
            Write-Host "  WARNING: cloudflared config.yml has no ingress entry for $url ($($expected[$url])) - .env and the tunnel have drifted" -ForegroundColor Red
        }
    }
}
