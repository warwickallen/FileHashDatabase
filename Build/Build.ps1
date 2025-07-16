# Build.ps1 - Local development and validation script

[CmdletBinding()]
param(
    [switch]$RunTests,
    [switch]$SkipPSSQLite
)

$ErrorActionPreference = 'Stop'

Write-Host "FileHashDatabase Module Build Script" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

# Validate module structure
$ScriptRoot = Get-Item -Path $PSScriptRoot
$ModuleRoot = Join-Path -Path $ScriptRoot.Parent.FullName -ChildPath 'FileHashDatabase'
$ManifestPath = Join-Path $ModuleRoot 'FileHashDatabase.psd1'

if (-not (Test-Path $ManifestPath)) {
    throw "Module manifest not found at: $ManifestPath"
}

Write-Host "Testing module manifest..." -ForegroundColor Yellow
try {
    $manifest = Test-ModuleManifest -Path $ManifestPath -Verbose
    Write-Host "✅ Module manifest is valid" -ForegroundColor Green
    Write-Host "   Version: $($manifest.Version)" -ForegroundColor Gray
    Write-Host "   Functions: $($manifest.ExportedFunctions.Keys -join ', ')" -ForegroundColor Gray
} catch {
    Write-Error "❌ Module manifest validation failed: $_"
    throw
}

Write-Host "Testing module import..." -ForegroundColor Yellow
try {
    # Remove module if already loaded
    if (Get-Module FileHashDatabase) {
        Remove-Module FileHashDatabase -Force
    }
    
    Import-Module $ManifestPath -Force -Verbose:$false
    $module = Get-Module FileHashDatabase
    
    if (-not $module) {
        throw "Module was not imported"
    }
    
    Write-Host "✅ Module imported successfully" -ForegroundColor Green
    
    # Test exported functions
    $exportedCommands = Get-Command -Module FileHashDatabase
    Write-Host "   Exported commands: $($exportedCommands.Name -join ', ')" -ForegroundColor Gray
    
    if ($exportedCommands.Count -eq 0) {
        throw "No commands were exported"
    }
    
} catch {
    Write-Error "❌ Module import failed: $_"
    throw
}

# Test class availability
Write-Host "Testing FileHashDatabase class..." -ForegroundColor Yellow
try {
    $testDbPath = Join-Path ([System.IO.Path]::GetTempPath()) "BuildTest_$(Get-Random).db"
    $testInstance = [FileHashDatabase]::new($testDbPath)
    
    if ($testInstance) {
        Write-Host "✅ FileHashDatabase class is accessible" -ForegroundColor Green
        $testInstance = $null
    }
    
    # Clean up
    if (Test-Path $testDbPath) {
        Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue
    }
    
} catch {
    Write-Warning "⚠️  FileHashDatabase class test failed: $_"
    Write-Host "   This may indicate class loading issues" -ForegroundColor Yellow
}

# Check dependencies
Write-Host "Checking dependencies..." -ForegroundColor Yellow

$psSQLite = Get-Module -ListAvailable -Name PSSQLite
if ($psSQLite) {
    Write-Host "✅ PSSQLite is available (version: $($psSQLite.Version))" -ForegroundColor Green
} else {
    if ($SkipPSSQLite) {
        Write-Host "⚠️  PSSQLite not available (skipped)" -ForegroundColor Yellow
    } else {
        Write-Warning "❌ PSSQLite not available. Install with: Install-Module PSSQLite"
    }
}

# Run tests if requested
if ($RunTests) {
    Write-Host "Running tests..." -ForegroundColor Yellow
    
    $TestsPath = Join-Path $PSScriptRoot "Tests"
    if (Test-Path $TestsPath) {
        try {
            $pesterModule = Get-Module -ListAvailable -Name Pester
            if (-not $pesterModule) {
                Write-Warning "Pester not available. Installing..."
                Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
            }
            
            Import-Module Pester -Force
            
            $testResults = Invoke-Pester -Path $TestsPath -PassThru
            
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
        }
    } else {
        Write-Warning "Tests directory not found at: $TestsPath"
    }
}

Write-Host "Build validation completed successfully!" -ForegroundColor Green
