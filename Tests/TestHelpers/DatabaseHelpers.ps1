function Initialize-TestDatabase {
    param(
        [string]$DatabasePath = ":memory:",
        [string]$Schema = @"
CREATE TABLE IF NOT EXISTS FileHashes (
    Id INTEGER PRIMARY KEY AUTOINCREMENT,
    FilePath TEXT NOT NULL,
    FileName TEXT NOT NULL,
    Hash TEXT NOT NULL,
    Algorithm TEXT NOT NULL DEFAULT 'SHA256',
    FileSize INTEGER,
    LastModified DATETIME,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(FilePath, Algorithm)
);

CREATE INDEX IF NOT EXISTS idx_filehashes_path ON FileHashes(FilePath);
CREATE INDEX IF NOT EXISTS idx_filehashes_hash ON FileHashes(Hash);
"@
    )

    try {
        # Create in-memory database for testing
        if ($DatabasePath -eq ":memory:") {
            $connectionString = "Data Source=:memory:;Version=3;"
        } else {
            $connectionString = "Data Source=$DatabasePath;Version=3;"
        }

        if (Get-Module -ListAvailable PSSQLite) {
            Import-Module PSSQLite -Force

            # Use PSSQLite for database operations
            Invoke-SqliteQuery -DataSource $DatabasePath -Query $Schema
            return $DatabasePath
        } else {
            Write-Warning "PSSQLite not available for database testing"
            return $null
        }
    }
    catch {
        throw "Failed to initialize test database: $_"
    }
}

function New-TestFileHash {
    param(
        [string]$FilePath,
        [string]$Hash,
        [string]$Algorithm = "SHA256",
        [int]$FileSize = 1024
    )

    return [PSCustomObject]@{
        FilePath = $FilePath
        FileName = Split-Path -Leaf $FilePath
        Hash = $Hash
        Algorithm = $Algorithm
        FileSize = $FileSize
        LastModified = Get-Date
        CreatedAt = Get-Date
    }
}

function Clear-TestDatabase {
    param([string]$DatabasePath)

    if (Get-Module -ListAvailable PSSQLite) {
        try {
            Invoke-SqliteQuery -DataSource $DatabasePath -Query "DELETE FROM FileHashes"
        } catch {
            Write-Warning "Could not clear test database: $_"
        }
    }
}

function Test-DatabaseConnection {
    param([string]$DatabasePath)

    if (Get-Module -ListAvailable PSSQLite) {
        try {
            $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT 1 as test"
            return $result.test -eq 1
        } catch {
            return $false
        }
    }
    return $false
}
