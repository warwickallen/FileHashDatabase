<#
.SYNOPSIS
    Retrieves file hash records from the SQLite database.

.DESCRIPTION
    The Get-FileHashRecord function returns a list of files according to their hash values from
    information stored in the SQLite database.

    The returned objects have this structure:

        {
            Hash  = { [String]Hash, [String]Algorithm }   # A unique (hash value, algorithm) key
            Paths = ( [String]Path, ... )  # An array of the paths of the files having this hash key
            Count = [Integer]FileCount     # The number of files files having this hash key
            Size  = [Integer]FileSize      # The size of the file(s), in bytes
            FirstProcessed = [DateTime]Timestamp          # The earliest and latest times any of the
            LastProcessed  = [DateTime]Timestamp          # matching files were processed
        }

    By default, the function uses the database path "$env:APPDATA\FileHashDatabase\FileHashes.db".
    You can specify a different database file using the -DatabasePath parameter.

.PARAMETER DatabasePath
    Path to the SQLite database file. Defaults to "$env:APPDATA\FileHashDatabase\FileHashes.db".

.PARAMETER Filter
    A list of strings defining conditions on which to filter the records. These should be in SQL
    syntax and refer to these fields:
        - Hash
        - Algorithm
        - FilePaths       (all the associated paths, delimited by newline characters)
        - MaxFileSize
        - MinProcessedAt  (in milliseconds since 1970-01-01)
        - MaxProcessedAt  (in milliseconds since 1970-01-01)
        - RecordCount     (how often a file with this hash has been processed)
        - FileCount       (the number of files with this hash)

.PARAMETER Limit
    The maximum number of records returned. If not specified, all available records are returned.

.PARAMETER Help
    Displays this help message and exits.

.EXAMPLE
    Get-FileHashRecord
    Returns file hash records from the default database.

.EXAMPLE
    Get-FileHashRecord -DatabasePath "C:\Temp\FileHashes.db"
    Returns file hash records from the specified database file.

.EXAMPLE
    Get-FileHashRecord -Limit 4 -Filter "FileCount > 1", 'FilePaths LIKE "%.jpg%"'
    Returns the first four records that have multiple paths, at least one of which contains the
    characters ".jpg".

.EXAMPLE
    Get-FileHashRecord -Help
    Displays the help message for the function.

.NOTES
    Requires the PSSQLite module to be installed and available in the PowerShell session.

    The Get-FileHashRecord function returns transformed information from the DeduplicatedFile view
    in the SQLite database. The returned objects are transformed as follows:
        - 'Hash' and 'Algorithm' are combined into a nested object labelled 'Hash' with keys:
            'Hash' and 'Algorithm'.
        - 'FilePaths' is split on newline characters and returned as an array labelled 'Paths'.
        - 'MaxFileSize' is relabelled to 'Size'.
        - 'MinProcessedAt' (GMT Unix timestamp) is relabelled to 'FirstProcessed' and converted to a
            PowerShell DateTime object.
        - 'MaxProcessedAt' (GMT Unix timestamp) is relabelled to 'LastProcessed' and converted to a
            PowerShell DateTime object.
        - 'RecordCount' is disregarded.

    The defaults are set in FileHashDatabase.psm1.
#>

function Get-FileHashRecord {
    [CmdletBinding()]
    param(
        [string]$DatabasePath,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Limit = -1,   # -1 means no limit

        [string[]]$Filter = @(),

        [switch]$Help
    )

    if ($Help) {
        Get-Help -Name Get-FileHashRecord
        return
    }

    # Handle database logic via the FileHashDatabase class
    $db = $null
    try {
        # Load the class if not already available
        if (-not ([System.Management.Automation.PSTypeName]'FileHashDatabase').Type) {
            $classPath = Join-Path $PSScriptRoot "..\Private\FileHashDatabase.ps1"
            . $classPath
        }

        $db = [FileHashDatabase]::new($DatabasePath)
    } catch {
        throw "Failed to initialise database object: $_"
    }

    try {
        Write-Debug "Get-FileHashRecord calling db.GetFileHashes with Limit: $Limit, Filter: $($Filter -join ', ')"
        $results = $db.GetFileHashes($Limit, $Filter)
        Write-Debug "GetFileHashes returned $($results.Count) results"
        Write-Debug "Raw results: $($results | ConvertTo-Json -Depth 3)"
    } catch {
        Write-Debug "GetFileHashes failed: $_"
        throw "Failed to retrieve file hash records: $_"
    }
    try {
        Write-Debug "Transforming $($results.Count) result rows"
        # Transform the result rows
        $toDateTime = {
            param($unix_ms)
            ([DateTimeOffset]::FromUnixTimeMilliseconds($unix_ms)).DateTime
        };
        $transformedResults = foreach ($row in $results) {
            Write-Debug "Transforming row: $($row | ConvertTo-Json -Depth 3)"
            $transformed = [PSCustomObject]@{
                Hash = @{
                    Hash      = $row.Hash
                    Algorithm = $row.Algorithm
                }
                Paths          = ($row.FilePaths -split "`n")
                Count          = $row.FileCount
                Size           = $row.MaxFileSize
                FirstProcessed = &$toDateTime $row.MinProcessedAt
                LastProcessed  = &$toDateTime $row.MaxProcessedAt
            }
            Write-Debug "Transformed to: $($transformed | ConvertTo-Json -Depth 3)"
            $transformed
        }
        Write-Debug "Returning $($transformedResults.Count) transformed results"

        # Add debugging for duplicate detection
        Write-Debug "Analyzing results for duplicate detection"
        $duplicateGroups = $transformedResults | Where-Object { $_.Count -gt 1 }
        Write-Debug "Found $($duplicateGroups.Count) groups with duplicates"
        foreach ($group in $duplicateGroups) {
            Write-Debug "Duplicate group - Hash: $($group.Hash.Hash), Algorithm: $($group.Hash.Algorithm), Count: $($group.Count), Paths: $($group.Paths -join ', ')"
        }

        return $transformedResults
    } catch {
        throw "Failed to transform file hash records: $_"
    }
}
