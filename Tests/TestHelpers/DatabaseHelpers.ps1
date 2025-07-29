function Test-DatabaseConnection {
    param([string]$DatabasePath)

    if (Get-Module -ListAvailable PSSQLite) {
        try {
            Import-Module PSSQLite -Force
            $result = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT 1 as test"
            return $result.test -eq 1
        } catch {
            return $false
        }
    }
    return $false
}

function Get-DatabaseTable {
    param([string]$DatabasePath)

    if (Get-Module -ListAvailable PSSQLite) {
        try {
            Import-Module PSSQLite -Force
            $tables = Invoke-SqliteQuery -DataSource $DatabasePath -Query "SELECT name FROM sqlite_master WHERE type='table'"
            return $tables.name
        } catch {
            Write-Warning "Could not query database tables: $_"
            return @()
        }
    }
    return @()
}

function Clear-TestDatabase {
    param([string]$DatabasePath)

    if (Test-Path $DatabasePath) {
        try {
            Remove-Item $DatabasePath -Force
        } catch {
            Write-Warning "Could not remove test database: $_"
        }
    }
}
