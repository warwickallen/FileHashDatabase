# Build.ps1 - Local development and validation script
# Located in Build/ subdirectory

[CmdletBinding()]
param(
    [switch]$RunTests,
    [switch]$SkipPSSQLite
)

$ErrorActionPreference = 'Stop'

Write-Host "FileHashDatabase Module Build Script" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

# Determine paths - since this script is in Build/ subdirectory
$BuildRoot = $PSScriptRoot
$RepositoryRoot = Split-Path $BuildRoot -Parent
$ModuleRoot = Join-Path $RepositoryRoot "src"
$ManifestPath = Join-Path $ModuleRoot "FileHashDatabase.psd1"
$TestsPath = Join-Path $RepositoryRoot "Tests"

Write-Host "Build script location: $BuildRoot" -ForegroundColor Gray
Write-Host "Repository root: $RepositoryRoot" -ForegroundColor Gray
Write-Host "Module root: $ModuleRoot" -ForegroundColor Gray
Write-Host "Manifest path: $ManifestPath" -ForegroundColor Gray

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

Write-Host "Testing module manifest..." -ForegroundColor Yellow
try {
    $manifest = Test-ModuleManifest -Path $ManifestPath -Verbose:$false
    Write-Host "✅ Module manifest is valid" -ForegroundColor Green
    Write-Host "   Version: $($manifest.Version)" -ForegroundColor Gray
    Write-Host "   Functions to export: $($manifest.ExportedFunctions.Keys -join ', ')" -ForegroundColor Gray
} catch {
    Write-Error "❌ Module manifest validation failed: $_"
    throw
}

Write-Host "Testing module import..." -ForegroundColor Yellow
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
    
    Write-Host "✅ Module imported successfully" -ForegroundColor Green
    Write-Host "   Module path: $($module.Path)" -ForegroundColor Gray
    
    # Test exported functions
    $exportedCommands = Get-Command -Module FileHashDatabase
    if ($exportedCommands) {
        Write-Host "   Exported commands: $($exportedCommands.Name -join ', ')" -ForegroundColor Gray
    } else {
        Write-Warning "No commands were exported from the module"
    }
    
    if ($exportedCommands.Count -eq 0) {
        throw "No commands were exported"
    }
    
} catch {
    Write-Error "❌ Module import failed: $_"
    Write-Host "Debug information:" -ForegroundColor Yellow
    Write-Host "  Current location: $(Get-Location)" -ForegroundColor Gray
    Write-Host "  PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "  Module path being imported: $ManifestPath" -ForegroundColor Gray
    throw
}

# Test class availability
Write-Host "Testing FileHashDatabase class..." -ForegroundColor Yellow
try {
    # Create a test database in a temp location
    $tempDir = [System.IO.Path]::GetTempPath()
    $testDbPath = Join-Path $tempDir "BuildTest_$(Get-Random).db"
    
    Write-Verbose "Attempting to create FileHashDatabase instance with path: $testDbPath"
    
    # Try to instantiate the class
    $testInstance = [FileHashDatabase]::new($testDbPath)
    
    if ($testInstance) {
        Write-Host "✅ FileHashDatabase class is accessible" -ForegroundColor Green
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
    Write-Warning "⚠️  FileHashDatabase class test failed: $_"
    Write-Host "   This may indicate class loading issues" -ForegroundColor Yellow
    Write-Host "   Checking if class type is available..." -ForegroundColor Yellow
    
    try {
        $classType = [FileHashDatabase] -as [type]
        if ($classType) {
            Write-Host "   Class type is available but instantiation failed" -ForegroundColor Yellow
        } else {
            Write-Host "   Class type is not available - class loading failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "   Cannot access class type: $_" -ForegroundColor Red
    }
}

# Check dependencies
Write-Host "Checking dependencies..." -ForegroundColor Yellow

$psSQLite = Get-Module -ListAvailable -Name PSSQLite
if ($psSQLite) {
    Write-Host "✅ PSSQLite is available (version: $($psSQLite.Version))" -ForegroundColor Green
    
    # Try importing it
    try {
        Import-Module PSSQLite -Force -Verbose:$false
        Write-Host "✅ PSSQLite imported successfully" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  PSSQLite available but import failed: $_"
    }
} else {
    if ($SkipPSSQLite) {
        Write-Host "⚠️  PSSQLite not available (skipped)" -ForegroundColor Yellow
    } else {
        Write-Warning "❌ PSSQLite not available. Install with: Install-Module PSSQLite"
        Write-Host "   Run with -SkipPSSQLite to bypass this check" -ForegroundColor Gray
    }
}

# Check for Pester if we're going to run tests
if ($RunTests) {
    Write-Host "Checking Pester..." -ForegroundColor Yellow
    
    $pesterModule = Get-Module -ListAvailable -Name Pester
    if (-not $pesterModule) {
        Write-Warning "Pester not available. Installing..."
        try {
            Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
            Write-Host "✅ Pester installed" -ForegroundColor Green
        } catch {
            Write-Error "Failed to install Pester: $_"
            throw
        }
    } else {
        Write-Host "✅ Pester is available (version: $($pesterModule.Version))" -ForegroundColor Green
    }
}

# Run tests if requested
if ($RunTests) {
    Write-Host "Running tests..." -ForegroundColor Yellow
    
    if (Test-Path $TestsPath) {
        try {
            Import-Module Pester -Force
            
            # Set environment variable for tests to find the module
            $env:TEST_MODULE_PATH = $ManifestPath
            
            Write-Host "Test path: $TestsPath" -ForegroundColor Gray
            Write-Host "Module path for tests: $env:TEST_MODULE_PATH" -ForegroundColor Gray
            
            $testResults = Invoke-Pester -Path $TestsPath -PassThru -Verbose:$false
            
            Write-Host "Test Results:" -ForegroundColor Yellow
            Write-Host "  Total: $($testResults.TotalCount)" -ForegroundColor Gray
            Write-Host "  Passed: $($testResults.PassedCount)" -ForegroundColor Green
            Write-Host "  Failed: $($testResults.FailedCount)" -ForegroundColor $(if ($testResults.FailedCount -gt 0) { 'Red' } else { 'Gray' })
            Write-Host "  Skipped: $($testResults.SkippedCount)" -ForegroundColor Yellow
            
            if ($testResults.FailedCount -gt 0) {
                Write-Warning "Some tests failed!"
                return 1
            } else {
                Write-Host "✅ All tests passed!" -ForegroundColor Green
            }
            
        } catch {
            Write-Error "❌ Test execution failed: $_"
            throw
        } finally {
            # Clean up environment variable
            Remove-Item Env:TEST_MODULE_PATH -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warning "Tests directory not found at: $TestsPath"
    }
}

Write-Host "Build validation completed successfully!" -ForegroundColor Green

# Return 0 for success
return 0
