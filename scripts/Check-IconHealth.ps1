<#
.SYNOPSIS
    Read-only health check for desktop shortcuts.

.DESCRIPTION
    For every *.lnk in the given folders it reports:
      - whether the target still exists
      - the integrity level of the .lnk (a Low label can break icon rendering)
      - whether a custom icon source is present and structurally valid

    Nothing is modified by this script.

.PARAMETER Path
    Folders to scan for *.lnk files.
    Default: user Desktop and Public Desktop.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Check-IconHealth.ps1

.EXAMPLE
    .\Check-IconHealth.ps1 -Path "$env:USERPROFILE\Desktop"
#>
[CmdletBinding()]
param([string[]]$Path)

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

function Test-IcoFile {
    param([string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return 'missing' }
    try { $b = [System.IO.File]::ReadAllBytes($File) } catch { return 'unreadable' }
    if ($b.Length -lt 6) { return 'invalid: too small' }
    if ([BitConverter]::ToUInt16($b, 0) -ne 0 -or [BitConverter]::ToUInt16($b, 2) -ne 1) { return 'invalid: not an ICO' }
    $count = [BitConverter]::ToUInt16($b, 4)
    if ($count -eq 0) { return 'invalid: zero entries' }
    for ($i = 0; $i -lt $count; $i++) {
        $o = 6 + $i * 16
        if ($o + 16 -gt $b.Length) { return 'invalid: truncated directory' }
        $len = [BitConverter]::ToUInt32($b, $o + 8)
        $off = [BitConverter]::ToUInt32($b, $o + 12)
        if ($len -eq 0 -or ($off + $len) -gt $b.Length) { return "invalid: entry $i out of bounds" }
    }
    return "ok ($count entries)"
}

$shell = New-Object -ComObject WScript.Shell
$rows = @()

foreach ($folder in $Path) {
    $folderLevel = Get-IntegrityLevel -Item $folder
    Write-Host ""
    Write-Host ("== " + $folder) -ForegroundColor Cyan
    Write-Host ("   integrity : " + $folderLevel)
    if ($folderLevel -like 'Low*') {
        Write-Host "   WARNING   : Low integrity label -> shortcut icons may render blank." -ForegroundColor Yellow
        Write-Host "               fix with: scripts\Fix-DesktopIconIntegrity.ps1" -ForegroundColor Yellow
    }

    foreach ($f in (Get-ChildItem -LiteralPath $folder -Filter *.lnk -ErrorAction SilentlyContinue)) {
        $lnk = $shell.CreateShortcut($f.FullName)

        $targetOk = $false
        if ($lnk.TargetPath) { $targetOk = Test-Path -LiteralPath $lnk.TargetPath }

        $iconPath = ''
        if ($lnk.IconLocation) { $iconPath = ($lnk.IconLocation -split ',')[0].Trim('"') }

        $iconState = '-'
        if ($iconPath) {
            if ($iconPath -like '*.ico') { $iconState = Test-IcoFile -File $iconPath }
            elseif (Test-Path -LiteralPath $iconPath) { $iconState = 'ok (resource)' }
            else { $iconState = 'missing' }
        }

        $level = Get-IntegrityLevel -Item $f.FullName

        $verdict = 'ok'
        if ($level -like 'Low*') { $verdict = 'FIX: low integrity' }
        elseif (-not $targetOk) { $verdict = 'BROKEN: target missing' }
        elseif ($iconState -like 'invalid*' -or $iconState -eq 'missing') { $verdict = 'FIX: icon source' }

        $rows += [PSCustomObject]@{
            Folder       = Split-Path $folder -Leaf
            Name         = $f.Name
            TargetExists = $targetOk
            Integrity    = $level
            IconSource   = $iconState
            Verdict      = $verdict
        }
    }
}

Write-Host ""
$rows | Sort-Object Verdict, Name | Format-Table -AutoSize

$bad = @($rows | Where-Object { $_.Verdict -notlike 'ok' }).Count
Write-Host ("Checked: {0}   Need attention: {1}" -f $rows.Count, $bad)

if ($bad -gt 0) { exit 1 } else { exit 0 }
