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

# Use using module for reliable class loading across all PowerShell platforms
# This approach works better than dot-sourcing for classes
$classModulePath = Join-Path $PSScriptRoot 'Private' 'FileHashDatabase.ps1'

if (Test-Path $classModulePath) {
    # For PowerShell 5.1 and later - use using module with dynamic path
    # We need to handle this carefully for cross-platform compatibility
    try {
        # Method 1: Try using module (PowerShell 5.1+)
        Import-Module $classModulePath -Global -Force -Verbose:$false
        Write-Verbose "FileHashDatabase class loaded via Import-Module"
    } catch {
        try {
            # Method 2: Fallback to dot-sourcing with explicit class declaration
            . $classModulePath
            
            # Verify the class is available
            if (-not ([System.Management.Automation.PSTypeName]'FileHashDatabase').Type) {
                throw "FileHashDatabase class not properly loaded"
            }
            Write-Verbose "FileHashDatabase class loaded via dot-sourcing"
        } catch {
            # Method 3: Last resort - load with Add-Type if the class is defined as a string
            Write-Warning "Standard class loading failed: $($_.Exception.Message)"
            throw "Cannot load FileHashDatabase class: $_"
        }
    }
} else {
    throw "Cannot find required class file: $classModulePath"
}

# Load public functions with error handling
$publicFunctionPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $publicFunctionPath) {
    Get-ChildItem -Path $publicFunctionPath -Filter "*.ps1" | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded function: $($_.BaseName)"
        } catch {
            Write-Error "Failed to load function $($_.Name): $_"
            throw
        }
    }
} else {
    throw "Cannot find Public functions directory: $publicFunctionPath"
}

# Verify the FileHashDatabase class is accessible
try {
    $testInstance = [FileHashDatabase]::new($null)
    $testInstance = $null  # Clean up
    Write-Verbose "FileHashDatabase class verified successfully"
    
    # Export the class type for external use
    Export-ModuleMember -Variable Config
} catch {
    Write-Warning "FileHashDatabase class verification failed: $_"
    Write-Warning "Some functionality may not be available"
}

# Export functions (this should match your manifest)
Export-ModuleMember -Function @(
    'Get-FileHashes',
    'Move-FileHashDuplicates', 
    'Write-FileHashes'
)
