# FileHashDatabase.psm1

$script:Config = @{
    Defaults = @{
        DatabasePath = [System.IO.Path]::Combine($env:APPDATA, "FileHashDatabase", "FileHashes.db")
        Algorithm             = 'SHA256'
        FileNameDisplayLength =              64
        InterfilePauseSeconds =               0
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

# Robust way to determine the module root directory
# This handles cases where $PSScriptRoot might be empty in PowerShell 5.1
function Get-ModuleRoot {
    # Method 1: Try $PSScriptRoot (works in most cases)
    if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
        return $PSScriptRoot
    }

    # Method 2: Try $MyInvocation.MyCommand.Path (fallback for PS 5.1)
    if ($MyInvocation.MyCommand.Path) {
        return Split-Path $MyInvocation.MyCommand.Path -Parent
    }

    # Method 3: Use the module's path from Get-Module (if already loaded)
    $thisModule = Get-Module -Name FileHashDatabase
    if ($thisModule -and $thisModule.Path) {
        return Split-Path $thisModule.Path -Parent
    }

    # Method 4: Try to find the module manifest in the call stack
    $callStack = Get-PSCallStack
    foreach ($frame in $callStack) {
        if ($frame.ScriptName -and $frame.ScriptName -like "*FileHashDatabase.psm1") {
            return Split-Path $frame.ScriptName -Parent
        }
    }

    # Method 5: Last resort - look for the manifest file relative to current location
    $possiblePaths = @(
        ".",
        "..",
        ".\FileHashDatabase",
        "..\FileHashDatabase"
    )

    foreach ($path in $possiblePaths) {
        $manifestPath = Join-Path $path "FileHashDatabase.psd1"
        if (Test-Path $manifestPath) {
            return (Resolve-Path $path).Path
        }
    }

    # If all else fails, throw an informative error
    throw @"
Cannot determine module root directory. Tried the following methods:
1. PSScriptRoot: '$PSScriptRoot'
2. MyInvocation.MyCommand.Path: '$($MyInvocation.MyCommand.Path)'
3. Get-Module path lookup
4. Call stack analysis
5. Relative path search

Please ensure the module is properly structured and try importing with an absolute path.
"@
}

# Get the module root using our robust function
try {
    $script:ModuleRoot = Get-ModuleRoot
    Write-Verbose "Module root determined as: $script:ModuleRoot"
} catch {
    Write-Error "Failed to determine module root: $_"
    throw
}

# Load the FileHashDatabase class with multiple fallback strategies
# Use Join-Path twice for PS 5.1 compatibility
$privatePath = Join-Path $script:ModuleRoot 'Private'
$classModulePath = Join-Path $privatePath 'FileHashDatabase.ps1'

if (Test-Path $classModulePath) {
    Write-Verbose "Loading FileHashDatabase class from: $classModulePath"

    try {
        # Method 1: Try dot-sourcing (most reliable for classes)
        . $classModulePath

        # Verify the class is available by trying to get its type
        $classType = [FileHashDatabase] -as [type]
        if (-not $classType) {
            throw "FileHashDatabase class not found after dot-sourcing"
        }

        Write-Verbose "FileHashDatabase class loaded via dot-sourcing"
        $classLoaded = $true
    } catch {
        Write-Verbose "Dot-sourcing failed: $($_.Exception.Message)"
        $classLoaded = $false
    }

    if (-not $classLoaded) {
        try {
            # Method 2: Try Import-Module (PowerShell 5.1+)
            Import-Module $classModulePath -Global -Force -Verbose:$false -ErrorAction Stop
            Write-Verbose "FileHashDatabase class loaded via Import-Module"
            $classLoaded = $true
        } catch {
            Write-Verbose "Import-Module failed: $($_.Exception.Message)"
            $classLoaded = $false
        }
    }

    if (-not $classLoaded) {
        # Method 3: Try using Add-Type with the file content (last resort)
        try {
            Write-Warning "Standard class loading methods failed. Attempting alternative loading..."
            $classContent = Get-Content $classModulePath -Raw

            # Remove any using statements that might cause issues
            $classContent = $classContent -replace 'using\s+.*', ''

            # This is a more complex fallback - you might need to adjust based on your class definition
            # Use dot-sourcing with a temporary file instead of Invoke-Expression for security
            $tempFile = [System.IO.Path]::GetTempFileName() + '.ps1'
            try {
                Set-Content -Path $tempFile -Value $classContent -Encoding UTF8
                . $tempFile

                # Verify the class is available
                $classType = [FileHashDatabase] -as [type]
                if ($classType) {
                    Write-Verbose "FileHashDatabase class loaded via temporary file"
                    $classLoaded = $true
                }
            }
            finally {
                # Clean up temporary file
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Verbose "Alternative loading failed: $($_.Exception.Message)"
            $classLoaded = $false
        }
    }

    if (-not $classLoaded) {
        Write-Warning @"
Failed to load FileHashDatabase class using all available methods:
1. Import-Module
2. Dot-sourcing
3. Invoke-Expression

Some functionality may not be available. The module will still load public functions.
Class file location: $classModulePath
"@
    }
} else {
    Write-Warning "Cannot find required class file: $classModulePath"
}

# Load the PauseIndicator class
$pauseIndicatorPath = Join-Path $privatePath 'PauseIndicator.ps1'

if (Test-Path $pauseIndicatorPath) {
    Write-Verbose "Loading PauseIndicator class from: $pauseIndicatorPath"

    try {
        # Method 1: Try dot-sourcing (most reliable for classes)
        . $pauseIndicatorPath

        # Verify the class is available by trying to get its type
        $classType = [PauseIndicator] -as [type]
        if (-not $classType) {
            throw "PauseIndicator class not found after dot-sourcing"
        }

        Write-Verbose "PauseIndicator class loaded via dot-sourcing"
        $pauseIndicatorLoaded = $true
    } catch {
        Write-Verbose "Dot-sourcing failed: $($_.Exception.Message)"
        $pauseIndicatorLoaded = $false
    }

    if (-not $pauseIndicatorLoaded) {
        try {
            # Method 2: Try Import-Module (PowerShell 5.1+)
            Import-Module $pauseIndicatorPath -Global -Force -Verbose:$false -ErrorAction Stop
            Write-Verbose "PauseIndicator class loaded via Import-Module"
            $pauseIndicatorLoaded = $true
        } catch {
            Write-Verbose "Import-Module failed: $($_.Exception.Message)"
            $pauseIndicatorLoaded = $false
        }
    }

    if (-not $pauseIndicatorLoaded) {
        Write-Warning "Failed to load PauseIndicator class. Pause indicators may not work correctly."
    }
} else {
    Write-Warning "Cannot find PauseIndicator class file: $pauseIndicatorPath"
}

# Load public functions with robust error handling
$publicFunctionPath = Join-Path $script:ModuleRoot 'Public'

if (Test-Path $publicFunctionPath) {
    Write-Verbose "Loading public functions from: $publicFunctionPath"

    $loadedFunctions = @()
    $failedFunctions = @()

    Get-ChildItem -Path $publicFunctionPath -Filter "*.ps1" | ForEach-Object {
        try {
            Write-Verbose "Loading function: $($_.Name)"
            . $_.FullName
            $loadedFunctions += $_.BaseName
        } catch {
            Write-Warning "Failed to load function $($_.Name): $_"
            $failedFunctions += $_.BaseName
        }
    }

    Write-Verbose "Successfully loaded functions: $($loadedFunctions -join ', ')"
    if ($failedFunctions.Count -gt 0) {
        Write-Warning "Failed to load functions: $($failedFunctions -join ', ')"
    }
} else {
    throw "Cannot find Public functions directory: $publicFunctionPath"
}

# Verify the FileHashDatabase class is accessible (if it was loaded)
if ($classLoaded) {
    try {
        # Try to create a test instance to verify the class works
        $tempPath = [System.IO.Path]::GetTempPath()
        $testDbPath = Join-Path $tempPath "ModuleLoadTest_$(Get-Random).db"
        $testInstance = [FileHashDatabase]::new($testDbPath)

        if ($testInstance) {
            Write-Verbose "FileHashDatabase class verified successfully"
            $testInstance = $null

            # Clean up test database
            if (Test-Path $testDbPath) {
                Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "FileHashDatabase class verification failed: $_"
        Write-Warning "Class-dependent functionality may not work properly"
    }
}

# Export functions (this should match your manifest)
Export-ModuleMember -Function @(
    'Get-FileHashRecord',
    'Move-FileHashDuplicate',
    'Write-FileHashRecord'
)

# Export the Config variable for use by functions
Export-ModuleMember -Variable Config

Write-Verbose "FileHashDatabase module loaded successfully"
