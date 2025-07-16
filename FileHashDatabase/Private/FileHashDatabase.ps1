# FileHashDatabase.ps1 - PowerShell 5.1 Fully Compatible Version

# Check if we're in a module context and adjust accordingly
$script:ModuleRoot = if ($PSScriptRoot) { 
    Split-Path $PSScriptRoot -Parent 
} else { 
    $PWD 
}

# Define the class with PowerShell 5.1 compatibility
class FileHashDatabase {
    static [string] $DatabasePath
    
    # Static constructor equivalent - initialize default path
    static FileHashDatabase() {
        # PowerShell 5.1 compatible platform detection
        # $IsWindows doesn't exist in PS 5.1, so we use other methods
        $isWindowsPlatform = $true
        
        # Check if we're on a non-Windows platform
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 6+ has the automatic variables
            if (Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue) {
                $isWindowsPlatform = $IsWindows
            }
        } else {
            # PowerShell 5.1 - assume Windows unless proven otherwise
            # In PS 5.1, we're almost certainly on Windows
            $isWindowsPlatform = $true
        }
        
        if ($isWindowsPlatform -or $env:OS -eq 'Windows_NT' -or -not $env:HOME) {
            # Windows path
            [FileHashDatabase]::DatabasePath = [System.IO.Path]::Combine($env:APPDATA, "FileHashDatabase", "FileHashes.db")
        } else {
            # Unix-like systems (Linux, macOS)
            $homeDir = if ($env:HOME) { $env:HOME } else { "~" }
            $localSharePath = Join-Path $homeDir ".local"
            $shareDir = Join-Path $localSharePath "share"
            $appDir = Join-Path $shareDir "FileHashDatabase"
            [FileHashDatabase]::DatabasePath = Join-Path $appDir "FileHashes.db"
        }
    }

    FileHashDatabase([string]$path) {
        if ($path) {
            # Normalize and validate the provided path
            try {
                $resolvedPath = [System.IO.Path]::GetFullPath($path)
                if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                    throw "The provided database path '$resolvedPath' is not a valid absolute path."
                }
                [FileHashDatabase]::DatabasePath = $resolvedPath
            } catch {
                throw "Invalid database path '$path': $_"
            }
        }
        
        # Ensure the path is always fully resolved
        try {
            [FileHashDatabase]::DatabasePath = [System.IO.Path]::GetFullPath([FileHashDatabase]::DatabasePath)
            Write-Debug "Resolved database path: $([FileHashDatabase]::DatabasePath)"
        } catch {
            throw "Could not resolve database path: $_"
        }
        
        $this.EnsureSchema()
    }

    static [bool] IsModuleAvailable([string]$moduleName) {
        try {
            return [bool](Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue)
        } catch {
            return $false
        }
    }

    [System.Object[]] InvokeQuery([string]$query, [hashtable]$parameters) {
        $dbPath = [FileHashDatabase]::DatabasePath
        Write-Debug "Executing query: $query with parameters: $($parameters | Out-String)"
        
        # Check if PSSQLite is available before attempting to use it
        if (-not [FileHashDatabase]::IsModuleAvailable('PSSQLite')) {
            throw "PSSQLite module is required but not available. Install with: Install-Module PSSQLite"
        }
        
        try {
            # Import PSSQLite if not already loaded
            if (-not (Get-Module -Name PSSQLite)) {
                Import-Module PSSQLite -ErrorAction Stop
            }
            
            return Invoke-SQLiteQuery -DataSource $dbPath -Query $query -SqlParameters $parameters
        } catch {
            throw "Error executing query '$query': $_"
        }
    }

    [void] EnsureSchema() {
        # Ensure the database directory exists
        $dbPath = [FileHashDatabase]::DatabasePath
        Write-Debug "(EnsureSchema) Database path: $dbPath"
        
        try {
            $dbDir = [System.IO.Path]::GetDirectoryName($dbPath)
            if (!(Test-Path $dbDir)) {
                New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
                Write-Debug "Created database directory: $dbDir"
            }
        } catch {
            throw "Cannot create database directory: $_"
        }

        # Ensure PSSQLite module is available
        if (-not [FileHashDatabase]::IsModuleAvailable('PSSQLite')) {
            throw "PSSQLite module is required. Install with: Install-Module PSSQLite"
        }
        
        try {
            Import-Module PSSQLite -ErrorAction Stop
        } catch {
            throw "Failed to import PSSQLite module: $_"
        }

        # Create database schema
        $sqlCreate = @(
            @('Table FileHash', @"
CREATE TABLE IF NOT EXISTS FileHash (
  Hash        TEXT
, AlgorithmId INTEGER
, FilePath    TEXT
, FileSize    INTEGER
, ProcessedAt INTEGER
, PRIMARY KEY (Hash, ProcessedAt)
, FOREIGN KEY (AlgorithmId) REFERENCES Algorithm(AlgorithmId)
);
"@          ),
            @('Table Algorithm', @"
CREATE TABLE IF NOT EXISTS Algorithm (
  AlgorithmId   INTEGER PRIMARY KEY
, AlgorithmName TEXT NOT NULL UNIQUE
);
"@          ),
            @('Table MovedFile', @"
CREATE TABLE IF NOT EXISTS MovedFile (
  Hash            TEXT
, AlgorithmId     INTEGER
, SourcePath      TEXT
, DestinationPath TEXT
, Timestamp       INTEGER
, PRIMARY KEY (SourcePath, Timestamp)
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
WHERE fh.Hash IS NOT NULL
GROUP BY fh.Hash, fh.AlgorithmId;
"@          )
        )
        
        foreach ($sql in $sqlCreate) {
            try {
                Write-Verbose "Executing SQL for $($sql[0])"
                $this.InvokeQuery($sql[1], @{}) | Out-Null
            } catch {
                throw "Failed to create $($sql[0]) in SQLite database: $_"
            }
        }
        
        # Populate supported algorithms
        $supportedAlgorithms = $script:Config.SupportedAlgorithms
        $query = "SELECT AlgorithmName FROM Algorithm"
        $existingAlgorithms = ($this.InvokeQuery($query, @{}) | ForEach-Object {$_.AlgorithmName})
        
        foreach ($supportedAlgorithm in $supportedAlgorithms) {
            if (-not ($existingAlgorithms -contains $supportedAlgorithm)) {
                $query = "INSERT INTO Algorithm (AlgorithmName) VALUES (@algorithm);"
                $this.InvokeQuery($query, @{ algorithm = $supportedAlgorithm }) | Out-Null
            }
        }
    }

    [bool] FileExistsInDatabase([string]$filePath) {
        $query = "SELECT 1 FROM FileHash WHERE FilePath = @filepath LIMIT 1;"
        try {
            $exists = $this.InvokeQuery($query, @{ filepath = $filePath })
            return [bool]$exists
        } catch {
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
        $unixTimestampMs = ([DateTimeOffset]$timestamp).ToUnixTimeMilliseconds()
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
, (SELECT AlgorithmId FROM Algorithm WHERE AlgorithmName = @algorithm)
, @filepath
, @filesize
, @processedat
);
"@
        $parameters = @{
            hash        = if ($hash) { $hash } else { $null }
            algorithm   = $algorithm
            filepath    = $filePath
            filesize    = $fileSize
            processedat = $unixTimestampMs
        }
        try {
            $this.InvokeQuery($insert, $parameters) | Out-Null
        } catch {
            Write-Warning "Failed to log hash info to SQLite database: $_"
        }
    }

    [void] LogMovedFile(
        [string]$hash,
        [string]$algorithm,
        [string]$sourcePath,
        [string]$destinationPath,
        [datetime]$timestamp
    ) {
        $unixTimestampMs = ([DateTimeOffset]$timestamp).ToUnixTimeMilliseconds()
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
, (SELECT AlgorithmId FROM Algorithm WHERE AlgorithmName = @algorithm)
, @sourcepath
, @destinationpath
, @timestamp
);
"@
        $parameters = @{
            hash = if ($hash) { $hash } else { $null }
            algorithm = $algorithm
            sourcepath = $sourcePath
            destinationpath = $destinationPath
            timestamp = $unixTimestampMs
        }
        try {
            $this.InvokeQuery($insert, $parameters) | Out-Null
        } catch {
            Write-Warning "Failed to log moved file to SQLite database: $_"
        }
    }

    [System.Collections.ArrayList] GetFailedFilePaths() {
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
            $rows = $this.InvokeQuery($query, @{})
            foreach ($row in $rows) {
                $result += $row.FilePath
            }
        } catch {
            throw "Failed to retrieve list of failed files from database: $_"
        }
        return $result
    }

    [System.Collections.ArrayList] GetFileHashes([int]$limit, [string[]]$filter) {
        $filterStr = "WHERE 1"
        foreach ($clause in $filter) {
            $filterStr += " AND ($clause)"
        }
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

        try {
            $results = $this.InvokeQuery($query, @{})
            return $results
        } catch {
            throw "Failed to retrieve FileHashes records: $_"
        }
    }
}
