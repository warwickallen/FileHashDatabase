class FileHashDatabase {
    static [string] $DatabasePath = $script:Config.Defaults.DatabasePath

    FileHashDatabase([string]$path) {
        if ($path) {
            # Normalise and validate the provided path
            $resolvedPath = [System.IO.Path]::GetFullPath($path)
            if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
                throw "The provided database path '$resolvedPath' is not a valid absolute path."
            }
            [FileHashDatabase]::DatabasePath = $resolvedPath
        }
        # Ensure the path is always fully resolved
        [FileHashDatabase]::DatabasePath = [System.IO.Path]::GetFullPath(
            [FileHashDatabase]::DatabasePath
        )
        "Resolved database path: {0}" -f [FileHashDatabase]::DatabasePath | Write-Debug
        $this.EnsureSchema()
    }

    static [bool] IsModuleAvailable([string]$moduleName) {
        return [bool](Get-Module -ListAvailable -Name $moduleName)
    }

    [System.Object[]] InvokeQuery([string]$query, [hashtable]$parameters) {
        $dbPath = [FileHashDatabase]::DatabasePath
        "Executing query: $query with parameters: $($parameters | Out-String)" | Write-Debug
        try {
            return Invoke-SQLiteQuery -DataSource $dbPath -Query $query -SqlParameters $parameters
        } catch {
            throw "Error executing query '$query': $_"
        }
    }

    [void] EnsureSchema() {
        # Ensure the database directory exists
        $dbPath = [FileHashDatabase]::DatabasePath
        Write-Debug "(EnsureSchema) Database path: $dbPath"
        $dbDir = [System.IO.Path]::GetDirectoryName($dbPath)
        if (!(Test-Path $dbDir)) {
            try {
                New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
            } catch {
                throw "Cannot create database directory '$dbDir': $_"
            }
        }

        # Ensure PSSQLite module is available
        if (-not [FileHashDatabase]::IsModuleAvailable('PSSQLite')) {
            throw "PSSQLite module is required. Install with: Install-Module PSSQLite"
        }
        Import-Module PSSQLite

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
                "Executing SQL for {0}" -f $sql[0] | Write-Verbose
                $this.InvokeQuery($sql[1], @{}) | Out-Null
            } catch {
                throw "Failed to create $($sql[0]) in SQLite database with disparity: $_"
            }
        }
        $query = "SELECT AlgorithmName FROM Algorithm"
        $existingAlgorithms = ($this.InvokeQuery($query, @{}) | ForEach-Object {$_.AlgorithmName})
        foreach ($supportedAlgorithm in $script:Config.SupportedAlgorithms) {
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
