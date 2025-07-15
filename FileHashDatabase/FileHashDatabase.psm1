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

# Load private classes
. $PSScriptRoot\Private\FileHashDatabase.ps1

# Load public functions
. $PSScriptRoot\Public\Get-FileHashes.ps1
. $PSScriptRoot\Public\Move-FileHashDuplicates.ps1
. $PSScriptRoot\Public\Write-FileHashes.ps1
