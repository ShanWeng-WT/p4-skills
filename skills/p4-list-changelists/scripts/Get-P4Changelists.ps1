#Requires -Version 5.1
<#
.SYNOPSIS
    Lists submitted Perforce changelists that match explicit filters.

.DESCRIPTION
    Accepts repeated -Filter tokens in key:value form and runs `p4 changes`
    with server-side filters where possible. Submitted changelists are printed
    as compact console text.

.PARAMETER Filter
    Repeated filter token. Supported keys:
      date:yyyy/MM/dd HH:mm - yyyy/MM/dd HH:mm
      owner:<p4_user>
      description:<literal substring>
      cl:<min>-<max>

.PARAMETER PreviewCommand
    Prints the p4 command that would run after filter parsing. Does not connect
    to the P4 server.

.EXAMPLE
    .\Get-P4Changelists.ps1 -Workspace "my_workspace" -Filter "date:2026/04/28 09:00 - 2026/04/29 18:00"

.EXAMPLE
    .\Get-P4Changelists.ps1 -Filter "description:fix crash" -Filter "cl:00001-00005"

.EXAMPLE
    .\Get-P4Changelists.ps1 -Filter "client:my_workspace"

.EXAMPLE
    .\Get-P4Changelists.ps1 -P4Stream "//depot/main" -Filter "owner:alice"
#>

param(
    [Parameter()]
    [string]$Workspace,

    [Parameter()]
    [string]$P4Stream,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# -- Encoding Safety ---------------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:InvariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Write-Usage {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" [-Workspace <workspace>] [-P4Stream <stream>] -Filter `"date:2026/04/28 09:00 - 2026/04/29 18:00`" -Filter `"owner:alice`""
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Cyan
    Write-Host "  -Workspace <workspace>  Filter by workspace/client name (optional, uses current workspace if not specified)"
    Write-Host "  -P4Stream <stream>      Filter by depot stream path (e.g. //depot/main)"
    Write-Host ""
    Write-Host "Supported filters:" -ForegroundColor Cyan
    Write-Host "  date:yyyy/MM/dd HH:mm - yyyy/MM/dd HH:mm"
    Write-Host "  owner:<p4_user>"
    Write-Host "  client:<workspace_name>"
    Write-Host "  stream:<stream_path>"
    Write-Host "  description:<literal substring>"
    Write-Host "  cl:<min>-<max>"
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    Write-Usage
    exit 1
}

function Parse-CommandLine {
    param([string[]]$RawArguments)

    if ($null -eq $RawArguments) {
        $RawArguments = @()
    }

    $filters = New-Object System.Collections.Generic.List[string]
    $preview = $false

    for ($i = 0; $i -lt $RawArguments.Count; $i++) {
        $argument = $RawArguments[$i]

        if ($argument -ieq '-PreviewCommand') {
            if ($preview) {
                Fail "Duplicate -PreviewCommand switch."
            }
            $preview = $true
            continue
        }

        if ($argument -ieq '-Filter') {
            if ($i + 1 -ge $RawArguments.Count) {
                Fail "-Filter requires a value."
            }

            $filters.Add($RawArguments[$i + 1])
            $i++
            continue
        }

        Fail "Unknown argument '$argument'. Use repeated -Filter values and optional -PreviewCommand."
    }

    return @{
        Filters = [string[]]$filters.ToArray()
        PreviewCommand = $preview
    }
}

function Parse-ExactDateTime {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $formats = [string[]]@(
        'yyyy/MM/dd HH:mm',
        'yyyy/MM/dd HH:mm:ss',
        'yyyy/MM/dd:HH:mm',
        'yyyy/MM/dd:HH:mm:ss'
    )

    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($Value, $formats, $script:InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        Fail "Invalid $Label date '$Value'. Use yyyy/MM/dd HH:mm."
    }

    return $parsed
}

function Parse-DateFilter {
    param([Parameter(Mandatory = $true)][string]$Value)

    $datePattern = '\d{4}/\d{2}/\d{2}(?:\s|:)\d{2}:\d{2}(?::\d{2})?'
    if ($Value -notmatch "^\s*(?<from>$datePattern)\s+-\s+(?<to>$datePattern)\s*$") {
        Fail "Invalid date filter '$Value'. Use date:yyyy/MM/dd HH:mm - yyyy/MM/dd HH:mm."
    }

    $fromText = $Matches['from']
    $toText = $Matches['to']
    $from = Parse-ExactDateTime -Value $fromText -Label 'start'
    $to = Parse-ExactDateTime -Value $toText -Label 'end'

    if ($toText -notmatch '(?:\s|:)\d{2}:\d{2}:\d{2}$') {
        $to = $to.AddMinutes(1).AddSeconds(-1)
    }

    if ($from -gt $to) {
        Fail "Invalid date filter '$Value'. Start date must be earlier than or equal to end date."
    }

    return @{
        From = $from
        To = $to
    }
}

function Parse-ChangelistRange {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '^\s*(?<min>\d+)\s*-\s*(?<max>\d+)\s*$') {
        Fail "Invalid changelist range '$Value'. Use cl:<min>-<max>."
    }

    try {
        $min = [int64]::Parse($Matches['min'], $script:InvariantCulture)
        $max = [int64]::Parse($Matches['max'], $script:InvariantCulture)
    } catch {
        Fail "Invalid changelist range '$Value'. Changelist numbers must fit in a 64-bit integer."
    }

    if ($min -gt $max) {
        Fail "Invalid changelist range '$Value'. Minimum CL must be less than or equal to maximum CL."
    }

    return @{
        Min = $min
        Max = $max
    }
}

function Parse-Filters {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Tokens)

    if ($null -eq $Tokens) {
        $Tokens = @()
    }

    $allowedKeys = @{
        'date' = $true
        'owner' = $true
        'client' = $true
        'stream' = $true
        'description' = $true
        'cl' = $true
    }
    $seen = @{}
    $result = @{
        Date = $null
        Owner = $null
        Client = $null
        Stream = $null
        Description = $null
        CL = $null
    }

    foreach ($token in $Tokens) {
        if ([string]::IsNullOrWhiteSpace($token)) {
            Fail "Filter tokens cannot be empty."
        }

        $separator = $token.IndexOf(':')
        if ($separator -lt 1) {
            Fail "Invalid filter '$token'. Use key:value format."
        }

        $key = $token.Substring(0, $separator).Trim().ToLowerInvariant()
        $value = $token.Substring($separator + 1).Trim()

        if (-not $allowedKeys.ContainsKey($key)) {
            Fail "Unknown filter key '$key'. Supported keys are: date, owner, client, stream, description, cl."
        }
        if ($seen.ContainsKey($key)) {
            Fail "Duplicate filter key '$key'. Each filter can be supplied only once."
        }
        $seen[$key] = $true

        switch ($key) {
            'date' {
                $result.Date = Parse-DateFilter -Value $value
            }
            'owner' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    Fail "owner filter cannot be empty."
                }
                if ($value -match '\s' -or $value.StartsWith('-')) {
                    Fail "Invalid owner '$value'. Owner must be a single P4 user name and cannot start with '-'."
                }
                $result.Owner = $value
            }
            'client' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    Fail "client filter cannot be empty."
                }
                if ($value -match '\s' -or $value.StartsWith('-')) {
                    Fail "Invalid client '$value'. Client must be a single P4 workspace name and cannot start with '-'."
                }
                $result.Client = $value
            }
            'stream' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    Fail "stream filter cannot be empty."
                }
                if (-not $value.StartsWith('//')) {
                    Fail "Invalid stream '$value'. Stream path must start with '//' (e.g. //depot/main)."
                }
                $result.Stream = $value
            }
            'description' {
                if ([string]::IsNullOrWhiteSpace($value)) {
                    Fail "description filter cannot be empty."
                }
                $result.Description = $value
            }
            'cl' {
                $result.CL = Parse-ChangelistRange -Value $value
            }
        }
    }

    return $result
}

function Format-P4Date {
    param([Parameter(Mandatory = $true)][datetime]$Value)
    return $Value.ToString('yyyy/MM/dd:HH:mm:ss', $script:InvariantCulture)
}

function Format-CommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '^[A-Za-z0-9_./:@=-]+$') {
        return $Value
    }

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Format-CommandForDisplay {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($Command)
    foreach ($argument in $Arguments) {
        $parts.Add((Format-CommandArgument -Value $argument))
    }
    return ($parts -join ' ')
}

function Build-P4Arguments {
    param([Parameter(Mandatory = $true)][hashtable]$ParsedFilters)

    $args = New-Object System.Collections.Generic.List[string]
    $args.Add('-z')
    $args.Add('tag')
    $args.Add('changes')
    $args.Add('-s')
    $args.Add('submitted')
    $args.Add('-t')
    $args.Add('-l')

    if ($ParsedFilters.Client) {
        $args.Add('-c')
        $args.Add([string]$ParsedFilters.Client)
    }

    if ($ParsedFilters.Stream) {
        $args.Add('-S')
        $args.Add([string]$ParsedFilters.Stream)
    }

    if ($ParsedFilters.Owner) {
        $args.Add('-u')
        $args.Add([string]$ParsedFilters.Owner)
    }

    if ($ParsedFilters.CL) {
        $args.Add('-e')
        $args.Add(([string]$ParsedFilters.CL.Min))
    }

    if ($ParsedFilters.Date) {
        $dateSpec = '@' + (Format-P4Date -Value $ParsedFilters.Date.From) + ',@' + (Format-P4Date -Value $ParsedFilters.Date.To)
        $args.Add($dateSpec)
    }

    return [string[]]$args.ToArray()
}

function Get-P4TaggedLine {
    param([AllowEmptyString()][string]$Line)

    if ($Line -notmatch '^\.\.\.\s+(\S+)(?:\s(.*))?$') {
        return $null
    }

    $value = ''
    if ($Matches.Count -gt 2 -and $null -ne $Matches[2]) {
        $value = $Matches[2]
    }

    return @{
        Key = $Matches[1]
        Value = $value
    }
}

function Test-IsP4ChangeRecordStart {
    param(
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][int]$Index
    )

    if ($null -eq $Lines -or $Index -lt 0 -or $Index -ge $Lines.Count) {
        return $false
    }

    $tag = Get-P4TaggedLine -Line $Lines[$Index]
    if ($null -eq $tag -or $tag.Key -ne 'change' -or $tag.Value -notmatch '^\d+$') {
        return $false
    }

    $hasTime = $false
    $hasUser = $false
    $hasClient = $false

    for ($lookAhead = $Index + 1; $lookAhead -lt $Lines.Count; $lookAhead++) {
        $nextTag = Get-P4TaggedLine -Line $Lines[$lookAhead]
        if ($null -eq $nextTag) {
            continue
        }

        if ($nextTag.Key -eq 'desc') {
            break
        }
        if ($nextTag.Key -eq 'change') {
            break
        }
        if ($nextTag.Key -eq 'time') {
            $hasTime = $true
        } elseif ($nextTag.Key -eq 'user') {
            $hasUser = $true
        } elseif ($nextTag.Key -eq 'client') {
            $hasClient = $true
        }
    }

    return ($hasTime -and $hasUser -and $hasClient)
}

function ConvertFrom-P4TaggedChanges {
    param([AllowNull()][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines)

    $records = New-Object System.Collections.Generic.List[hashtable]
    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return $records
    }

    $current = $null
    $lastKey = $null

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $tag = Get-P4TaggedLine -Line $line

        if ($null -ne $tag -and ($lastKey -ne 'desc' -or (Test-IsP4ChangeRecordStart -Lines $Lines -Index $i))) {
            $key = $tag.Key
            $value = $tag.Value

            if ($key -eq 'change') {
                if ($null -ne $current -and $current.ContainsKey('change')) {
                    $records.Add($current)
                }
                $current = @{}
            } elseif ($null -eq $current) {
                $current = @{}
            }

            $current[$key] = $value
            $lastKey = $key
        } elseif ($null -ne $current -and $lastKey -eq 'desc') {
            $current['desc'] = ([string]$current['desc']) + "`n" + $line
        }
    }

    if ($null -ne $current -and $current.ContainsKey('change')) {
        $records.Add($current)
    }

    return $records
}

function Get-P4ServerUtcOffset {
    $infoOutput = & p4 info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not read P4 server timezone from 'p4 info'; displaying tagged epoch timestamps in UTC."
        return $null
    }

    foreach ($line in $infoOutput) {
        if ($line -match '^Server date:\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+(?<offset>[+-]\d{4})\b') {
            $offsetText = $Matches['offset']
            $sign = 1
            if ($offsetText.StartsWith('-')) {
                $sign = -1
            }
            $hours = [int]::Parse($offsetText.Substring(1, 2), $script:InvariantCulture)
            $minutes = [int]::Parse($offsetText.Substring(3, 2), $script:InvariantCulture)
            return (New-TimeSpan -Hours ($sign * $hours) -Minutes ($sign * $minutes))
        }
    }

    Write-Warning "Could not parse P4 server timezone from 'p4 info'; displaying tagged epoch timestamps in UTC."
    return $null
}

function Get-CurrentP4Workspace {
    $infoOutput = & p4 info 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $infoOutput) {
        if ($line -match '^Client name:\s+(\S+)$') {
            return $Matches[1]
        }
    }

    return $null
}

function Format-P4Time {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Record,
        [AllowNull()][object]$ServerUtcOffset
    )

    if ($Record.ContainsKey('time')) {
        $epochText = [string]$Record['time']
        $epoch = 0L
        if ([int64]::TryParse($epochText, [ref]$epoch)) {
            $offset = [DateTimeOffset]::FromUnixTimeSeconds($epoch)
            if ($ServerUtcOffset -is [System.TimeSpan]) {
                return $offset.ToOffset($ServerUtcOffset).ToString('yyyy/MM/dd HH:mm:ss zzz', $script:InvariantCulture)
            }

            return $offset.UtcDateTime.ToString('yyyy/MM/dd HH:mm:ss', $script:InvariantCulture) + ' UTC'
        }
    }

    if ($Record.ContainsKey('date')) {
        $dateText = [string]$Record['date']
        $parsed = [datetime]::MinValue
        $formats = [string[]]@('yyyy/MM/dd HH:mm:ss', 'yyyy/MM/dd HH:mm', 'yyyy/MM/dd')
        if ([datetime]::TryParseExact($dateText, $formats, $script:InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed.ToString('yyyy/MM/dd HH:mm:ss', $script:InvariantCulture)
        }
    }

    return ''
}

function Get-FirstDescriptionLine {
    param([string]$Description)

    if ($null -eq $Description) {
        return ''
    }

    $normalized = $Description -replace "`r", ''
    $firstLine = ($normalized -split "`n", 2)[0].Trim()
    return $firstLine
}

function Test-RecordMatchesClientFilters {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Record,
        [Parameter(Mandatory = $true)][hashtable]$ParsedFilters
    )

    if (-not $Record.ContainsKey('change')) {
        return $false
    }

    $change = 0L
    if (-not [int64]::TryParse([string]$Record['change'], [ref]$change)) {
        return $false
    }

    if ($ParsedFilters.CL -and $change -gt [int64]$ParsedFilters.CL.Max) {
        return $false
    }

    if ($ParsedFilters.Description) {
        $description = ''
        if ($Record.ContainsKey('desc')) {
            $description = [string]$Record['desc']
        }

        if ($description.IndexOf([string]$ParsedFilters.Description, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            return $false
        }
    }

    return $true
}

function Write-Records {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Records,
        [AllowNull()][object]$ServerUtcOffset
    )

    $count = 0
    foreach ($ignored in $Records) {
        $count++
    }

    if ($count -eq 0) {
        Write-Host "No submitted changelists matched the filters."
        return
    }

    Write-Host "Found $count submitted changelist(s)."
    Write-Host "CL | DateTime | Owner@Client | Description"

    foreach ($record in $Records) {
        $change = [string]$record['change']
        $dateText = Format-P4Time -Record $record -ServerUtcOffset $ServerUtcOffset

        $user = ''
        if ($record.ContainsKey('user')) {
            $user = [string]$record['user']
        }
        $client = ''
        if ($record.ContainsKey('client')) {
            $client = [string]$record['client']
        }
        $ownerClient = "$user@$client"
        if ([string]::IsNullOrWhiteSpace($user) -and [string]::IsNullOrWhiteSpace($client)) {
            $ownerClient = ''
        }

        $description = ''
        if ($record.ContainsKey('desc')) {
            $description = Get-FirstDescriptionLine -Description ([string]$record['desc'])
        }

        Write-Host "$change | $dateText | $ownerClient | $description"
    }
}

$commandLine = Parse-CommandLine -RawArguments $Arguments
$parsedFilters = Parse-Filters -Tokens $commandLine.Filters

if ($Workspace -and $P4Stream) {
    Fail "Cannot use both -Workspace and -P4Stream together. Use only one."
}

if ($Workspace) {
    if ($parsedFilters.Client) {
        Fail "Workspace is specified via both -Workspace parameter and client: filter. Use only one."
    }
    $parsedFilters.Client = $Workspace
} elseif ($P4Stream) {
    if ($parsedFilters.Client) {
        Fail "Stream is specified via both -P4Stream parameter and client: filter. Use only one."
    }
    if ($parsedFilters.Stream) {
        Fail "Stream is specified via both -P4Stream parameter and stream: filter. Use only one."
    }
    $parsedFilters.Stream = $P4Stream
} elseif (-not $parsedFilters.Client -and -not $parsedFilters.Stream) {
    $currentWorkspace = Get-CurrentP4Workspace
    if ($currentWorkspace) {
        $parsedFilters.Client = $currentWorkspace
    } else {
        Fail "Could not determine current P4 workspace. Use -Workspace or -P4Stream parameter to specify one."
    }
}

$p4Args = Build-P4Arguments -ParsedFilters $parsedFilters

if ($commandLine.PreviewCommand) {
    Write-Host (Format-CommandForDisplay -Command 'p4' -Arguments $p4Args)
    exit 0
}

if (-not (Get-Command p4 -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("ERROR: 'p4' is not installed or not on PATH.")
    exit 1
}

$serverUtcOffset = Get-P4ServerUtcOffset
$p4Output = & p4 @p4Args 2>&1
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("ERROR: p4 changes failed (exit $LASTEXITCODE):`n$($p4Output -join "`n")")
    exit 1
}

$records = ConvertFrom-P4TaggedChanges -Lines ([string[]]$p4Output)
$matched = New-Object System.Collections.Generic.List[hashtable]
foreach ($record in $records) {
    if (Test-RecordMatchesClientFilters -Record $record -ParsedFilters $parsedFilters) {
        $matched.Add($record)
    }
}

Write-Records -Records $matched -ServerUtcOffset $serverUtcOffset
exit 0
