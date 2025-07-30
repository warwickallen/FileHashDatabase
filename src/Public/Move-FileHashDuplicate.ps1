<#
.SYNOPSIS
    Moves duplicated files identified by hash values to a staging folder.

.DESCRIPTION
    The Move-FileHashDuplicate function identifies files with identical hash values in the FileHash
    table and moves all but one to a specified staging folder for later deletion. One file per
    unique hash is preserved, selected based on the criterion specified by the PreserveBy parameter.
    The function replicates the original directory structure under the destination, logs moves to
    the MovedFile table, and provides a progress indicator.

.PARAMETER Destination
    The directory where duplicated files are moved. Must be a valid, absolute path.

.PARAMETER DatabasePath
    Path to the SQLite database file. Defaults to "$env:APPDATA\FileHashDatabase\FileHashes.db".

.PARAMETER Algorithm
    The hash algorithm to use for identifying duplicates. Defaults to "SHA256".

.PARAMETER Filter
    Conditions to filter duplicates. Can be:
    - An array of strings applied to the aggregated result (HAVING clause), e.g.,
        @("FileCount > 2").
    - A hashtable with keys:
        - 'individual': Conditions on FileHash table rows (e.g., @("FilePath LIKE 'C:%'")).
        - 'aggregated': Conditions on grouped results (e.g., @("FileCount > 2")).
    Available fields:
    - Individual: Hash, Algorithm (e.g., 'SHA256'), FilePath, FileSize, ProcessedAt
    - Aggregated: Hash, Algorithm, FileCount, MaxFileSize, MinProcessedAt, MaxProcessedAt

.PARAMETER PreserveBy
    Criterion for selecting which file to preserve for each unique hash. Options are:
    - EarliestProcessed: The file first processed by Write-FileHashRecord.
    - LongestName:       The file with the longest file name.
    - LongestPath:       The file with the longest full path.
    - ShortestPath:      The file with the shortest full path.
    Default: LongestName

.PARAMETER OrderBy
    Criterion for determining the order in which to move the files. Options are:
    - FilePaths:      The concatenated list of the duplicate files' full paths.
    - MaxProcessedAt: The time when the last file was processed by Write-FileHashRecord.
    - MinProcessedAt: The time when the first file was processed by Write-FileHashRecord.
    Default: FilePaths

.PARAMETER OrderDirection
    The direction of the ordering. Options are:
    - Ascending  (or "Asc" or "a")
    - Descending (or "Desc" or "d")
    Default: Ascending

.PARAMETER MaxFiles
    Maximum number of files to move. Defaults to the maximum integer value.

.PARAMETER InterfilePauseSeconds
    Number of seconds to pause between moving files, used for the progress indicator.

.PARAMETER Reprocess
    If specified, moves files already recorded as moved in the MovedFile table.

.PARAMETER CopyMode
    Copies the files instead of moving them.

.PARAMETER HaltOnFailure
    Stops execution on any error if $true; otherwise, continues with non-terminating errors.

.PARAMETER Help
    Displays this help message and exits.

.EXAMPLE
    Move-FileHashDuplicate -Destination "C:\Staging" -WhatIf
    Simulates moving duplicated files to "C:\Staging" without making changes.

.EXAMPLE
    $params = @{
        Destination = "D:\Duplicates"
        DatabasePath = "C:\Custom\FileHashes.db"
        Algorithm = "MD5"
    }
    Move-FileHashDuplicate @params
    Moves duplicated files identified by MD5 hashes to "D:\Duplicates" using a custom database.

.EXAMPLE
    $params = @{
        Destination = "E:\Backup"
        Filter = @{
            individual = @("Algorithm = 'SHA256'", "FilePath LIKE 'C:%'")
            aggregated = @("FileCount > 2")
        }
        PreserveBy = "EarliestProcessed"
    }
    Move-FileHashDuplicate @params
    Moves duplicated files, such that:
    - the only files moved have:
        - SHA256 hashes,
        - paths starting with "C:",
        - more than two files per hash,
    - the earliest processed file is preserved,
    - the files are moved to "E:\Backup".

.NOTES
    Requires the PSSQLite module. Defaults are set in FileHashDatabase.psm1.

    All database operations are performed securely via the FileHashDatabase class using
    parameterised queries.
#>

function Convert-FilterToParameter {
    param(
        [string[]]$Filters,
        [string]$Scope
    )
    $parameterizedFilters = @()
    $params = @{}
    $counter = 1
    $supportedAlgorithms = $script:Config.SupportedAlgorithms

    foreach ($filter in $Filters) {
        if ($Scope -eq 'individual') {
            $filter = $filter -replace '\bAlgorithm\b', 'a.AlgorithmName'
        }
        $pattern = '(\w+)\s*(=|<|>|>=|<=|<>|LIKE)\s*(''[^'']*''|\d+|NULL)'
        $match = [regex]::Match($filter, $pattern)
        if ($match.Success) {
            $column = $match.Groups[1].Value
            $operator = $match.Groups[2].Value
            $value = $match.Groups[3].Value
            $placeholder = ":param$counter"
            if ($value -match '^''(.*)''$') {
                $paramValue = $matches[1]
                if ($column -eq 'a.AlgorithmName' -or $column -eq 'Algorithm') {
                    if ($paramValue -notin $supportedAlgorithms) {
                        throw("Invalid algorithm in filter: '$paramValue'. " +
                              "Must be one of: $supportedAlgorithms")
                    }
                }
            } elseif ($value -match '^\d+$') {
                $paramValue = [int]$value
            } elseif ($value -eq 'NULL') {
                $paramValue = $null
            } else {
                throw "Unsupported value type in filter: $value"
            }
            $parameterizedFilter = "$column $operator $placeholder"
            $params[$placeholder] = $paramValue
            $counter++
        } else {
            $parameterizedFilter = $filter
        }
        $parameterizedFilters += $parameterizedFilter
    }
    return $parameterizedFilters, $params
}

function Get-DestinationPath {
    param (
        [string]$SourcePath,
        [string]$DestinationRoot
    )
    $drive = [System.IO.Path]::GetPathRoot($SourcePath).Replace(':', '_').Replace('\', '')
    $relativePath = $SourcePath.Substring([System.IO.Path]::GetPathRoot($SourcePath).Length)
    $destDir = Join-Path $DestinationRoot $drive
    $destPath = Join-Path $destDir $relativePath
    $destDirPath = [System.IO.Path]::GetDirectoryName($destPath)
    if (-not (Test-Path $destDirPath)) {
        New-Item -Path $destDirPath -ItemType Directory -Force | Out-Null
    }
    $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($destPath)
    $extension = [System.IO.Path]::GetExtension($destPath)
    $counter = 1
    while (Test-Path $destPath) {
        $newFileName = "$baseFileName`_$counter$extension"
        $destPath = Join-Path $destDirPath $newFileName
        "Resolved conflict by renaming to '$newFileName'" | Write-Verbose
        $counter++
    }
    return $destPath
}

function Move-FileHashDuplicate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [ValidateNotNullOrEmpty()]
        [string]$DatabasePath = $script:Config.Defaults.DatabasePath,

        # The developer must ensure the ValidationSet matches $script:Config.SupportedAlgorithms
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MACTripleDES', 'MD5', 'RIPEMD160')]
        [string]$Algorithm = $script:Config.Defaults.Algorithm,

        [Parameter(Mandatory=$false)]
        [object]$Filter = @(),

        [ValidateSet('EarliestProcessed', 'LongestPath', 'ShortestPath', 'LongestName')]
        [string]$PreserveBy = 'LongestName',

        [ValidateSet('FilePaths', 'MaxProcessedAt', 'MinProcessedAt')]
        [string]$OrderBy = $script:Config.Defaults.OrderBy,

        [ValidateSet('Ascending', 'Asc', 'a', 'Descending', 'Desc', 'd')]
        [string]$OrderDirection = $script:Config.Defaults.OrderDirection,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxFiles = $script:Config.Defaults.MaxFiles,

        [ValidateRange(0, [float]::MaxValue)]
        [float]$InterfilePauseSeconds = $script:Config.Defaults.InterfilePauseSeconds,

        [switch]$Reprocess,

        [switch]$CopyMode,

        [bool]$HaltOnFailure = $false,

        [switch]$Help
    )

    begin {
        if ($Help) {
            Get-Help -Name Move-FileHashDuplicate
            return
        }

        # Initialise database
        try {
            $db = [FileHashDatabase]::new($DatabasePath)
        } catch {
            throw "Failed to initialise database at '$DatabasePath': $_"
        }

        # Process Filter parameter
        if ($null -eq $Filter) {
            $filters = @{}
        } elseif ($Filter -is [array]) {
            $filters = @{ aggregated = $Filter }
        } elseif ($Filter -is [hashtable]) {
            $filters = $Filter
            $validKeys = 'individual', 'aggregated'
            foreach ($key in $filters.Keys) {
                if ($key -notin $validKeys) {
                    throw("Invalid filter key: $key. " +
                          "Allowed keys are 'individual' and 'aggregated'.")
                }
            }
        } else {
            throw "Filter must be an array or a hashtable."
        }

        $individualFilters = if ($filters.ContainsKey('individual'))
                                  { $filters['individual'] }
                             else { @() }
        $aggregatedFilters = if ($filters.ContainsKey('aggregated'))
                                 { $filters['aggregated'] }
                             else { @() }

        # Convert filters to parameters
        $individualConditions, $individualParams = Convert-FilterToParameter `
                                                       -Filters $individualFilters `
                                                       -Scope 'individual'
        $aggregatedConditions, $aggregatedParams = Convert-FilterToParameter `
                                                       -Filters $aggregatedFilters `
                                                       -Scope 'aggregated'

        # Construct query
        $fileCount = if ($Reprocess) { 'COUNT(DISTINCT fh.FilePath)' } else { 'COUNT(*)' }

        $leftJoinClause = ''
        $leftJoinClause += if (-not $Reprocess) {
            "LEFT JOIN MovedFile mf ON fh.FilePath = mf.SourcePath AND mf.Hash IS NOT NULL"
        }

        $whereClause = "WHERE a.AlgorithmName = @algorithm"
        if ($individualConditions) {
            $whereClause += " AND " + ($individualConditions -join " AND ")
        }

        $havingClause = "HAVING COUNT(*) > 1"
        if ($aggregatedConditions) {
            $havingClause += " AND " + ($aggregatedConditions -join " AND ")
        }

        $orderByClause = "ORDER BY "
        $orderByClause += switch ($OrderBy) {
            'FilePaths' { 'GROUP_CONCAT(fh.FilePath)' }
            'MaxProcessedAt'  { 'MAX(fh.ProcessedAt)' }
            'MinProcessedAt'  { 'MIN(fh.ProcessedAt)' }
        }
        $orderByClause += if ($OrderDirection -match '^(Asc|a)') { ' ASC' } else { ' DESC' }

        $query = @"
SELECT
  fh.Hash
, a.AlgorithmName     AS Algorithm
, $fileCount          AS FileCount
, MAX(fh.FileSize)    AS MaxFileSize
, MIN(fh.ProcessedAt) AS MinProcessedAt
, MAX(fh.ProcessedAt) AS MaxProcessedAt
FROM FileHash fh
JOIN Algorithm a ON fh.AlgorithmId = a.AlgorithmId
$leftJoinClause
$whereClause
GROUP BY fh.Hash, fh.AlgorithmId
$havingClause
$orderByClause
"@

        $queryParams = @{ algorithm = $Algorithm } + $individualParams + $aggregatedParams
        try {
            $groups = $db.InvokeQuery($query, $queryParams)
            if (-not $groups) {
                Write-Verbose "No duplicate files found for algorithm '$Algorithm'."
            }
        } catch {
            throw "Failed to retrieve duplicate groups: $_"
        }

        $processedFiles = 0
        $errorAction = if ($HaltOnFailure) { 'Stop' } else { 'Continue' }
        $ndots = 64
        $dots = '.' * $ndots
        $interdotPauseMs = [math]::Round(1000 * $InterfilePauseSeconds / $ndots, 0)
    }

    process {
        # Validate and resolve Destination
        try {
            $Destination = [System.IO.Path]::GetFullPath($Destination)
            "Resolved destination path: $Destination" | Write-Verbose
            if ((Test-Path $Destination) -and -not (Test-Path $Destination -PathType Container)) {
                throw "The destination path '$Destination' exists but is not a directory."
            }
            if (-not (Test-Path $Destination)) {
                New-Item -Path $Destination -ItemType Directory -Force | Out-Null
                "Created destination directory: $Destination" | Write-Verbose
            }
        } catch {
            throw "Failed to create destination directory '$Destination': $_"
        }

        foreach ($group in $groups) {
            if ($processedFiles -ge $MaxFiles) { break }

            $filesQueryTemplate = @"
SELECT
  fh.FilePath
, fh.ProcessedAt
, fh.FileSize
FROM FileHash fh
JOIN Algorithm a ON fh.AlgorithmId = a.AlgorithmId
$leftJoinClause
$whereClause
AND fh.Hash = @hash
$(if (-not $Reprocess) { " AND mf.SourcePath IS NULL" })
"@
            $fileParams = @{ hash = $group.Hash; algorithm = $Algorithm } + $individualParams
            try {
                $files = $db.InvokeQuery($filesQueryTemplate, $fileParams) | ForEach-Object {
                    [PSCustomObject]@{
                        FilePath    = $_.FilePath
                        ProcessedAt = $_.ProcessedAt
                        PathLength  = $_.FilePath.Length
                        NameLength  = ([System.IO.Path]::GetFileName($_.FilePath)).Length
                    }
                }
            } catch {
                Write-Error "Failed to retrieve files for hash '$($group.Hash)': $_" `
                  -ErrorAction $errorAction
                continue
            }

            if ($files.Count -le 1) { continue }

            $preserveFile = switch ($PreserveBy) {
                'EarliestProcessed' {
                    $files | Sort-Object ProcessedAt | Select-Object -First 1
                }
                'LongestPath'       {
                    $files | Sort-Object PathLength -Descending | Select-Object -First 1
                }
                'ShortestPath'      {
                    $files | Sort-Object PathLength | Select-Object -First 1
                }
                'LongestName'       {
                    $files | Sort-Object NameLength -Descending | Select-Object -First 1
                }
            }
            "Preserving file: $($preserveFile.FilePath)" | Write-Verbose

            $toMove = $files | Where-Object { $_.FilePath -ne $preserveFile.FilePath }

            foreach ($file in $toMove) {
                if ($processedFiles -ge $MaxFiles) { break }
                if (-not (Test-Path $file.FilePath)) {
                    "File not found: $($file.FilePath)" | Write-Warning
                    continue
                }

                $moveOrCopy      = if ($CopyMode) { 'Copy'    } else { 'Move'   }
                $movedOrCopied   = if ($CopyMode) { 'Copied'  } else { 'Moved'  }
                $movingOrCopying = if ($CopyMode) { 'Copying' } else { 'Moving' }

                $destPath = Get-DestinationPath -SourcePath $file.FilePath `
                                                -DestinationRoot $Destination
                "$movingOrCopying '$($file.FilePath)' to '$destPath'" | Write-Verbose

                $fileName = [System.IO.Path]::GetFileName($file.FilePath)
                $displayName = if ($fileName.Length -gt 64) {
                    $fileName.Substring(0, 61) + "..."
                } else {
                    $fileName.PadRight(64)
                }
                $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
                Write-Host -NoNewline "$timestamp $displayName $dots"

                try {
                    if ($PSCmdlet.ShouldProcess($file.FilePath, "$moveOrCopy to $destPath")) {
                        $params = @{
                            Path        = $file.FilePath
                            Destination = $destPath
                            Force       = $true
                            ErrorAction = 'Stop'
                        }
                        if ($CopyMode) {
                            Copy-Item @params
                        } else {
                            Move-Item @params
                        }
                        $db.LogMovedFile($group.Hash, $Algorithm, $file.FilePath, $destPath,
                                         (Get-Date))
                        for ($i = $ndots; $i -gt 0; $i--) {
                            Start-Sleep -Milliseconds $interdotPauseMs
                            Write-Host -NoNewline "`b `b"
                        }
                        Write-Host "[$movedOrCopied to $destPath]"
                    }
                } catch {
                    "Failed to $($moveOrCopy.ToLower()) '$($file.FilePath)' to '$destPath': $_" |
                        Write-Error -ErrorAction $errorAction
                    $db.LogMovedFile($group.Hash, $Algorithm, $file.FilePath, $null, (Get-Date))
                    for ($i = $ndots; $i -gt 0; $i--) { Write-Host -NoNewline "`b `b" }
                    Write-Host "[Failed]"
                }
                $processedFiles++
            }
        }
    }
}
