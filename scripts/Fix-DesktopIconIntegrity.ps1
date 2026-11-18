<#
.SYNOPSIS
    Restore the default (Medium) integrity level on desktop folders so that
    Windows Explorer can resolve shortcut icons again.

.DESCRIPTION
    Symptom this fixes:
      Some desktop shortcuts show a blank "page + blue arrow" icon while the
      programs themselves still launch. Clearing the icon cache does not help,
      because the cause is a Low Mandatory Level (integrity) label applied to
      the folder, typically by a sandboxed tool that treated the Desktop as
      its workspace parent.

    What it changes:
      Only the integrity label of the folder (and, through inheritance, of its
      children). File contents are not touched.

.PARAMETER Path
    Folders to repair. Default: user Desktop and Public Desktop.

.PARAMETER NoRestart
    Do not restart explorer.exe. Take effect on the next Explorer restart.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Fix-DesktopIconIntegrity.ps1

.EXAMPLE
    .\Fix-DesktopIconIntegrity.ps1 -Path "$env:USERPROFILE\Desktop" -NoRestart
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$NoRestart
)

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop") | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-IntegrityLevel {
    param([string]$Item)
    $lines = & icacls $Item 2>$null
    $m = $lines | Select-String -Pattern 'Mandatory Label\\(\w+) Mandatory Level'
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return 'Medium (inherited)'
}

$changed = 0
foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $before = Get-IntegrityLevel -Item $p
    Write-Host ("{0}" -f $p)
    Write-Host ("  before: {0}" -f $before)
    if ($before -notlike 'Low*') {
        Write-Host "  skip  : not a Low integrity label" -ForegroundColor DarkGray
        continue
    }
    & icacls "$p" /setintegritylevel "(OI)(CI)Medium" | Out-Null
    $after = Get-IntegrityLevel -Item $p
    Write-Host ("  after : {0}" -f $after) -ForegroundColor Green
    $changed++
}

if ($changed -eq 0) {
    Write-Host ""
    Write-Host "Nothing to repair. If icons are still blank, run Check-IconHealth.ps1" -ForegroundColor Yellow
}

if (-not $NoRestart) {
    Write-Host ""
    Write-Host "Restarting explorer.exe ..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Start-Sleep -Seconds 3
    Write-Host "Done. Verify: icacls `"$env:USERPROFILE\Desktop`" shows Medium." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Skipped Explorer restart (-NoRestart)." -ForegroundColor Yellow
}
