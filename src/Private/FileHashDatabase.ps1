# FileHashDatabase.ps1 - Cross-Platform PowerShell 5.1+ Compatible Version

# Check if we're in a module context and adjust accordingly
$script:ModuleRoot = if ($PSScriptRoot) {
    Split-Path $PSScriptRoot -Parent
} else {
    $PWD
}

# Cross-platform default database path detection - OUTSIDE the class to avoid scoping issues
function Get-DefaultDatabasePath {
    # PowerShell 5.1 compatible platform detection
    $isWindowsPlatform = $true

    # Check PowerShell version and platform
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell 6+ has automatic platform variables
        if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) {
            $isWindowsPlatform = $IsWindows
        } elseif (Get-Variable -Name 'IsLinux' -ErrorAction SilentlyContinue -ValueOnly) {
            $isWindowsPlatform = $false
        } elseif (Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue -ValueOnly) {
            $isWindowsPlatform = $false
        }
    } else {
        # PowerShell 5.1 - use environment variable detection
        if ($env:HOME -and -not $env:APPDATA) {
            # Likely Unix-like system (though PS 5.1 is usually Windows-only)
            $isWindowsPlatform = $false
        } elseif ($env:OS -eq 'Windows_NT') {
            $isWindowsPlatform = $true
        }
        # Default to Windows for PS 5.1 since it's typically Windows-only
    }

    if ($isWindowsPlatform) {
        # Windows path
        return [System.IO.Path]::Combine($env:APPDATA, "FileHashDatabase", "FileHashes.db")
    } else {
        # Unix-like systems (Linux, macOS)
        $homeDir = if ($env:HOME) { $env:HOME } else { "~" }
        $localPath = [System.IO.Path]::Combine($homeDir, ".local")
        $sharePath = [System.IO.Path]::Combine($localPath, "share")
        $appPath = [System.IO.Path]::Combine($sharePath, "FileHashDatabase")
        return [System.IO.Path]::Combine($appPath, "FileHashes.db")
    }
}

# Get the default path outside the class
$script:DefaultDatabasePath = Get-DefaultDatabasePath

# Define the class with the computed default path
class FileHashDatabase {
    # Instance properties instead of static properties to avoid syntax issues
    [string[]] $SupportedAlgorithms
    [string] $DatabasePath

    # Constructor - initialize with defaults and config
    FileHashDatabase([string]$path) {
        # Initialize supported algorithms
        $this.SupportedAlgorithms = @('SHA1', 'SHA256', 'SHA384', 'SHA512', 'MACTripleDES', 'MD5', 'RIPEMD160')

        # Try to get algorithms from config if available
        try {
            if ($script:Config -and $script:Config.SupportedAlgorithms) {
                $this.SupportedAlgorithms = $script:Config.SupportedAlgorithms
            }
        } catch {
            Write-Debug "Config not available, using default algorithms: $($this.SupportedAlgorithms -join ', ')"
        }

        # Set database path
        if ($path) {
            # Normalize and validate the provided path
            try {
                $resolvedPath = [System.IO.Path]::GetFullPath($path)
                if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                    throw "The provided database path '$resolvedPath' is not a valid absolute path."
                }
                $this.DatabasePath = $resolvedPath
            } catch {
                throw "Invalid database path '$path': $_"
            }
        } else {
            # Use default path
            try {
                $this.DatabasePath = $script:DefaultDatabasePath
            } catch {
                # If DefaultDatabasePath is not available, use a fallback
                $this.DatabasePath = [System.IO.Path]::Combine($env:APPDATA, "FileHashDatabase", "FileHashes.db")
            }
        }

        # Ensure the path is always fully resolved
        try {
            $this.DatabasePath = [System.IO.Path]::GetFullPath($this.DatabasePath)
            Write-Debug "Resolved database path: $($this.DatabasePath)"
        } catch {
            throw "Could not resolve database path: $_"
        }

        Write-Debug "FileHashDatabase constructor called with path: $($this.DatabasePath)"
        Write-Debug "Database file exists before EnsureSchema: $(Test-Path $this.DatabasePath)"
        $this.EnsureSchema()
        Write-Debug "Database file exists after EnsureSchema: $(Test-Path $this.DatabasePath)"
        if (Test-Path $this.DatabasePath) {
            Write-Debug "Database file size: $((Get-Item $this.DatabasePath).Length) bytes"
        }
    }



    static [bool] IsModuleAvailable([string]$moduleName) {
        try {
            return [bool](Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
        } catch {
            return $false
        }
    }

    [array] InvokeQuery([string]$query, [hashtable]$parameters) {
        $dbPath = $this.DatabasePath
        Write-Debug "InvokeQuery called with database path: $dbPath"
        Write-Debug "Database file exists: $(Test-Path $dbPath)"
        Write-Debug "Query: $query"
        Write-Debug "Parameters: $($parameters | ConvertTo-Json -Depth 3)"

        try {
            # Validate database path
            if ([string]::IsNullOrWhiteSpace($dbPath)) {
                throw "Database path is null or empty"
            }

            # Check if database file exists (for existing databases)
            if ((Test-Path $dbPath) -and (Get-Item $dbPath).Length -eq 0) {
                throw "Database file exists but is empty: $dbPath"
            }

            # Validate query
            if ([string]::IsNullOrWhiteSpace($query)) {
                throw "Query is null or empty"
            }

            # Validate parameters (if provided)
            if ($parameters -and $parameters.Count -gt 0) {
                foreach ($key in $parameters.Keys) {
                    if ([string]::IsNullOrWhiteSpace($key)) {
                        throw "Parameter key is null or empty"
                    }
                    if ($parameters[$key] -eq $null) {
                        Write-Warning "Parameter '$key' has null value"
                    }
                }
            }

            Write-Debug "Executing Invoke-SQLiteQuery with DataSource: $dbPath"
            $result = Invoke-SQLiteQuery -DataSource $dbPath -Query $query -SqlParameters $parameters
            Write-Debug "Query executed successfully, result count: $($result.Count)"

            # Ensure we always return an array, even for single results
            if ($result -eq $null) {
                return @()
            } elseif ($result -is [array]) {
                return $result
            } else {
                # Convert single object to array
                return @($result)
            }
        } catch {
            $errorDetails = @{
                Query = $query
                Parameters = $parameters
                DatabasePath = $dbPath
                DatabaseExists = Test-Path $dbPath
                DatabaseSize = if (Test-Path $dbPath) { (Get-Item $dbPath).Length } else { 0 }
                ErrorMessage = $_.Exception.Message
                ErrorType = $_.Exception.GetType().Name
                InnerException = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $null }
            }

            Write-Debug "Query execution failed with details: $($errorDetails | ConvertTo-Json -Depth 3)"

            # Provide specific error messages based on error type
            $specificError = switch -Wildcard ($_.Exception.Message) {
                "*Insufficient parameters*" {
                    "Parameter binding error: The query expects parameters that were not provided. Query: $query, Provided parameters: $($parameters.Keys -join ', ')"
                }
                "*unknown error*" {
                    "SQLite unknown error: This may indicate a database corruption, permission issue, or SQL syntax error. Query: $query"
                }
                "*SQL logic error*" {
                    "SQL logic error: The query contains invalid SQL syntax or references non-existent objects. Query: $query"
                }
                "*missing database*" {
                    "Database file missing or inaccessible: $dbPath"
                }
                "*database is locked*" {
                    "Database is locked by another process. Close any other applications using the database: $dbPath"
                }
                "*disk full*" {
                    "Disk full error: Insufficient disk space to complete the database operation"
                }
                "*permission denied*" {
                    "Permission denied: Cannot access database file. Check file permissions: $dbPath"
                }
                default {
                    "Database operation failed: $($_.Exception.Message). Query: $query"
                }
            }

            throw $specificError
        }
    }

    [void] EnsureSchema() {
        # Ensure the database directory exists
        $dbPath = $this.DatabasePath
        Write-Debug "EnsureSchema called with database path: $dbPath"
        Write-Debug "(EnsureSchema) Database path: $dbPath"

        try {
            # Validate database path
            if ([string]::IsNullOrWhiteSpace($dbPath)) {
                throw "Database path is null or empty"
            }

            $dbDir = [System.IO.Path]::GetDirectoryName($dbPath)
            Write-Debug "Database directory: $dbDir"
            Write-Debug "Database directory exists: $(Test-Path $dbDir)"

            if ([string]::IsNullOrWhiteSpace($dbDir)) {
                throw "Cannot determine database directory from path: $dbPath"
            }

            # Resolve the directory path to handle CI environment path issues
            try {
                $resolvedDbDir = (Resolve-Path -Path $dbDir -ErrorAction Stop).Path
                Write-Debug "Resolved database directory: $resolvedDbDir"
                $dbDir = $resolvedDbDir
            } catch {
                Write-Debug "Could not resolve database directory path, using original: $dbDir"
            }

            if (!(Test-Path $dbDir)) {
                Write-Debug "Creating database directory: $dbDir"
                try {
                    New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
                    Write-Debug "Created database directory: $dbDir"
                } catch {
                    throw "Cannot create database directory '$dbDir': $($_.Exception.Message)"
                }
            }

            # Check directory permissions with more robust error handling
            try {
                $testFile = Join-Path $dbDir "test_permissions.tmp"
                New-Item -Path $testFile -ItemType File -Force | Out-Null
                Remove-Item -Path $testFile -Force
                Write-Debug "Successfully tested write permissions in: $dbDir"
            } catch {
                $errorMsg = $_.Exception.Message
                Write-Debug "Failed to write test file to directory: $errorMsg"
                throw "Cannot write to database directory. Check permissions: $errorMsg"
            }
        } catch {
            Write-Debug "Failed to prepare database directory: $_"
            throw "Database directory preparation failed: $_"
        }

        # Ensure PSSQLite module is available
        Write-Debug "Checking PSSQLite module availability"
        if (-not [FileHashDatabase]::IsModuleAvailable('PSSQLite')) {
            Write-Debug "PSSQLite module not available"
            throw "PSSQLite module is required but not available. Install with: Install-Module PSSQLite -Force"
        }

        try {
            Write-Debug "Importing PSSQLite module"
            Import-Module PSSQLite -ErrorAction Stop
            Write-Debug "PSSQLite module imported successfully"
        } catch {
            Write-Debug "Failed to import PSSQLite module: $_"
            throw "Failed to import PSSQLite module. Error: $($_.Exception.Message). Try reinstalling with: Install-Module PSSQLite -Force"
        }

        # Create Algorithm table first
        Write-Debug "Creating Algorithm table"
        $sqlAlgorithmTable = @"
CREATE TABLE IF NOT EXISTS Algorithm (
  AlgorithmId   INTEGER PRIMARY KEY
, AlgorithmName TEXT NOT NULL UNIQUE
);
"@
        try {
            Write-Debug "Executing Algorithm table creation SQL"
            $this.InvokeQuery($sqlAlgorithmTable, @{}) | Out-Null
            Write-Debug "Algorithm table created successfully"
        } catch {
            Write-Debug "Failed to create Algorithm table: $_"
            throw "Failed to create Algorithm table in database '$dbPath': $_"
        }

        # Now create the rest of the schema (tables, indexes, view)
        $sqlCreate = @(
            @('Table FileHash', @"
CREATE TABLE IF NOT EXISTS FileHash (
  FileHashId    INTEGER PRIMARY KEY AUTOINCREMENT
, Hash          TEXT
, AlgorithmId   INTEGER
, FilePath      TEXT NOT NULL
, FileSize      INTEGER
, ProcessedAt   INTEGER
, FOREIGN KEY (AlgorithmId) REFERENCES Algorithm(AlgorithmId)
);
"@          ),
            @('Table MovedFile', @"
CREATE TABLE IF NOT EXISTS MovedFile (
  MovedFileId     INTEGER PRIMARY KEY AUTOINCREMENT
, Hash            TEXT
, AlgorithmId     INTEGER
, SourcePath      TEXT NOT NULL
, DestinationPath TEXT
, Timestamp       INTEGER
, FOREIGN KEY (AlgorithmId) REFERENCES Algorithm(AlgorithmId)
);
"@          ),
            @('Index FileHash (Hash, AlgorithmId)', @"
CREATE INDEX IF NOT EXISTS idx_filehash_hash_algorithmid ON
FileHash (Hash, AlgorithmId);
"@          ),
            @('Index FileHash (FilePath)', @"
CREATE INDEX IF NOT EXISTS idx_filehash_filepath ON
FileHash (FilePath);
"@          ),
            @('Index FileHash (Hash, AlgorithmId, FilePath)', @"
CREATE INDEX IF NOT EXISTS idx_filehash_hash_algorithmid_filepath ON
FileHash (Hash, AlgorithmId, FilePath);
"@          ),
            @('Index MovedFile (SourcePath)', @"
CREATE INDEX IF NOT EXISTS idx_movedfile_sourcepath ON
MovedFile (SourcePath);
"@          ),
            @('Index MovedFile (Hash, AlgorithmId)', @"
CREATE INDEX IF NOT EXISTS idx_movedfile_hash_algorithmid ON
MovedFile (Hash, AlgorithmId);
"@          ),
            @('View DeduplicatedFile', @"
CREATE VIEW IF NOT EXISTS DeduplicatedFile AS
SELECT
  fh.Hash
, a.AlgorithmName AS Algorithm
, GROUP_CONCAT(fh.FilePath, CHAR(10)) AS FilePaths
, COUNT(DISTINCT fh.FilePath) AS FileCount
, MAX(fh.FileSize) AS MaxFileSize
, MIN(fh.ProcessedAt) AS MinProcessedAt
, MAX(fh.ProcessedAt) AS MaxProcessedAt
, COUNT(*) AS RecordCount
FROM FileHash fh
JOIN Algorithm a ON fh.AlgorithmId = a.AlgorithmId
LEFT JOIN MovedFile mf ON fh.FilePath = mf.SourcePath AND mf.Hash IS NOT NULL
WHERE fh.Hash IS NOT NULL
  AND mf.SourcePath IS NULL
GROUP BY fh.Hash, fh.AlgorithmId
ORDER BY fh.Hash, a.AlgorithmName;
"@          )
        )

        foreach ($sql in $sqlCreate) {
            try {
                Write-Debug "Creating $($sql[0])"
                Write-Verbose "Executing SQL for $($sql[0])"
                $this.InvokeQuery($sql[1], @{}) | Out-Null
                Write-Debug "Successfully created $($sql[0])"
            } catch {
                Write-Debug "Failed to create $($sql[0]): $_"
                throw "Failed to create $($sql[0]) in database '$dbPath': $_"
            }
        }

        # Verify database was created successfully
        try {
            if (Test-Path $dbPath) {
                $dbSize = (Get-Item $dbPath).Length
                Write-Debug "Database file exists after EnsureSchema: $true"
                Write-Debug "Database file size: $dbSize bytes"
                if ($dbSize -eq 0) {
                    throw "Database file was created but is empty"
                }
            } else {
                throw "Database file was not created"
            }
        } catch {
            Write-Debug "Database verification failed: $_"
            throw "Database verification failed after schema creation: $_"
        }
    }

    [void] EnsureAlgorithms() {
        Write-Debug "EnsureAlgorithms called"
        # Use the instance property for supported algorithms
        $algorithms = $this.SupportedAlgorithms
        Write-Debug "Supported algorithms: $($algorithms -join ', ')"
        Write-Debug "(EnsureAlgorithms) Supported algorithms: $($algorithms -join ', ')"

        # Validate algorithms list
        if (-not $algorithms -or $algorithms.Count -eq 0) {
            throw "No supported algorithms defined. This indicates a configuration error."
        }

        try {
            Write-Debug "Querying existing algorithms"
            $selectQuery = "SELECT AlgorithmName FROM Algorithm"
            $existingAlgorithms = ($this.InvokeQuery($selectQuery, @{}) | ForEach-Object {$_.AlgorithmName})
            Write-Debug "Existing algorithms in database: $($existingAlgorithms -join ', ')"
            Write-Debug "(EnsureAlgorithms) Existing algorithms in database: $($existingAlgorithms -join ', ')"
        } catch {
            Write-Debug "Failed to query existing algorithms: $_"
            throw "Failed to query existing algorithms from database: $_"
        }

        foreach ($algorithm in $algorithms) {
            Write-Debug "Processing algorithm: $algorithm"

            # Validate algorithm name
            if ([string]::IsNullOrWhiteSpace($algorithm)) {
                Write-Debug "Skipping null or empty algorithm name"
                continue
            }

            if (-not ($existingAlgorithms -contains $algorithm)) {
                Write-Debug "Inserting algorithm: $algorithm"
                Write-Debug "(EnsureAlgorithms) Inserting algorithm: $algorithm"

                try {
                    $insertQuery = "INSERT INTO Algorithm (AlgorithmName) VALUES (@algorithm);"
                    $this.InvokeQuery($insertQuery, @{ algorithm = $algorithm }) | Out-Null
                    Write-Debug "Successfully inserted algorithm: $algorithm"
                } catch {
                    Write-Debug "Failed to insert algorithm '$algorithm': $_"

                    # Check if it's a duplicate key error (algorithm was inserted by another process)
                    if ($_.Exception.Message -like "*UNIQUE constraint failed*" -or
                        $_.Exception.Message -like "*duplicate key*") {
                        Write-Debug "Algorithm '$algorithm' was already inserted by another process"
                        continue
                    }

                    throw "Failed to insert algorithm '$algorithm' into database: $_"
                }
            } else {
                Write-Debug "Algorithm already exists: $algorithm"
                Write-Debug "(EnsureAlgorithms) Algorithm already exists: $algorithm"
            }
        }

        # Verify algorithms were inserted correctly
        try {
            Write-Debug "Verifying final algorithms"
            $finalAlgorithms = ($this.InvokeQuery("SELECT AlgorithmName FROM Algorithm", @{}) | ForEach-Object {$_.AlgorithmName})
            Write-Debug "Final algorithms in database: $($finalAlgorithms -join ', ')"
            Write-Debug "(EnsureAlgorithms) Final algorithms in database: $($finalAlgorithms -join ', ')"

            # Check if all required algorithms are present
            $missingAlgorithms = $algorithms | Where-Object { $finalAlgorithms -notcontains $_ }
            if ($missingAlgorithms.Count -gt 0) {
                Write-Warning "Missing algorithms: $($missingAlgorithms -join ', ')"
                # Re-enable verification to ensure data integrity
                throw "Failed to insert all required algorithms. Missing: $($missingAlgorithms -join ', ')"
            }
        } catch {
            Write-Debug "Failed to verify algorithms: $_"
            # Re-enable verification to ensure data integrity
            throw "Failed to verify algorithms in database: $_"
        }
    }

    [bool] FileExistsInDatabase([string]$filePath) {
        Write-Debug "FileExistsInDatabase called with filePath: $filePath"

        # Validate input parameter
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            Write-Debug "FilePath is null or empty, returning false"
            return $false
        }

        $query = "SELECT 1 FROM FileHash WHERE FilePath = @filepath LIMIT 1;"
        try {
            Write-Debug "Executing FileExistsInDatabase query for path: $filePath"
            $exists = $this.InvokeQuery($query, @{ filepath = $filePath })
            $result = [bool]$exists
            Write-Debug "FileExistsInDatabase result: $result"
            return $result
        } catch {
            Write-Debug "FileExistsInDatabase query failed: $_"
            Write-Warning "Error checking if file exists in database: $_"
            return $false
        }
    }

    [void] LogFileHash(
        [string]$hash,
        [string]$algorithm,
        [string]$filePath,
        [long]$fileSize,
        [datetime]$timestamp
    ) {
        Write-Debug "LogFileHash called with:"
        Write-Debug "  Hash: $hash"
        Write-Debug "  Algorithm: $algorithm"
        Write-Debug "  FilePath: $filePath"
        Write-Debug "  FileSize: $fileSize"
        Write-Debug "  Timestamp: $timestamp"
        Write-Debug "(LogFileHash) Processing file: $filePath with algorithm: $algorithm"

        # Validate input parameters
        if ([string]::IsNullOrWhiteSpace($filePath)) {
            throw "FilePath cannot be null or empty"
        }

        if ([string]::IsNullOrWhiteSpace($algorithm)) {
            throw "Algorithm cannot be null or empty for file: $filePath"
        }

        if ($fileSize -lt 0) {
            throw "FileSize cannot be negative for file: $filePath"
        }

        if ($timestamp -eq [DateTime]::MinValue) {
            throw "Timestamp cannot be DateTime.MinValue for file: $filePath"
        }

        # Validate file exists (if hash is provided, file should exist)
        if (-not [string]::IsNullOrWhiteSpace($hash) -and -not (Test-Path $filePath)) {
            throw "File does not exist but hash was provided: $filePath"
        }

        $unixTimestampMs = ([DateTimeOffset]$timestamp).ToUnixTimeMilliseconds()

        # Check if file path already exists in database
        Write-Debug "Checking if file path already exists in database"
        try {
            $exists = $this.FileExistsInDatabase($filePath)
            if ($exists) {
                Write-Debug "File path already exists in database: $filePath"
                Write-Debug "File path already exists in database: $filePath"
                return
            }
        } catch {
            Write-Debug "Failed to check if file exists in database: $_"
            throw "Failed to check if file exists in database: $_"
        }

        # Ensure algorithms are populated before getting AlgorithmId
        Write-Debug "Ensuring algorithms are populated"
        try {
            $this.EnsureAlgorithms()
        } catch {
            Write-Debug "Failed to ensure algorithms: $_"
            throw "Failed to ensure algorithms are populated: $_"
        }

        # Get AlgorithmId for the algorithm
        Write-Debug "Getting AlgorithmId for algorithm: $algorithm"
        try {
            $algoIdQuery = "SELECT AlgorithmId FROM Algorithm WHERE AlgorithmName = @algorithm;"
            $algoIdResult = $this.InvokeQuery($algoIdQuery, @{ algorithm = $algorithm })

            # Handle both single object and array results
            if ($algoIdResult -and $algoIdResult.Count -gt 0) {
                $algorithmId = $algoIdResult[0].AlgorithmId
                Write-Debug "Found AlgorithmId: $algorithmId"
            } else {
                throw "Algorithm '$algorithm' not found in Algorithm table. Available algorithms: $($this.SupportedAlgorithms -join ', ')"
            }
        } catch {
            Write-Debug "Failed to get AlgorithmId for algorithm '$algorithm': $_"
            throw "Failed to get AlgorithmId for algorithm '$algorithm': $_"
        }

        # Insert FileHash record
        Write-Debug "Inserting FileHash record with parameters: $(@{
            hash = $hash
            algorithmId = $algorithmId
            filepath = $filePath
            filesize = $fileSize
            processedat = $unixTimestampMs
        } | ConvertTo-Json -Depth 3)"

        try {
            $insert = @"
INSERT INTO FileHash (
  Hash
, AlgorithmId
, FilePath
, FileSize
, ProcessedAt
)
VALUES (
  @hash
, @algorithmId
, @filepath
, @filesize
, @processedat
);
"@
            $parameters = @{
                hash = if ($hash) { $hash } else { $null }
                algorithmId = $algorithmId
                filepath = $filePath
                filesize = $fileSize
                processedat = $unixTimestampMs
            }

            $this.InvokeQuery($insert, $parameters) | Out-Null
            Write-Debug "Successfully inserted FileHash record"
        } catch {
            Write-Debug "Failed to insert FileHash record: $_"

            # Provide specific error messages for common issues
            $specificError = switch -Wildcard ($_.Exception.Message) {
                "*UNIQUE constraint failed*" {
                    "File path already exists in database: $filePath"
                }
                "*FOREIGN KEY constraint failed*" {
                    "Invalid AlgorithmId ($algorithmId) for algorithm '$algorithm'. This may indicate database corruption."
                }
                "*NOT NULL constraint failed*" {
                    "Required field is null. Check that all required parameters are provided."
                }
                default {
                    "Failed to insert FileHash record for file '$filePath': $_"
                }
            }

            throw $specificError
        }
    }

    [void] LogMovedFile(
        [string]$hash,
        [string]$algorithm,
        [string]$sourcePath,
        [string]$destinationPath,
        [datetime]$timestamp
    ) {
        Write-Debug "LogMovedFile called with:"
        Write-Debug "  Hash: $hash"
        Write-Debug "  Algorithm: $algorithm"
        Write-Debug "  SourcePath: $sourcePath"
        Write-Debug "  DestinationPath: $destinationPath"
        Write-Debug "  Timestamp: $timestamp"

        # Validate input parameters
        if ([string]::IsNullOrWhiteSpace($sourcePath)) {
            throw "SourcePath cannot be null or empty"
        }

        if ([string]::IsNullOrWhiteSpace($algorithm)) {
            throw "Algorithm cannot be null or empty for source path: $sourcePath"
        }

        if ($timestamp -eq [DateTime]::MinValue) {
            throw "Timestamp cannot be DateTime.MinValue for source path: $sourcePath"
        }

        # Validate source path exists in database
        try {
            $sourceExists = $this.FileExistsInDatabase($sourcePath)
            if (-not $sourceExists) {
                throw "Source path '$sourcePath' does not exist in FileHash table. Cannot log moved file."
            }
        } catch {
            Write-Debug "Failed to check if source path exists in database: $_"
            throw "Failed to check if source path exists in database: $_"
        }

        $unixTimestampMs = ([DateTimeOffset]$timestamp).ToUnixTimeMilliseconds()

        # Check if this source path already exists in MovedFile table
        Write-Debug "Checking if source path already exists in MovedFile table"
        try {
            $checkQuery = "SELECT 1 FROM MovedFile WHERE SourcePath = @sourcepath LIMIT 1;"
            $exists = $this.InvokeQuery($checkQuery, @{ sourcepath = $sourcePath })

            if ($exists) {
                Write-Debug "Source path already exists in MovedFile table: $sourcePath"
                Write-Debug "Source path already exists in MovedFile table: $sourcePath"
                return
            }
        } catch {
            Write-Debug "Failed to check if source path exists in MovedFile table: $_"
            throw "Failed to check if source path exists in MovedFile table: $_"
        }

        # Ensure algorithms are populated before getting AlgorithmId
        Write-Debug "Ensuring algorithms are populated"
        try {
            $this.EnsureAlgorithms()
        } catch {
            Write-Debug "Failed to ensure algorithms: $_"
            throw "Failed to ensure algorithms are populated: $_"
        }

        # Get AlgorithmId for the algorithm
        Write-Debug "Getting AlgorithmId for algorithm: $algorithm"
        try {
            $algoIdQuery = "SELECT AlgorithmId FROM Algorithm WHERE AlgorithmName = @algorithm;"
            $algoIdResult = $this.InvokeQuery($algoIdQuery, @{ algorithm = $algorithm })

            # Handle both single object and array results
            if ($algoIdResult -and $algoIdResult.Count -gt 0) {
                $algorithmId = $algoIdResult[0].AlgorithmId
                Write-Debug "Found AlgorithmId: $algorithmId"
            } else {
                throw "Algorithm '$algorithm' not found in Algorithm table. Available algorithms: $($this.SupportedAlgorithms -join ', ')"
            }
        } catch {
            Write-Debug "Failed to get AlgorithmId for algorithm '$algorithm': $_"
            throw "Failed to get AlgorithmId for algorithm '$algorithm': $_"
        }

        # Insert into MovedFile table
        Write-Debug "Inserting into MovedFile table"
        try {
            $insert = @"
INSERT INTO MovedFile (
  Hash
, AlgorithmId
, SourcePath
, DestinationPath
, Timestamp
)
VALUES (
  @hash
, @algorithmId
, @sourcepath
, @destinationpath
, @timestamp
);
"@
            $parameters = @{
                hash = if ($hash) { $hash } else { $null }
                algorithmId = $algorithmId
                sourcepath = $sourcePath
                destinationpath = $destinationPath
                timestamp = $unixTimestampMs
            }

            Write-Debug "Executing MovedFile insert with parameters: $($parameters | ConvertTo-Json -Depth 3)"
            $this.InvokeQuery($insert, $parameters) | Out-Null
            Write-Debug "Successfully inserted into MovedFile table"
        } catch {
            Write-Debug "Failed to insert into MovedFile table: $_"

            # Provide specific error messages for common issues
            $specificError = switch -Wildcard ($_.Exception.Message) {
                "*UNIQUE constraint failed*" {
                    "Source path already exists in MovedFile table: $sourcePath"
                }
                "*FOREIGN KEY constraint failed*" {
                    "Invalid AlgorithmId ($algorithmId) for algorithm '$algorithm'. This may indicate database corruption."
                }
                "*NOT NULL constraint failed*" {
                    "Required field is null. Check that all required parameters are provided."
                }
                default {
                    "Failed to insert into MovedFile table for source path '$sourcePath': $_"
                }
            }

            throw $specificError
        }

        # Remove the corresponding record from FileHash table
        Write-Debug "Removing record from FileHash table for moved file"
        try {
            $deleteQuery = "DELETE FROM FileHash WHERE FilePath = @sourcepath;"
            Write-Debug "Executing FileHash delete for path: $sourcePath"
            $this.InvokeQuery($deleteQuery, @{ sourcepath = $sourcePath }) | Out-Null
            Write-Debug "Successfully removed record from FileHash table"
        } catch {
            Write-Debug "Failed to remove record from FileHash table: $_"

            # This is a warning, not a critical error, as the MovedFile record was already inserted
            $specificError = switch -Wildcard ($_.Exception.Message) {
                "*no such table*" {
                    "FileHash table does not exist. This may indicate database corruption."
                }
                default {
                    "Failed to remove FileHash record for moved file '$sourcePath': $_"
                }
            }

            Write-Warning $specificError
        }
    }

    [System.Collections.ArrayList] GetFailedFilePaths() {
        Write-Debug "GetFailedFilePaths called"

        $query = @"
SELECT FilePath
FROM (
SELECT
  sum(Hash IS NOT NULL) Success
, FilePath
FROM FileHash
GROUP BY FilePath
) a
WHERE NOT Success
ORDER BY FilePath;
"@
        $result = @()
        try {
            Write-Debug "Executing GetFailedFilePaths query"
            $rows = $this.InvokeQuery($query, @{})
            Write-Debug "GetFailedFilePaths query returned $($rows.Count) rows"

            foreach ($row in $rows) {
                if ($row.PSObject.Properties.Name -contains 'FilePath') {
                    $result += $row.FilePath
                } else {
                    Write-Warning "Row missing FilePath property: $($row | ConvertTo-Json)"
                }
            }

            Write-Debug "GetFailedFilePaths returning $($result.Count) failed file paths"
            return $result
        } catch {
            Write-Debug "GetFailedFilePaths query failed: $_"
            throw "Failed to retrieve list of failed files from database: $_"
        }
    }

    [System.Collections.ArrayList] GetFileHashes([int]$limit, [string[]]$filter) {
        Write-Debug "GetFileHashes called with limit: $limit, filter: $($filter -join ', ')"

        # Validate input parameters
        if ($limit -lt -1) {
            throw "Limit cannot be less than -1. Provided value: $limit"
        }

        if ($filter -and $filter.Count -gt 0) {
            foreach ($clause in $filter) {
                if ([string]::IsNullOrWhiteSpace($clause)) {
                    throw "Filter clause cannot be null or empty"
                }
            }
        }

        $filterStr = "WHERE 1"
        if ($filter -and $filter.Count -gt 0) {
            foreach ($clause in $filter) {
                $filterStr += " AND ($clause)"
            }
        }
        Write-Debug "Filter string: $filterStr"

        # Build parameters hashtable
        $parameters = @{}
        if ($limit -ne -1) {
            $parameters['limit'] = $limit
        }
        Write-Debug "Parameters: $($parameters | ConvertTo-Json -Depth 3)"

        $query = @"
SELECT
  Hash
, Algorithm
, FilePaths
, FileCount
, MaxFileSize
, MinProcessedAt
, MaxProcessedAt
FROM DeduplicatedFile
$filterStr
$(if ($limit -ne -1) { "LIMIT @limit" });
"@
        Write-Debug "Main query: $query"

        try {
            Write-Debug "Executing main query against DeduplicatedFile view"
            $results = $this.InvokeQuery($query, $parameters)
            Write-Debug "Main query result count: $($results.Count)"
            Write-Debug "Main query results: $($results | ConvertTo-Json -Depth 3)"

            if ($null -eq $results) {
                Write-Debug "Main query returned null, returning empty array"
                return @()
            }

            # Validate results structure
            foreach ($result in $results) {
                if (-not $result.PSObject.Properties.Name -contains 'Hash') {
                    Write-Warning "Result missing Hash property: $($result | ConvertTo-Json)"
                }
                if (-not $result.PSObject.Properties.Name -contains 'Algorithm') {
                    Write-Warning "Result missing Algorithm property: $($result | ConvertTo-Json)"
                }
                if (-not $result.PSObject.Properties.Name -contains 'FilePaths') {
                    Write-Warning "Result missing FilePaths property: $($result | ConvertTo-Json)"
                }
            }

            return $results
        } catch {
            Write-Debug "Main query failed: $_"
            Write-Debug "Failed to retrieve FileHashes records from view: $_"

            # Check if it's a view-related error
            $isViewError = $_.Exception.Message -like "*no such table*" -or
                          $_.Exception.Message -like "*no such view*" -or
                          $_.Exception.Message -like "*DeduplicatedFile*"

            if ($isViewError) {
                Write-Debug "DeduplicatedFile view not available, attempting fallback query"
                # Fallback to direct query if view fails
                try {
                    $fallbackQuery = @"
SELECT
  fh.Hash
, a.AlgorithmName AS Algorithm
, GROUP_CONCAT(fh.FilePath, CHAR(10)) AS FilePaths
, COUNT(DISTINCT fh.FilePath) AS FileCount
, MAX(fh.FileSize) AS MaxFileSize
, MIN(fh.ProcessedAt) AS MinProcessedAt
, MAX(fh.ProcessedAt) AS MaxProcessedAt
FROM FileHash fh
JOIN Algorithm a ON fh.AlgorithmId = a.AlgorithmId
LEFT JOIN MovedFile mf ON fh.FilePath = mf.SourcePath AND mf.Hash IS NOT NULL
WHERE fh.Hash IS NOT NULL
  AND mf.SourcePath IS NULL
GROUP BY fh.Hash, fh.AlgorithmId
ORDER BY fh.Hash, a.AlgorithmName
$filterStr
$(if ($limit -ne -1) { "LIMIT @limit" });
"@
                    Write-Debug "Fallback query: $fallbackQuery"
                    $fallbackResults = $this.InvokeQuery($fallbackQuery, $parameters)
                    Write-Debug "Fallback query result count: $($fallbackResults.Count)"
                    Write-Debug "Fallback query results: $($fallbackResults | ConvertTo-Json -Depth 3)"

                    if ($null -eq $fallbackResults) {
                        Write-Debug "Fallback query returned null, returning empty array"
                        return @()
                    }

                    return $fallbackResults
                } catch {
                    Write-Debug "Fallback query also failed: $_"
                    throw "Failed to retrieve FileHashes records from both view and fallback query. View error: $($_.Exception.Message). Fallback error: $_"
                }
            } else {
                throw "Failed to retrieve FileHashes records from DeduplicatedFile view: $_"
            }
        }
    }
}
