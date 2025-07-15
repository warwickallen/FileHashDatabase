# FileHashDatabase.psm1

# Import the class using 'using module' for proper class loading
using module .\Private\FileHashDatabase.ps1

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

# Load public functions
. $PSScriptRoot\Public\Get-FileHashes.ps1
. $PSScriptRoot\Public\Move-FileHashDuplicates.ps1
. $PSScriptRoot\Public\Write-FileHashes.ps1
