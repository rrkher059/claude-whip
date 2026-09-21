<#
.SYNOPSIS
    One-command install for claude-whip. Safe to run repeatedly.

.DESCRIPTION
    Installs missing dependencies, copies the sixteen skills into
    ~/.claude/skills, generates whip.wav, creates a Startup shortcut, starts
    the tool, and finishes by running --doctor so you can see the result.

    Every step is idempotent: existing dependencies are left alone, the
    shortcut is rewritten rather than duplicated, and an already-running
    instance is restarted rather than doubled.

.PARAMETER NoStartup
    Skip creating the Startup shortcut.

.PARAMETER NoLaunch
    Install everything but do not start whip.ahk.
#>
[CmdletBinding()]
param(
    [switch]$NoStartup,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($n, $t) { Write-Host ""; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    $t" -ForegroundColor Green }
function Info($t)     { Write-Host "    $t" -ForegroundColor Gray }
function Warn($t)     { Write-Host "    $t" -ForegroundColor Yellow }
function Die($t)      { Write-Host ""; Write-Host "  $t" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  claude-whip installer" -ForegroundColor Yellow
Write-Host "  ---------------------" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 1. deps --
Step 1 "Dependencies"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Warn "winget not found - install AutoHotkey v2 manually from autohotkey.com"
} else {
    foreach ($id in 'AutoHotkey.AutoHotkey', 'Git.Git', 'GitHub.cli') {
        $have = (winget list --id $id --exact --accept-source-agreements 2>$null | Out-String) -match [regex]::Escape($id)
        if ($have) {
            Info "$id already installed"
        } else {
            Info "installing $id ..."
            winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements | Out-Null
            Ok "$id installed"
        }
    }
}

# ------------------------------------------------------------ 2. find ahk --
Step 2 "Locating AutoHotkey v2"
$candidates = @(
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe"
    "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe"
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey32.exe"
)
$ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) {
    Die "AutoHotkey v2 not found. Checked:`n    $($candidates -join "`n    ")"
}
Ok $ahk

# --------------------------------------------------------------- 3. skills --
Step 3 "Installing skills"
$skillsSrc = Join-Path $root 'skills'
$skillsDst = Join-Path $env:USERPROFILE '.claude\skills'
if (-not (Test-Path $skillsSrc)) { Die "skills/ not found next to install.ps1" }
New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
$n = 0
foreach ($d in Get-ChildItem $skillsSrc -Directory) {
    $target = Join-Path $skillsDst $d.Name
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item (Join-Path $d.FullName 'SKILL.md') $target -Force
    $n++
}
Ok "$n skills copied to $skillsDst"

# ------------------------------------------------------------------ 4. wav --
Step 4 "Sound"
$wav = Join-Path $root 'whip.wav'
$gen = Join-Path $root 'gen-whip-wav.ps1'
if (Test-Path $wav) {
    Info ("whip.wav already present ({0:N0} bytes)" -f (Get-Item $wav).Length)
} elseif (Test-Path $gen) {
    & powershell -ExecutionPolicy Bypass -File $gen | ForEach-Object { Info $_ }
    Ok "whip.wav generated"
} else {
    Warn "gen-whip-wav.ps1 missing - the tool will fall back to SoundBeep"
}

# -------------------------------------------------------------- 5. startup --
Step 5 "Startup shortcut"
if ($NoStartup) {
    Info "skipped (-NoStartup)"
} else {
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'claude-whip.lnk'
    $ws  = New-Object -ComObject WScript.Shell
    $s   = $ws.CreateShortcut($lnk)
    $s.TargetPath       = $ahk
    $s.Arguments        = '"' + (Join-Path $root 'whip.ahk') + '"'
    $s.WorkingDirectory = $root
    $s.Description      = 'claude-whip'
    $s.Save()
    Ok $lnk
}

# --------------------------------------------------------------- 6. launch --
Step 6 "Starting"
$running = Get-Process AutoHotkey64, AutoHotkey32 -ErrorAction SilentlyContinue |
           Where-Object { $_.Path -eq $ahk }
if ($running) {
    Info "restarting the running instance"
    $running | Stop-Process -Force -Confirm:$false
    Start-Sleep -Milliseconds 500
}
if ($NoLaunch) {
    Info "skipped (-NoLaunch)"
} else {
    Start-Process $ahk -ArgumentList ('"' + (Join-Path $root 'whip.ahk') + '"') -WorkingDirectory $root
    Start-Sleep -Seconds 2
    $proc = Get-Process AutoHotkey64, AutoHotkey32 -ErrorAction SilentlyContinue
    if ($proc) { Ok ("running (pid {0})" -f $proc[0].Id) } else { Warn "process did not stay running" }
}

# --------------------------------------------------------------- 7. doctor --
Step 7 "Health check"
Write-Host ""
$tmpOut = [System.IO.Path]::GetTempFileName()
$tmpErr = [System.IO.Path]::GetTempFileName()
$p = Start-Process -FilePath $ahk `
        -ArgumentList ('"' + (Join-Path $root 'whip.ahk') + '"'), '--doctor' `
        -NoNewWindow -PassThru -Wait -WorkingDirectory $root `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
Get-Content $tmpOut | ForEach-Object { Write-Host "  $_" }
Remove-Item $tmpOut, $tmpErr -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  Done. Focus your Claude Code terminal and press F1." -ForegroundColor Yellow
Write-Host "  If nothing happens, the window title did not match - run:" -ForegroundColor DarkGray
Write-Host "      .\whip.ahk --pick" -ForegroundColor DarkGray
Write-Host ""
