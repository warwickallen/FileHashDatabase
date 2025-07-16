# FileHashDatabase.psm1

$script:Config = @{
    Defaults = @{
        DatabasePath = [System.IO.Path]::Combine($env:APPDATA, "FileHashDatabase", "FileHashes.db")
        Algorithm             = 'SHA256'
        FileNameDisplayLength =              64
        InterfilePauseSeconds =               1
        MaxFiles              = [int]::MaxValue
        OrderBy               = 'FilePaths'
        OrderDirection        = 'Ascending'
        RetryAttempts         =               2
        RetryDelaySeconds     =               5
    }
    SupportedAlgorithms = @(
        'SHA1',
        'SHA256',
        'SHA384',
        'SHA512',
        'MACTripleDES',
        'MD5',
        'RIPEMD160'
    )
}

# Load the class file - this approach works reliably across PowerShell versions
$classPath = Join-Path $PSScriptRoot 'Private' 'FileHashDatabase.ps1'
if (Test-Path $classPath) {
    . $classPath
} else {
    throw "Cannot find required class file: $classPath"
}

# Load public functions
. $PSScriptRoot\Public\Get-FileHashes.ps1
. $PSScriptRoot\Public\Move-FileHashDuplicates.ps1
. $PSScriptRoot\Public\Write-FileHashes.ps1

# Report on the accessibility of the FileHashDatabase class
if (Get-Command -Name 'FileHashDatabase' -ErrorAction SilentlyContinue) {
    Write-Verbose "FileHashDatabase class loaded successfully"
} else {
    Write-Warning "FileHashDatabase class may not be properly loaded"
}
