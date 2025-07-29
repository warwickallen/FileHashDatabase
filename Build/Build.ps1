# Build.ps1 - Local development and validation script
# Located in Build/ subdirectory

[CmdletBinding()]
param(
    [switch]$RunTests,
    [switch]$SkipPSSQLite
)

$ErrorActionPreference = 'Stop'

Write-Output "FileHashDatabase Module Build Script"
Write-Output "====================================="

# Determine paths - since this script is in Build/ subdirectory
$BuildRoot = $PSScriptRoot
$RepositoryRoot = Split-Path $BuildRoot -Parent
$ModuleRoot = Join-Path $RepositoryRoot "src"
$ManifestPath = Join-Path $ModuleRoot "FileHashDatabase.psd1"
$TestsPath = Join-Path $RepositoryRoot "Tests"

Write-Output "Build script location: $BuildRoot"
Write-Output "Repository root: $RepositoryRoot"
Write-Output "Module root: $ModuleRoot"
Write-Output "Manifest path: $ManifestPath"

# Validate paths exist
if (-not (Test-Path $RepositoryRoot)) {
    throw "Repository root not found at: $RepositoryRoot"
}

if (-not (Test-Path $ModuleRoot)) {
    throw "Module directory not found at: $ModuleRoot"
}

if (-not (Test-Path $ManifestPath)) {
    throw "Module manifest not found at: $ManifestPath"
}

Write-Output "Testing module manifest..."
try {
    $manifest = Test-ModuleManifest -Path $ManifestPath -Verbose:$false
    Write-Output "[OK] Module manifest is valid"
    Write-Output "     Version: $($manifest.Version)"
    Write-Output "     Functions to export: $($manifest.ExportedFunctions.Keys -join ', ')"
} catch {
    Write-Error "[KO] Module manifest validation failed: $_"
    throw
}

Write-Output "Testing module import..."
try {
    # Remove module if already loaded
    if (Get-Module FileHashDatabase) {
        Remove-Module FileHashDatabase -Force
        Write-Verbose "Removed existing FileHashDatabase module"
    }

    # Import with full path to avoid any path resolution issues
    Import-Module $ManifestPath -Force -Verbose:$false
    $module = Get-Module FileHashDatabase

    if (-not $module) {
        throw "Module was not imported"
    }

    Write-Output "[OK] Module imported successfully"
    Write-Output "     Module path: $($module.Path)"

    # Test exported functions
    $exportedCommands = Get-Command -Module FileHashDatabase
    if ($exportedCommands) {
        Write-Output "   Exported commands: $($exportedCommands.Name -join ', ')"
    } else {
        Write-Warning "No commands were exported from the module"
    }

    if ($exportedCommands.Count -eq 0) {
        throw "No commands were exported"
    }

} catch {
    Write-Error "[KO] Module import failed: $_"
    Write-Output "    Debug information:"
    Write-Output "      Current location: $(Get-Location)"
    Write-Output "      PowerShell version: $($PSVersionTable.PSVersion)"
    Write-Output "      Module path being imported: $ManifestPath"
    throw
}

# Test class availability
Write-Output "Testing FileHashDatabase class..."
try {
    # Create a test database in a temp location
    $tempDir = [System.IO.Path]::GetTempPath()
    $testDbPath = Join-Path $tempDir "BuildTest_$(Get-Random).db"

    Write-Verbose "Attempting to create FileHashDatabase instance with path: $testDbPath"

    # Try to instantiate the class
    $testInstance = [FileHashDatabase]::new($testDbPath)

    if ($testInstance) {
        Write-Output "[OK] FileHashDatabase class is accessible"
        $testInstance = $null

        # Clean up test database
        if (Test-Path $testDbPath) {
            Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue
            Write-Verbose "Cleaned up test database: $testDbPath"
        }
    } else {
        throw "FileHashDatabase instance was null"
    }

} catch {
    Write-Warning "[!!]  FileHashDatabase class test failed: $_"
    Write-Output "       This may indicate class loading issues"
    Write-Output "       Checking if class type is available..."

    try {
        $classType = [FileHashDatabase] -as [type]
        if ($classType) {
            Write-Output "   Class type is available but instantiation failed"
        } else {
            Write-Output "   Class type is not available - class loading failed"
        }
    } catch {
        Write-Output "   Cannot access class type: $_"
    }
}

# Check dependencies
Write-Output "Checking dependencies..."

$psSQLite = Get-Module -ListAvailable -Name PSSQLite
if ($psSQLite) {
    Write-Output "[OK] PSSQLite is available (version: $($psSQLite.Version))"

    # Try importing it
    try {
        Import-Module PSSQLite -Force -Verbose:$false
        Write-Output "[OK] PSSQLite imported successfully"
    } catch {
        Write-Warning "[!!]  PSSQLite available but import failed: $_"
    }
} else {
    if ($SkipPSSQLite) {
        Write-Output "[!!]  PSSQLite not available (skipped)"
    } else {
        Write-Warning "[KO] PSSQLite not available. Install with: Install-Module PSSQLite"
        Write-Output "      Run with -SkipPSSQLite to bypass this check"
    }
}

# Check for Pester if we're going to run tests
if ($RunTests) {
    Write-Output "Checking Pester..."

    $pesterModule = Get-Module -ListAvailable -Name Pester
    if (-not $pesterModule) {
        Write-Warning "Pester not available. Installing..."
        try {
            Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
            Write-Output "[OK] Pester installed"
        } catch {
            Write-Error "Failed to install Pester: $_"
            throw
        }
    } else {
        Write-Output "[OK] Pester is available (version: $($pesterModule.Version))"
    }
}

# Run tests if requested
if ($RunTests) {
    Write-Output "Running tests..."

    if (Test-Path $TestsPath) {
        try {
            Import-Module Pester -Force

            # Set environment variable for tests to find the module
            $env:TEST_MODULE_PATH = $ManifestPath

            Write-Output "Test path: $TestsPath"
            Write-Output "Module path for tests: $env:TEST_MODULE_PATH"

            $testResults = Invoke-Pester -Path $TestsPath -PassThru -Verbose:$false

            Write-Output "Test Results:"
            Write-Output "  Total: $($testResults.TotalCount)"
            Write-Output "  Passed: $($testResults.PassedCount)"
            Write-Output "  Failed: $($testResults.FailedCount)" -ForegroundColor $(if ($testResults.FailedCount -gt 0) { 'Red' } else { 'Gray' })
            Write-Output "  Skipped: $($testResults.SkippedCount)"

            if ($testResults.FailedCount -gt 0) {
                Write-Warning "Some tests failed!"
                return 1
            } else {
                Write-Output "[OK] All tests passed!"
            }

        } catch {
            Write-Error "[KO] Test execution failed: $_"
            throw
        } finally {
            # Clean up environment variable
            Remove-Item Env:TEST_MODULE_PATH -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warning "Tests directory not found at: $TestsPath"
    }
}

Write-Output "Build validation completed successfully!"

# Return 0 for success
return 0
