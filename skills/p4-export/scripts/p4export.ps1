<#
.SYNOPSIS
    Exports files from a Perforce changelist to a local directory.

.DESCRIPTION
    Runs `p4 describe -s <changelist>` to get the list of affected files,
    strips the configured depot root prefix, recreates the relative directory
    structure under an output folder, and uses `p4 print` to copy each file.

.PARAMETER Changelist
    The Perforce changelist number to export. (Mandatory)

.PARAMETER OutputDir
    Base directory in which the output folder is created.
    Defaults to the current working directory.

.EXAMPLE
    .\p4export.ps1 483078
    .\p4export.ps1 483078 -OutputDir C:\Exports
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Changelist,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = (Get-Location).Path
)

# ---------------------------------------------------------------------------
# Configuration
# $DepotRoot is auto-detected from the changelist files at runtime.
# You may hard-code a value here to override auto-detection, e.g.:
#   $DepotRoot = '//OSX/Fish4_0_Global/'
# ---------------------------------------------------------------------------
$DepotRoot = $null   # set to $null to enable auto-detection
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # let us handle errors per-file

# ---- helper: write a coloured status line ----------------------------------
function Write-Status {
    param([string]$Msg, [System.ConsoleColor]$Color = 'Cyan')
    Write-Host $Msg -ForegroundColor $Color
}

# ---- helper: pause only when running in an interactive console -------------
function Invoke-PauseIfInteractive {
    # [Console]::IsInputRedirected is $true when stdin is piped/redirected
    # (i.e. called non-interactively by a script or tool).
    if (-not [Console]::IsInputRedirected) {
        Write-Host "Press any key to close..." -ForegroundColor Cyan
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}

# ---- 1. Validate that p4 is available --------------------------------------
if (-not (Get-Command p4 -ErrorAction SilentlyContinue)) {
    Write-Error "p4 is not found in PATH. Please install the Perforce command-line client."
    exit 1
}

# ---- 2. Run p4 describe ----------------------------------------------------
Write-Status "Fetching changelist $Changelist ..."
$describeOutput = & p4 describe -s $Changelist 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "p4 describe failed (exit $LASTEXITCODE):`n$describeOutput"
    exit 1
}

# Check for a "no such changelist" style error in the output text
$describeText = $describeOutput -join "`n"
if ($describeText -match 'no such changelist') {
    Write-Error "Changelist $Changelist was not found on the server."
    exit 1
}

# ---- 3. Parse affected file lines ------------------------------------------
# Line format:  ... //depot/path/file.ext#<rev> <action>
$fileEntries = [System.Collections.Generic.List[hashtable]]::new()

foreach ($line in $describeOutput) {
    if ($line -match '^\.\.\.\s+(\S+)#(\d+)\s+(\S+)\s*$') {
        $fileEntries.Add(@{
            DepotPath = $Matches[1]
            Revision  = $Matches[2]
            Action    = $Matches[3]
        })
    }
}

if ($fileEntries.Count -eq 0) {
    Write-Status "No affected files found in changelist $Changelist." 'Yellow'
    exit 0
}

Write-Status "Found $($fileEntries.Count) file(s) in changelist $Changelist."

# ---- 4a. Auto-detect depot root if not configured --------------------------
if (-not $DepotRoot) {
    # The depot root is the portion of the depot path up to and including the
    # third path component, e.g. //depot/stream/ from //depot/stream/a/b/c.cs
    $firstPath = $fileEntries[0].DepotPath   # e.g. //OSX/Fish2_0_Global/Model.Unity/...
    $parts     = $firstPath.TrimStart('/').Split('/')
    # parts[0] = depot name, parts[1] = stream/branch name
    if ($parts.Count -ge 2) {
        $DepotRoot = '//' + $parts[0] + '/' + $parts[1] + '/'
    } else {
        Write-Error "Cannot auto-detect depot root from path: $firstPath"
        exit 1
    }
    Write-Status "Auto-detected depot root: $DepotRoot"
}

# ---- 4. Create output folder -----------------------------------------------
$outputFolder = Join-Path $OutputDir "CL$Changelist"

if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
    Write-Status "Created output folder: $outputFolder"
} else {
    Write-Status "Output folder already exists: $outputFolder" 'Yellow'
}

# ---- 5-8. Copy each file ---------------------------------------------------
$successCount = 0
$failureCount = 0
$failedFiles  = [System.Collections.Generic.List[string]]::new()
$skippedCount = 0
$skippedFiles = [System.Collections.Generic.List[string]]::new()

$index = 0
foreach ($entry in $fileEntries) {
    $index++
    $depotPath = $entry.DepotPath
    $revision  = $entry.Revision
    $fileSpec  = "$depotPath#$revision"

    # Strip depot root to obtain a relative path
    if (-not $depotPath.StartsWith($DepotRoot)) {
        Write-Host "  [$index/$($fileEntries.Count)] SKIP  $depotPath  (outside configured depot root)" -ForegroundColor Yellow
        $failureCount++
        $failedFiles.Add($depotPath)
        continue
    }

    # Skip files that were deleted in this changelist — there is no content to export
    if ($entry.Action -in @('delete', 'move/delete', 'purge')) {
        Write-Host "  [$index/$($fileEntries.Count)] SKIP  $depotPath  (action: $($entry.Action))" -ForegroundColor DarkYellow
        $skippedCount++
        $skippedFiles.Add($depotPath)
        continue
    }

    $relativePath = $depotPath.Substring($DepotRoot.Length)  # e.g. Model.Unity/Assets/.../Foo.cs

    # Build the full local destination path
    # Replace forward slashes with the platform path separator
    $localRelative = $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $destination   = Join-Path $outputFolder $localRelative

    # Ensure the parent directory exists
    $parentDir = Split-Path $destination -Parent
    if (-not (Test-Path $parentDir)) {
        try {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        } catch {
            Write-Host "  [$index/$($fileEntries.Count)] FAIL  $fileSpec  (could not create directory: $parentDir)" -ForegroundColor Red
            $failureCount++
            $failedFiles.Add($depotPath)
            continue
        }
    }

    # Use p4 print to write the file to the destination
    Write-Host "  [$index/$($fileEntries.Count)] Copying $fileSpec ..." -ForegroundColor Gray
    $p4Output = & p4 print -o $destination $fileSpec 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [$index/$($fileEntries.Count)] FAIL  $fileSpec" -ForegroundColor Red
        Write-Host "    $($p4Output -join ' ')" -ForegroundColor DarkRed
        $failureCount++
        $failedFiles.Add($depotPath)
    } else {
        Write-Host "  [$index/$($fileEntries.Count)] OK    -> $destination" -ForegroundColor Green
        $successCount++
    }
}

# ---- 9. Summary ------------------------------------------------------------
Write-Host ""
Write-Status "--- Export Summary ---"
Write-Host "  Changelist : $Changelist"
Write-Host "  Output dir : $outputFolder"
Write-Host "  Succeeded  : $successCount" -ForegroundColor Green

if ($skippedCount -gt 0) {
    Write-Host "  Skipped    : $skippedCount (deleted in this CL)" -ForegroundColor DarkYellow
} else {
    Write-Host "  Skipped    : 0" -ForegroundColor Green
}

if ($failureCount -gt 0) {
    Write-Host "  Failed     : $failureCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Failed files:" -ForegroundColor Red
    foreach ($f in $failedFiles) {
        Write-Host "    $f" -ForegroundColor DarkRed
    }
    if ($skippedCount -gt 0) {
        Write-Host ""
        Write-Host "  Skipped files (deleted in this CL):" -ForegroundColor DarkYellow
        foreach ($f in $skippedFiles) {
            Write-Host "    $f" -ForegroundColor DarkYellow
        }
    }
    Write-Host ""
    Invoke-PauseIfInteractive
    exit 1
} else {
    Write-Host "  Failed     : 0" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host ""
        Write-Host "  Skipped files (deleted in this CL):" -ForegroundColor DarkYellow
        foreach ($f in $skippedFiles) {
            Write-Host "    $f" -ForegroundColor DarkYellow
        }
    }
    Write-Host ""
    Invoke-PauseIfInteractive
    exit 0
}
