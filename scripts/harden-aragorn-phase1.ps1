<#
.SYNOPSIS
    Phase 1 hardening for aragorn that needs an elevated PowerShell. Safe to re-run.

.DESCRIPTION
    1. SSH: turns off password logins for the OpenSSH server (key logins keep working).
       Aborts if the administrators' authorized_keys file holds no usable key, so you cannot lock yourself out.
       Validates the new config with `sshd -t` and restores the backup on any failure.
    2. RustDesk: points the RustDeskHbbs task's relay (-r) at rd.alex-dyakin.com instead of a fixed
       public IP, so relaying survives an IP change. Only done when the DNS name currently resolves to
       the IP being replaced. Takes effect the next time the task starts.

    Nothing else is touched. Public hostnames, Cloudflare tunnels and the apps are not affected.

    Run from the local console or RDP, NOT over SSH: step 1 restarts sshd, which drops SSH sessions.

.PARAMETER DryRun   Show what would change; write nothing.
.PARAMETER Rollback Restore the backups made by an earlier run.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Rollback,
    [switch]$SkipSsh,
    [switch]$SkipRustDesk
)

$ErrorActionPreference = 'Stop'

$sshdConfig   = 'C:\ProgramData\ssh\sshd_config'
$sshdBackup   = "$sshdConfig.pre-sec-phase1"
$adminKeys    = 'C:\ProgramData\ssh\administrators_authorized_keys'
$backupDir    = Join-Path $env:ProgramData 'security-backups'
$hbbsArgsFile = Join-Path $backupDir 'RustDeskHbbs-args.pre-sec-phase1.txt'
$beginMark    = '# --- security phase 1 (begin) ---'
$endMark      = '# --- security phase 1 (end) ---'

# Global options must come BEFORE the first "Match" block, or they would apply only inside it.
function Add-Phase1Block {
    param([string]$Text)
    if ($Text -match [regex]::Escape($beginMark)) { return $Text }   # already applied
    $block = @(
        $beginMark,
        'PasswordAuthentication no',
        'KbdInteractiveAuthentication no',
        'PubkeyAuthentication yes',
        'MaxAuthTries 3',
        'LoginGraceTime 30',
        $endMark,
        ''
    ) -join "`r`n"
    return $block + $Text
}

function Assert-Elevated {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this from an elevated (Run as administrator) PowerShell.'
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # dot-sourced for testing: define functions only

if (-not $DryRun) {
    Assert-Elevated
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
}

# ----------------------------------------------------------------- rollback
if ($Rollback) {
    if (Test-Path $sshdBackup) {
        Copy-Item $sshdBackup $sshdConfig -Force
        Restart-Service sshd
        Write-Host 'sshd_config restored and sshd restarted.' -ForegroundColor Green
    }
    if (Test-Path $hbbsArgsFile) {
        $orig = (Get-Content $hbbsArgsFile -Raw).Trim()
        $task = Get-ScheduledTask -TaskName 'RustDeskHbbs'
        $act  = $task.Actions[0]
        $new  = New-ScheduledTaskAction -Execute $act.Execute -Argument $orig -WorkingDirectory $act.WorkingDirectory
        Set-ScheduledTask -TaskName 'RustDeskHbbs' -Action $new | Out-Null
        Write-Host "RustDeskHbbs arguments restored to: $orig" -ForegroundColor Green
    }
    return
}

# --------------------------------------------------------------------- SSH
if (-not $SkipSsh) {
    Write-Host '== SSH: disable password logins' -ForegroundColor Cyan

    $keyLines = @(Get-Content $adminKeys -ErrorAction Stop | Where-Object { $_ -match '^(ssh-|ecdsa-|sk-)' })
    if ($keyLines.Count -lt 1) { throw "No usable key in $adminKeys. Refusing to disable password logins." }
    foreach ($line in $keyLines) {
        $tmp = New-TemporaryFile
        Set-Content -Path $tmp -Value $line
        $fp = & ssh-keygen.exe -lf $tmp
        Remove-Item $tmp -Force
        if ($LASTEXITCODE -ne 0) { throw 'An entry in administrators_authorized_keys is not a valid key. Refusing.' }
        Write-Host "   key allowed: $fp"
    }

    $current = Get-Content $sshdConfig -Raw
    $updated = Add-Phase1Block -Text $current
    if ($updated -eq $current) {
        Write-Host '   already applied.' -ForegroundColor Gray
    } elseif ($DryRun) {
        Write-Host '   [dry run] would add to the top of sshd_config:' -ForegroundColor Yellow
        ($updated.Substring(0, $updated.IndexOf($endMark) + $endMark.Length)) -split "`r?`n" | ForEach-Object { Write-Host "     $_" }
    } else {
        if (-not (Test-Path $sshdBackup)) { Copy-Item $sshdConfig $sshdBackup }
        Set-Content -Path $sshdConfig -Value $updated -NoNewline -Encoding ascii
        & "$env:SystemRoot\System32\OpenSSH\sshd.exe" -t
        if ($LASTEXITCODE -ne 0) {
            Copy-Item $sshdBackup $sshdConfig -Force
            throw 'sshd rejected the new config; the original has been restored.'
        }
        Restart-Service sshd
        Start-Sleep -Seconds 2
        if ((Get-Service sshd).Status -ne 'Running') {
            Copy-Item $sshdBackup $sshdConfig -Force
            Start-Service sshd
            throw 'sshd did not come back; the original config was restored and sshd started.'
        }
        $effective = & "$env:SystemRoot\System32\OpenSSH\sshd.exe" -T | Select-String -Pattern '^(passwordauthentication|pubkeyauthentication|maxauthtries) '
        $effective | ForEach-Object { Write-Host "   effective: $_" }
        Write-Host '   done. Test a key login from another machine now; run with -Rollback if it fails.' -ForegroundColor Green
    }
}

# ---------------------------------------------------------------- RustDesk
if (-not $SkipRustDesk) {
    Write-Host '== RustDesk: relay by hostname instead of fixed IP' -ForegroundColor Cyan
    $task = Get-ScheduledTask -TaskName 'RustDeskHbbs'
    $act  = $task.Actions[0]
    $args0 = $act.Arguments
    if ($args0 -match '-r\s+rd\.alex-dyakin\.com:') {
        Write-Host '   already uses the hostname.' -ForegroundColor Gray
    } elseif ($args0 -match '-r\s+(\d{1,3}(?:\.\d{1,3}){3}):(\d+)') {
        $oldIp = $Matches[1]; $port = $Matches[2]
        $resolved = @((Resolve-DnsName 'rd.alex-dyakin.com' -Type A -ErrorAction Stop).IPAddress)
        if ($resolved -notcontains $oldIp) {
            Write-Host "   rd.alex-dyakin.com resolves to $($resolved -join ', '), not $oldIp. Skipping so relaying cannot break." -ForegroundColor Yellow
        } else {
            $newArgs = $args0 -replace '-r\s+\d{1,3}(?:\.\d{1,3}){3}:\d+', "-r rd.alex-dyakin.com:$port"
            if ($DryRun) {
                Write-Host "   [dry run] $args0  ->  $newArgs" -ForegroundColor Yellow
            } else {
                if (-not (Test-Path $hbbsArgsFile)) { Set-Content -Path $hbbsArgsFile -Value $args0 }
                $new = New-ScheduledTaskAction -Execute $act.Execute -Argument $newArgs -WorkingDirectory $act.WorkingDirectory
                Set-ScheduledTask -TaskName 'RustDeskHbbs' -Action $new | Out-Null
                Write-Host "   task updated: $newArgs (takes effect the next time the task starts)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "   unexpected arguments, left alone: $args0" -ForegroundColor Yellow
    }
}
