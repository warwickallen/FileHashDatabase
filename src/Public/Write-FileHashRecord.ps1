<#
.SYNOPSIS
    Computes and displays file hashes for files in a specified directory, and logs file hash info to
    SQLite.

.DESCRIPTION
    The Write-FileHashRecord function scans a specified directory and computes file hashes using the
    specified algorithm (default SHA256). It displays a pause indicator with dots and handles
    retries for failed hash computations. The function can pause between files, retry failed
    attempts, and optionally halt on errors. File names are formatted to a specified display length
    for consistent output.

    Each file that has been attempted to be processed is logged to a SQLite database, including
    failed attempts. For failed hash attempts, the hash value is NULL. The database's default
    location is in the user's AppData directory. The logging can be turned off using the NoSqliteLog
    switch.

    The NoReprocess switch causes the function to check the database for each file's path and skip
    processing if the path exists.

    The ReprocessFailed switch causes the function to re-process the files with NULL hash in the log
    database. If ReprocessFailed is selected, ScanDirectory is ignored (a warning is issued if both
    are supplied). ReprocessFailed and NoReprocess may not both be selected.

    The Recurse switch causes the function to scan subdirectories of the ScanDirectory as well.

.PARAMETER ScanDirectory
    The directory to scan for files. Defaults to the current working directory.

.PARAMETER FileFilter
    A glob-style filter. If defined, only files match the filter was be considered.

.PARAMETER InterfilePauseSeconds
    The number of seconds to pause between processing files. Must be a non-negative number. The
    default is 20 seconds.

.PARAMETER RetryAttempts
    The number of retry attempts for computing a file's hash if it fails. Must be a non-negative
    integer. The default is 2.

.PARAMETER RetryDelaySeconds
    The delay in seconds between retry attempts for failed hash computations. Must be a non-negative
    number. The default is 5 seconds.

.PARAMETER HaltOnFailure
    If set to $true, the function stops execution on any error. If $false, it continues processing
    other files. The default is $false.

.PARAMETER FileNameDisplayLength
    The length to which file names are formatted in the output display. Must be between 10 and 260
    characters. The default is 64.

.PARAMETER Algorithm
    The hash algorithm to use for computing file hashes. Must be one of: SHA1, SHA256, SHA384,
    SHA512, MACTripleDES, MD5, RIPEMD160. The default is SHA256.

.PARAMETER DatabasePath
    Path to the SQLite database file to use for logging the hashes. Defaults to
    "$env:APPDATA\FileHashDatabase\FileHashes.db".

.PARAMETER NoSqliteLog
    Do not log file information to the SQLite database.

.PARAMETER NoReprocess
    If set, the function will check whether a file (by its path) has already been attempted and will
    skip it if so.

.PARAMETER ReprocessFailed
    Reprocesses the paths stored in the log database that have null values in the hash field (i.e.,
    the attempt to calculate the file's hash failed). If ReprocessFailed is selected, the
    ScanDirectory path is not scanned (a warning is issued if ReprocessFailed is selected and a
    ScanDirectory path is supplied). ReprocessFailed and NoReprocess may not both be selected.

.PARAMETER RandomOrder
    If set, files will be processed in a random order. The default is to process files in their
    normal order.

.PARAMETER Recurse
    If set, the function will scan the ScanDirectory and all of its subdirectories for files.

.PARAMETER MaxFiles
    The maximum number of files to process (including failed attempts). Must be a non-negative
    integer. Defaults to [int]::MaxValue.

.PARAMETER Help
    Displays this help message and exits.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -ScanDirectory "C:\Data" -InterfilePauseSeconds 10
    Scans the "C:\Data" directory, computing SHA256 file hashes with a 10-second pause between
    files.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -HaltOnFailure $true -RetryAttempts 3 -Algorithm SHA512
    Scans the current directory with SHA512, stopping on any error, with 3 retry attempts for failed
    hash computations.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -NoReprocess
    Scans the current directory, skipping files whose path exists in the database.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -RandomOrder
    Scans the current directory and processes files in a random order.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -Recurse
    Scans the current directory and all subdirectories for files.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -MaxFiles 100
    Scans up to 100 files from the source.

.EXAMPLE
    .\Write-FileHashRecord.ps1 -Help
    Displays the help message for the function.

.NOTES
    Requires the PSSQLite module to be installed and available in the PowerShell session.

    The defaults are set in FileHashDatabase.psm1.
#>

# Load the FileHashDatabase class
if (-not (Get-Command -Name 'FileHashDatabase' -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\..\Private\FileHashDatabase.ps1"
}
# Load the PauseIndicator class
if (-not ([System.Management.Automation.PSTypeName]'PauseIndicator').Type) {
    . "$PSScriptRoot\..\Private\PauseIndicator.ps1"
}

function Write-FileHashRecord {
    [CmdletBinding(DefaultParameterSetName='Normal')]
    param(
        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [string]$ScanDirectory = (Get-Location).ToString(),

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [string]$FileFilter,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [ValidateRange(0, [float]::MaxValue)]
        [float]$InterfilePauseSeconds = $script:Config.Defaults.InterfilePauseSeconds,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RetryAttempts = $script:Config.Defaults.RetryAttempts,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [ValidateRange(0, [float]::MaxValue)]
        [float]$RetryDelaySeconds = $script:Config.Defaults.RetryDelaySeconds,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [bool]$HaltOnFailure = $false,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [ValidateRange(10, 260)]
        [int]$FileNameDisplayLength = $script:Config.Defaults.FileNameDisplayLength,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        # The developer must ensure the ValidationSet matches $script:Config.SupportedAlgorithms
        [ValidateSet('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MACTripleDES', 'MD5', 'RIPEMD160')]
        [string]$Algorithm = $script:Config.Defaults.Algorithm,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [string]$DatabasePath = $script:Config.Defaults.DatabasePath,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [switch]$NoSqliteLog,

        [Parameter(ParameterSetName='Normal')]
        [switch]$NoReprocess,

        [Parameter(ParameterSetName='Reprocess')]
        [switch]$ReprocessFailed,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [switch]$RandomOrder,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [switch]$Recurse,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxFiles = $script:Config.Defaults.MaxFiles,

        [Parameter(ParameterSetName='Normal')]
        [Parameter(ParameterSetName='Reprocess')]
        [switch]$Help
    )

    if ($Help) {
        Get-Help -Name Write-FileHashRecord
        return
    }

    # Issue a warning if both -ReprocessFailed and -ScanDirectory are supplied
    if (
        $PSCmdlet.ParameterSetName -eq 'Reprocess' -and
        $PSBoundParameters.ContainsKey('ScanDirectory')
    ) {
        $msg = "Both -ReprocessFailed and -ScanDirectory were supplied."
        $msg += " Only -ReprocessFailed will be used."
        Write-Warning $msg
    }

    # Handle database logic via the FileHashDatabase class
    $db = $null
    if (-not $NoSqliteLog -or $NoReprocess -or $ReprocessFailed) {
        try {
            $db = [FileHashDatabase]::new($DatabasePath)
        } catch {
            throw "Failed to initialise database object: $_"
        }
    }

    # Build the file list
    if ($ReprocessFailed) {
        if (-not (Test-Path $DatabasePath -PathType Leaf)) {
            $msg = "-DatabasePath '$DatabasePath' does not exist or is not a file."
            $msg += " Please provide a valid database file."
            throw $msg
        }
        try {
            $failedPaths = $db.GetFailedFilePaths()
            $file_list = @()
            foreach ($path in $failedPaths) {
                if (Test-Path $path) {
                    $file_list += Get-Item $path
                } else {
                    Write-Warning "File not found: $path"
                }
            }
        } catch {
            throw $_
        }
    } else {
        # Normal directory scan
        if (-not (Test-Path $ScanDirectory -PathType Container)) {
            throw "-ScanDirectory does not exist or is not a directory."
        }
        $params = @{
            'File'    = $True
            'Filter'  = $FileFilter
            'Path'    = $ScanDirectory
            'Recurse' = $Recurse
        };
        $file_list = Get-ChildItem @params
    }

    $indicator = [PauseIndicator]::new($InterfilePauseSeconds)
    $error_action = 'Continue'
    if ($HaltOnFailure) {
        $error_action = 'Stop'
    }

    if ($RandomOrder) {
        $file_list = $file_list | Get-Random -Count $file_list.Count
    }

    $processedCount = 0  # Track how many files have been processed

    foreach ($f in $file_list) {
        if ($processedCount -ge $MaxFiles) { break } # Stop if we've reached the limit

        $fname = $f.Name
        $hash = $null
        $indicator.Start($fname)

        # If NoReprocess is set, check if this file's path already exists in the database
        if ($NoReprocess -and $db) {
            if ($db.FileExistsInDatabase($f.FullName)) {
                $indicator.Fail("[Skipped, already processed]")
                continue
            }
        }

        $indicator.Animate()
        $attempts_remaining = 1 + $RetryAttempts
        $this_error = $null
        while ($attempts_remaining-- -and -not $hash.Length) {
            try {
                $h = Get-FileHash -Path $f.FullName -Algorithm $Algorithm -ErrorAction Stop
                $hash = $h.Hash.ToString()
            } catch {
                $this_error = $_
                $n = $RetryAttempts - $attempts_remaining
                $backspaces = ("`b" * (3 * $n))
                Write-Host -NoNewline (('!! ' * $n) + $backspaces)
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
        $indicator.Complete($hash)
        if ($this_error) {
            $msg = 'Cannot read the contents of "{0}"' -f $f.FullName
            Write-Error -Message $msg -ErrorAction $error_action
        }

        # Log to SQLite database if requested
        if (-not $NoSqliteLog -and $db) {
            $db.LogFileHash($hash, $Algorithm, $f.FullName, $f.Length, (Get-Date))
        }

        $processedCount++ # Increment processed file count (success or failure)
    }
}
