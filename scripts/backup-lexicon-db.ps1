# Nightly backup of the Lexicon (HSQLDB) database to bilbo's SAS drive.
#
# What it does:
#   1. asks the running database for a consistent snapshot (HSQLDB BACKUP DATABASE, no downtime)
#   2. checks the archive and its checksum locally
#   3. checks that /mnt/lexicon-backup on bilbo really is the SAS drive (never write to bilbo's boot disk)
#   4. copies the archive over SSH, checks the checksum on bilbo, then moves it into place
#   5. deletes all but the newest $Keep archives on bilbo
#
# Database only. Media files are not part of this backup.
#
# Settings come from the root .env (all optional, same loader as restart-all.ps1):
#   BACKUP_REMOTE_USER  default alexpdyak32
#   BACKUP_REMOTE_HOST  default BILBO_LAN_IP
#   BACKUP_REMOTE_DIR   default /mnt/lexicon-backup/db
# DATABASE_URL and DATABASE_PASSWORD are read the same way the servers read them.
#
# Run by hand:  powershell -ExecutionPolicy Bypass -File scripts\backup-lexicon-db.ps1
# Scheduled:    Task Scheduler task "LexiconDbBackup", every night at 03:00
# Log:          logs\backup-lexicon-db.log
# Exit code:    0 ok, 1 failed

param(
    [int]$Keep = 30,
    [string]$MountPoint = "/mnt/lexicon-backup"
)

$ErrorActionPreference = "Stop"
$BASE_DIR = Split-Path -Parent $PSScriptRoot
. (Join-Path $BASE_DIR "scripts\env.ps1")
$cfg = Get-RegistryConfig -BaseDir $BASE_DIR

$logDir = Join-Path $BASE_DIR "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "backup-lexicon-db.log"

function Write-Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $logFile -Encoding UTF8 -Value $line
}

function Get-Setting([string]$key, [string]$default) {
    if ($cfg.Contains($key) -and $cfg[$key]) { return $cfg[$key] }
    return $default
}

$remoteUser = Get-Setting "BACKUP_REMOTE_USER" "alexpdyak32"
$remoteHost = Get-Setting "BACKUP_REMOTE_HOST" $cfg.BILBO_LAN_IP
$remoteDir  = Get-Setting "BACKUP_REMOTE_DIR"  "$MountPoint/db"
$target     = "$remoteUser@$remoteHost"
$sshOpts    = @("-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new")

$stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$name    = "lexicon_db_$stamp.tar.gz"
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "lexicon-backup-$stamp"

try {
    Write-Log "=== Lexicon database backup to $target`:$remoteDir ==="

    # 1. snapshot from the running server
    New-Item -ItemType Directory -Path $staging | Out-Null
    $jar = Join-Path $BASE_DIR "lexiconServer\lib\hsqldb.jar"
    $env:DATABASE_URL = $cfg.DATABASE_URL
    & java -cp $jar (Join-Path $BASE_DIR "scripts\HsqlBackup.java") $staging
    if ($LASTEXITCODE -ne 0) { throw "database snapshot failed (HsqlBackup exit $LASTEXITCODE). Is the database running on port $($cfg.DB_PORT)?" }

    $snap = Get-ChildItem -Path $staging -Filter "*.tar.gz" | Select-Object -First 1
    if (-not $snap) { throw "snapshot finished but no .tar.gz was written to $staging" }
    $archive = Join-Path $staging $name
    Move-Item -Path $snap.FullName -Destination $archive

    # 2. local check: the archive lists and holds the data file
    $listing = & tar -tzf $archive
    if ($LASTEXITCODE -ne 0 -or ($listing -notcontains "alchemydb.script")) { throw "archive failed its check (no alchemydb.script inside)" }
    $sha  = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLower()
    $size = [math]::Round((Get-Item $archive).Length / 1KB)
    Write-Log "snapshot ok: $name, $size KB, sha256 $sha"

    # 3. the mount must be the SAS drive, not a plain folder on bilbo's boot disk
    & ssh @sshOpts $target "mountpoint -q $MountPoint"
    if ($LASTEXITCODE -ne 0) { throw "$MountPoint is not mounted on $remoteHost (or SSH failed). Refusing to write to the boot disk." }
    & ssh @sshOpts $target "mkdir -p $remoteDir"
    if ($LASTEXITCODE -ne 0) { throw "could not create $remoteDir on $remoteHost" }

    # 4. copy as a hidden partial file, check it, then move it into place
    & scp -q @sshOpts $archive "$target`:$remoteDir/.partial-$name"
    if ($LASTEXITCODE -ne 0) { throw "scp to $remoteHost failed" }
    $remoteSha = (& ssh @sshOpts $target "sha256sum $remoteDir/.partial-$name | cut -d' ' -f1").Trim()
    if ($remoteSha -ne $sha) {
        & ssh @sshOpts $target "rm -f $remoteDir/.partial-$name"
        throw "checksum mismatch after copy (local $sha, remote $remoteSha)"
    }
    & ssh @sshOpts $target "mv $remoteDir/.partial-$name $remoteDir/$name"
    if ($LASTEXITCODE -ne 0) { throw "could not move the archive into place on $remoteHost" }
    Write-Log "copied and verified on $remoteHost"

    # 5. retention: keep the newest $Keep
    $drop = $Keep + 1
    & ssh @sshOpts $target "cd $remoteDir && ls -1t lexicon_db_*.tar.gz | tail -n +$drop | xargs -r rm --"
    $count = (& ssh @sshOpts $target "ls -1 $remoteDir/lexicon_db_*.tar.gz | wc -l").Trim()
    Write-Log "retention: $count archive(s) kept (limit $Keep)"
    Write-Log "backup complete"
    exit 0
}
catch {
    Write-Log "BACKUP FAILED: $($_.Exception.Message)"
    exit 1
}
finally {
    Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue }
}
