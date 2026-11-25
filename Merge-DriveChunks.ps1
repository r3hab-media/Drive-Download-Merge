<#
.SYNOPSIS
    Puts a split Google Drive download back together into one folder.

.DESCRIPTION
    When you download a large Google Drive folder, Google splits it into several zip files
    (drive-download-...-001.zip, -002.zip, and so on). Each zip holds part of the same folder
    structure. After you extract them, you end up with several folders that all look alike.

    This script merges every extracted drive-download-* folder into one "Merged" folder.

    It never overwrites or deletes anything.
      - A file at a new path is copied or moved into Merged.
      - A file that is identical (same SHA256 hash) to one already in Merged is skipped and
        left where it is.
      - A file with the same name but different content is kept as "name (from 003).ext".

    Empty folders are recreated. Every file is written to a CSV log as it is processed, and the
    script checks that every file landed in Merged before it finishes.

    Run it with no arguments (double-click style, or right-click > Run with PowerShell) and it
    does a dry run first, shows you what it plans to do, and asks before changing anything.

.PARAMETER Root
    Folder that holds the extracted drive-download-* folders. Defaults to the folder this
    script is saved in.

.PARAMETER Destination
    Where the merged folder goes. Defaults to <Root>\Merged.

.PARAMETER Pattern
    Which folders count as download chunks. Defaults to 'drive-download-*'.
    Use 'takeout-*' for Google Takeout exports.

.PARAMETER Copy
    Copy files into Merged. The original folders stay untouched. Needs as much free space as
    the download itself.

.PARAMETER Move
    Move files into Merged. Much faster on the same drive and needs no extra space.
    Identical duplicates stay behind in the original folders.

.EXAMPLE
    .\Merge-DriveChunks.ps1
    Dry run, then asks whether to move, copy, or quit.

.EXAMPLE
    .\Merge-DriveChunks.ps1 -Move
    Moves everything into .\Merged with no questions.

.EXAMPLE
    .\Merge-DriveChunks.ps1 -Root 'E:\My Drive Export' -Copy
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Destination,
    [string]$Pattern = 'drive-download-*',
    [switch]$Copy,
    [switch]$Move
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# No arguments means someone launched it from Explorer. Walk them through it and keep the window open.
$Interactive = ($PSBoundParameters.Count -eq 0)
$exitCode = 0

function Write-Step([string]$Text) { Write-Host $Text -ForegroundColor Cyan }

function Get-Inventory {
    $zips = @(Get-ChildItem -LiteralPath $Root -File |
        Where-Object {
            $_.Extension -eq '.zip' -and
            $_.Name -like $Pattern -and
            -not (Test-Path -LiteralPath ([IO.Path]::Combine($Root, $_.BaseName)))
        })
    if ($zips.Count -gt 0) {
        $names = ($zips | ForEach-Object { '  ' + $_.Name }) -join [Environment]::NewLine
        throw ("These zip files have not been extracted yet:" + [Environment]::NewLine + $names +
            [Environment]::NewLine + "Right-click each one, choose Extract All, keep the suggested folder name, then run this again.")
    }

    $chunks = @(Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.Name -like $Pattern } |
        Sort-Object Name)

    if ($chunks.Count -eq 0) {
        throw "No folders named like '$Pattern' were found in $Root. Save this script in the same folder as your extracted downloads and run it again."
    }

    Write-Step "Found $($chunks.Count) download folder(s) in $Root"
    $chunks | ForEach-Object { Write-Host "  $($_.Name)" }

    # Google numbers the zips 001, 002, 003... Warn if there is a gap.
    $numbers = @($chunks | ForEach-Object { ($_.Name -split '-')[-1] } |
        Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
    if ($numbers.Count -gt 0) {
        $missing = @(1..$numbers[-1] | Where-Object { $numbers -notcontains $_ })
        if ($missing.Count -gt 0) {
            $list = ($missing | ForEach-Object { '{0:D3}' -f $_ }) -join ', '
            Write-Warning "Folder number(s) $list look like they are missing. Check that every zip was downloaded and extracted."
        }
    }

    Write-Step 'Scanning files. This can take a few minutes on a large download...'
    $files = [System.Collections.Generic.List[object]]::new()
    $dirs  = [System.Collections.Generic.List[string]]::new()

    foreach ($c in $chunks) {
        $tag = ($c.Name -split '-')[-1]
        $prefixLen = $c.FullName.TrimEnd('\', '/').Length + 1

        foreach ($d in Get-ChildItem -LiteralPath $c.FullName -Recurse -Directory -Force) {
            $dirs.Add($d.FullName.Substring($prefixLen))
        }
        foreach ($f in Get-ChildItem -LiteralPath $c.FullName -Recurse -File -Force) {
            $files.Add([pscustomobject]@{
                Chunk    = $c.Name
                Tag      = $tag
                Source   = $f.FullName
                Relative = $f.FullName.Substring($prefixLen)
                Bytes    = $f.Length
            })
        }
    }

    $total = [int64]0
    foreach ($f in $files) { $total += $f.Bytes }
    Write-Host ("  {0:N0} files, {1:N2} GB, {2:N0} folders" -f $files.Count, ($total / 1GB), $dirs.Count)

    [pscustomobject]@{ Files = $files; Dirs = $dirs; TotalBytes = $total }
}

function ConvertTo-CsvLine([object[]]$Values) {
    ($Values | ForEach-Object { '"' + ([string]$_).Replace('"', '""') + '"' }) -join ','
}

function Invoke-Merge {
    param($Inv, [string]$Mode)   # Mode: DryRun, Copy, Move

    $dry = ($Mode -eq 'DryRun')
    Write-Host ''
    switch ($Mode) {
        'DryRun' { Write-Step 'DRY RUN: planning only. Nothing will be changed.' }
        'Copy'   { Write-Step "COPYING files into $Destination" }
        'Move'   { Write-Step "MOVING files into $Destination" }
    }

    if ($Mode -eq 'Copy') {
        $free = ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Destination))).AvailableFreeSpace
        if ($free -lt ($Inv.TotalBytes * 1.05)) {
            throw ("Not enough free space to copy ({0:N2} GB free, {1:N2} GB needed). Use Move instead." -f ($free / 1GB), ($Inv.TotalBytes / 1GB))
        }
    }

    if (-not $dry) {
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($rel in $Inv.Dirs) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($Destination, $rel))
        }
    }

    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logPath = [IO.Path]::Combine($Root, "merge-log-$stamp-$($Mode.ToLower()).csv")

    # Log is written row by row, so a run that gets stopped partway still has a record.
    $writer = [IO.StreamWriter]::new($logPath, $false, [Text.UTF8Encoding]::new($true))
    $writer.AutoFlush = $true
    $writer.WriteLine('Status,Chunk,Relative,Source,Destination,Bytes')

    # $placed: every destination claimed this run -> the file that currently holds that content.
    $placed = @{}
    $hashes = @{}
    function Get-Sha256([string]$Path) {
        if (-not $hashes.ContainsKey($Path)) {
            $hashes[$Path] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        }
        $hashes[$Path]
    }

    $log = [System.Collections.Generic.List[object]]::new()
    $count = $Inv.Files.Count
    $i = 0

    try {
        foreach ($f in $Inv.Files) {
            $i++
            if ($i % 25 -eq 0 -or $i -eq $count) {
                Write-Progress -Activity "Merge ($Mode)" -Status "$i of $count" -PercentComplete ($i / $count * 100)
            }

            $target = [IO.Path]::Combine($Destination, $f.Relative)
            $status = 'New'

            $existing = $null
            if ($placed.ContainsKey($target))       { $existing = $placed[$target] }
            elseif (Test-Path -LiteralPath $target) { $existing = $target }

            if ($existing) {
                $existingLen = (Get-Item -LiteralPath $existing -Force).Length
                if ($existingLen -eq $f.Bytes -and (Get-Sha256 $existing) -eq (Get-Sha256 $f.Source)) {
                    $status = 'Duplicate'
                }
                else {
                    $dir  = [IO.Path]::GetDirectoryName($target)
                    $base = [IO.Path]::GetFileNameWithoutExtension($target)
                    $ext  = [IO.Path]::GetExtension($target)
                    $n = 0
                    do {
                        $suffix = if ($n -eq 0) { " (from $($f.Tag))" } else { " (from $($f.Tag)-$n)" }
                        $target = [IO.Path]::Combine($dir, "$base$suffix$ext")
                        $n++
                    } while ($placed.ContainsKey($target) -or (Test-Path -LiteralPath $target))
                    $status = 'Renamed'
                }
            }

            if ($status -ne 'Duplicate') {
                if (-not $dry) {
                    try {
                        if ($Mode -eq 'Move') { [IO.File]::Move($f.Source, $target) }
                        else                  { [IO.File]::Copy($f.Source, $target, $false) }  # $false = never overwrite
                    }
                    catch {
                        $status = 'FAILED: ' + $_.Exception.Message
                    }
                }
                if ($status -notlike 'FAILED*') {
                    # In a dry run the content is still at the source, so compare against that.
                    $placed[$target] = if ($dry) { $f.Source } else { $target }
                }
            }

            $row = [pscustomobject]@{
                Status      = $status
                Chunk       = $f.Chunk
                Relative    = $f.Relative
                Source      = $f.Source
                Destination = $target
                Bytes       = $f.Bytes
            }
            $log.Add($row)
            $writer.WriteLine((ConvertTo-CsvLine @($row.Status, $row.Chunk, $row.Relative, $row.Source, $row.Destination, $row.Bytes)))
        }
    }
    finally {
        $writer.Dispose()
        Write-Progress -Activity "Merge ($Mode)" -Completed
    }

    $bad = @()
    if (-not $dry) {
        Write-Step 'Checking that every file made it...'
        $bad = @($log | Where-Object {
            $_.Status -like 'FAILED*' -or
            -not (Test-Path -LiteralPath $_.Destination) -or
            (Get-Item -LiteralPath $_.Destination -Force).Length -ne $_.Bytes
        })
    }

    Write-Host ''
    if ($dry) { Write-Host 'Dry run finished. Nothing was changed.' -ForegroundColor Green }
    else      { Write-Host 'Finished.' -ForegroundColor Green }

    $log | Group-Object { ($_.Status -split ':')[0] } | Sort-Object Name |
        ForEach-Object { Write-Host ("  {0,-10} {1:N0}" -f $_.Name, $_.Count) }
    Write-Host ("  Files found: {0:N0}   Files logged: {1:N0}" -f $count, $log.Count)
    Write-Host "  Log: $logPath"

    if ($bad.Count -gt 0) {
        Write-Host ''
        Write-Host "$($bad.Count) file(s) did not make it. Open the log and look for rows marked FAILED. Do NOT delete the original folders." -ForegroundColor Red
        return $false
    }

    if (-not $dry) {
        Write-Host ''
        Write-Host "Every file is accounted for in $Destination" -ForegroundColor Green
        if ($Mode -eq 'Move') {
            Write-Host 'Anything left in the original folders is an identical copy of a file already in Merged.'
        }
        Write-Host 'Look through Merged first. Delete the original drive-download folders yourself once you are happy.'
    }
    return $true
}

try {
    if ($Copy -and $Move) { throw 'Pick one: -Copy or -Move, not both.' }

    if (-not $Root) {
        $Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).ProviderPath }
    }
    $Root = (Resolve-Path -LiteralPath $Root).ProviderPath
    if (-not $Destination) { $Destination = [IO.Path]::Combine($Root, 'Merged') }

    $inv = Get-Inventory

    $mode = if ($Move) { 'Move' } elseif ($Copy) { 'Copy' } else { 'DryRun' }
    $ok = Invoke-Merge -Inv $inv -Mode $mode

    if ($ok -and $mode -eq 'DryRun' -and $Interactive) {
        Write-Host ''
        Write-Host 'Ready to merge. Pick one:' -ForegroundColor Yellow
        Write-Host '  M = Move  (recommended) Fast, needs no extra disk space. Files leave the original folders.'
        Write-Host ('  C = Copy  Leaves the original folders untouched. Needs about {0:N1} GB free.' -f ($inv.TotalBytes / 1GB))
        Write-Host '  Enter = Quit without changing anything'
        $answer = ([string](Read-Host 'Your choice')).Trim().ToUpper()

        if ($answer -eq 'M')     { $ok = Invoke-Merge -Inv $inv -Mode 'Move' }
        elseif ($answer -eq 'C') { $ok = Invoke-Merge -Inv $inv -Mode 'Copy' }
        else                     { Write-Host 'Quit. Nothing was changed.' }
    }

    if (-not $ok) { $exitCode = 2 }
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}
finally {
    if ($Interactive) {
        Write-Host ''
        [void](Read-Host 'Press Enter to close this window')
    }
}
exit $exitCode
