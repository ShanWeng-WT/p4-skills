#Requires -Version 5.1
# Move-ConflictFiles.ps1
# Moves all unresolved conflict files from a given P4 changelist to a new pending changelist.

param(
    [Parameter(Mandatory = $true)]
    [string]$Changelist
)

# ── Encoding Safety ──────────────────────────────────────────────
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ── Dependency Check ─────────────────────────────────────────────
if (-not (Get-Command p4 -ErrorAction SilentlyContinue)) {
    Write-Error "'p4' is not installed or not on PATH."
    exit 1
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function Parse-P4Info([string[]]$lines) {
    $result = @{}
    foreach ($line in $lines) {
        if ($line -match '^Client name:\s+(.+)$')  { $result['Client'] = $matches[1].Trim() }
        if ($line -match '^Client root:\s+(.+)$')  { $result['Root']   = $matches[1].Trim() }
        if ($line -match '^User name:\s+(.+)$')    { $result['User']   = $matches[1].Trim() }
    }
    return $result
}

function Normalize-Path([string]$p) {
    return $p.TrimEnd('\','/').Replace('/', '\').ToLowerInvariant()
}

function Is-UnderRoot([string]$dir, [string]$root) {
    $nd = Normalize-Path $dir
    $nr = Normalize-Path $root
    return $nd -eq $nr -or $nd.StartsWith($nr + '\')
}

function Get-P4Client {
    # Step 1: query current active client
    $rawInfo = p4 info 2>&1
    $info    = Parse-P4Info $rawInfo
    $cwd     = (Get-Location).Path

    # Step 2: check if CWD is under the active client root
    if ($info['Root'] -and (Is-UnderRoot $cwd $info['Root'])) {
        return $info['Client']
    }

    # Step 3a: derive candidate from CWD leaf directory name
    $candidate = Split-Path $cwd -Leaf
    $candidateInfo = p4 -c $candidate info 2>&1
    $ci = Parse-P4Info $candidateInfo
    if ($ci['Root'] -and (Is-UnderRoot $cwd $ci['Root'])) {
        Write-Host "P4 Workspace Mismatch Detected"
        Write-Host "  Active client : $($info['Client']) (root: $($info['Root']))"
        Write-Host "  Current dir   : $cwd"
        Write-Host "  Corrected to  : $candidate (root: $($ci['Root']))"
        Write-Host ""
        return $candidate
    }

    # Step 3b: search all clients for the current user
    if ($info['User']) {
        $clients = p4 clients -u $info['User'] 2>&1
        $bestMatch = $null
        $bestLen   = 0
        foreach ($line in $clients) {
            if ($line -match '^Client\s+(\S+)\s+\S+\s+root\s+(.+?)\s+') {
                $cName = $matches[1]
                $cRoot = $matches[2].Trim()
                if ((Is-UnderRoot $cwd $cRoot) -and $cRoot.Length -gt $bestLen) {
                    $bestMatch = $cName
                    $bestLen   = $cRoot.Length
                }
            }
        }
        if ($bestMatch) {
            $matchRoot = (p4 -c $bestMatch info 2>&1 | Where-Object { $_ -match '^Client root:' }) -replace '^Client root:\s+',''
            Write-Host "P4 Workspace Mismatch Detected"
            Write-Host "  Active client : $($info['Client']) (root: $($info['Root']))"
            Write-Host "  Current dir   : $cwd"
            Write-Host "  Corrected to  : $bestMatch (root: $matchRoot)"
            Write-Host ""
            return $bestMatch
        }
    }

    return $null
}

function Invoke-P4ChangeInput([string]$clientName, [string]$spec) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'p4'
    $psi.Arguments = "-c $clientName change -i"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    # Perforce rejects a UTF-8 BOM at the start of the spec as an unknown field name.
    $psi.StandardInputEncoding = New-Object System.Text.UTF8Encoding($false)
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.Write($spec)
    $process.StandardInput.Close()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return @{
        ExitCode = $process.ExitCode
        Output   = ($stdout + $stderr).Trim()
    }
}

# ── Entry point ───────────────────────────────────────────────────────────────

$Changelist = $Changelist.Trim()
if ($Changelist -notmatch '^\d+$') {
    Write-Error "Invalid changelist number: '$Changelist'"
    exit 1
}

# Detect current P4 client
$client = Get-P4Client
if (-not $client) {
    Write-Error "Could not determine P4 client from 'p4 info'. Ensure p4 is on PATH and you are logged in."
    exit 1
}

Write-Host "Client  : $client"
Write-Host "Source CL: $Changelist"
Write-Host ""

# Verify the changelist exists and is pending
$describe = p4 -c $client describe -s $Changelist 2>&1
if ($LASTEXITCODE -ne 0 -or ($describe -join "`n") -match 'no such changelist') {
    Write-Error "Changelist $Changelist not found."
    exit 1
}
if ($describe[0] -notmatch '\*pending\*') {
    Write-Error "Changelist $Changelist is not a pending changelist."
    exit 1
}

# Find all unresolved / conflict files in the workspace that belong to this CL
# p4 resolve -n lists files that still need resolving; filter to those in our CL
Write-Host "Searching for unresolved files..."
$allConflicts = p4 -c $client resolve -n 2>&1
if ($LASTEXITCODE -ne 0 -and $allConflicts -match 'error') {
    Write-Error "Failed to run 'p4 resolve -n': $allConflicts"
    exit 1
}

# Extract local file paths from lines like:
#   D:\path\to\file - merging //depot/...
#   D:\path\to\file - vs //depot/...
#   D:\path\to\file - resolving branch from //depot/...
$conflictPaths = @()
foreach ($line in $allConflicts) {
    if ($line -match '^(.+?) - (merging|vs |resolving)') {
        $conflictPaths += $matches[1].Trim()
    }
}

if ($conflictPaths.Count -eq 0) {
    Write-Host "No unresolved conflict files found in workspace for client '$client'."
    exit 0
}

# Cross-reference with files actually opened in the source changelist
Write-Host "Searching for conflict files in CL $Changelist..."
$openedInCL = p4 -c $client opened -c $Changelist 2>&1
# Build a set of depot paths open in the CL
$clDepotPaths = @{}
foreach ($line in $openedInCL) {
    if ($line -match '^(//[^#]+)#') {
        $clDepotPaths[$matches[1]] = $true
    }
}

# For each conflict local path, get its depot path and check membership
$filesToMove = @()
foreach ($localPath in $conflictPaths) {
    $whereOut = p4 -c $client where "$localPath" 2>&1
    # "p4 where" output: depotPath mappedPath localPath
    if ($whereOut -match '^(//\S+)\s') {
        $depotPath = $matches[1]
        if ($clDepotPaths.ContainsKey($depotPath)) {
            $filesToMove += $localPath
        }
    }
}

if ($filesToMove.Count -eq 0) {
    Write-Host "No conflict files from CL $Changelist found (they may already be resolved or in a different CL)."
    exit 0
}

Write-Host "Found $($filesToMove.Count) conflict file(s) in CL $Changelist."
Write-Host ""

# Create the new pending changelist
$changeSpec = @"
Change: new
Client: $client
Status: new
Description:
	Conflict files from CL $Changelist - requires manual resolve
"@

$newCLResult = Invoke-P4ChangeInput -clientName $client -spec $changeSpec
if ($newCLResult.ExitCode -ne 0) {
    Write-Error "Failed to create new changelist: $($newCLResult.Output)"
    exit 1
}

$newCL = $null
if ($newCLResult.Output -match 'Change (\d+) created') {
    $newCL = $matches[1]
} else {
    Write-Error "Could not parse new changelist number from: $($newCLResult.Output)"
    exit 1
}

Write-Host "Created new changelist: $newCL"
Write-Host "Moving files..."
Write-Host ""

# Reopen each conflict file into the new changelist
$successCount = 0
$failCount    = 0
foreach ($file in $filesToMove) {
    $result = p4 -c $client reopen -c $newCL "$file" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $result"
        $successCount++
    } else {
        Write-Warning "  [FAIL] $file : $result"
        $failCount++
    }
}

Write-Host ""
Write-Host "────────────────────────────────────────────"
Write-Host "Done."
Write-Host "  Source CL       : $Changelist  ($($filesToMove.Count - $failCount) files removed)"
Write-Host "  New conflict CL : $newCL  ($successCount files)"
if ($failCount -gt 0) {
    Write-Warning "  $failCount file(s) failed to move — check warnings above."
}
