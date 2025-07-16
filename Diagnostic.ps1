# Diagnostic.ps1 - Run this from the repository root to diagnose issues

Write-Host "FileHashDatabase Module Diagnostics" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Basic environment info
Write-Host "`nEnvironment Information:" -ForegroundColor Yellow
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "PowerShell Edition: $($PSVersionTable.PSEdition)"
Write-Host "OS: $($PSVersionTable.OS)"
Write-Host "Current Location: $(Get-Location)"

# Path information
Write-Host "`nPath Information:" -ForegroundColor Yellow
$repoRoot = Get-Location
$buildPath = Join-Path $repoRoot "Build"
$modulePath = Join-Path $repoRoot "FileHashDatabase"
$manifestPath = Join-Path $modulePath "FileHashDatabase.psd1"
$psm1Path = Join-Path $modulePath "FileHashDatabase.psm1"

Write-Host "Repository Root: $repoRoot"
Write-Host "Build Directory: $buildPath (Exists: $(Test-Path $buildPath))"
Write-Host "Module Directory: $modulePath (Exists: $(Test-Path $modulePath))"
Write-Host "Manifest File: $manifestPath (Exists: $(Test-Path $manifestPath))"
Write-Host "PSM1 File: $psm1Path (Exists: $(Test-Path $psm1Path))"

# Test manifest
if (Test-Path $manifestPath) {
    Write-Host "`nTesting Manifest:" -ForegroundColor Yellow
    try {
        $manifest = Test-ModuleManifest -Path $manifestPath
        Write-Host "✅ Manifest is valid"
        Write-Host "   Version: $($manifest.Version)"
        Write-Host "   Root Module: $($manifest.RootModule)"
        Write-Host "   Functions to Export: $($manifest.ExportedFunctions.Keys -join ', ')"
    } catch {
        Write-Host "❌ Manifest test failed: $_" -ForegroundColor Red
    }
} else {
    Write-Host "❌ Manifest file not found" -ForegroundColor Red
}

# Test PSM1 content
if (Test-Path $psm1Path) {
    Write-Host "`nAnalyzing PSM1 File:" -ForegroundColor Yellow
    $psm1Content = Get-Content $psm1Path -Raw
    
    if ($psm1Content -match '\$PSScriptRoot') {
        Write-Host "✅ PSM1 file contains PSScriptRoot references"
    } else {
        Write-Host "⚠️  PSM1 file does not contain PSScriptRoot references"
    }
    
    if ($psm1Content -match 'Get-ModuleRoot') {
        Write-Host "✅ PSM1 file contains Get-ModuleRoot function"
    } else {
        Write-Host "❌ PSM1 file missing Get-ModuleRoot function"
    }
} else {
    Write-Host "❌ PSM1 file not found" -ForegroundColor Red
}

# Test module import
Write-Host "`nTesting Module Import:" -ForegroundColor Yellow
try {
    # Remove if already loaded
    if (Get-Module FileHashDatabase) {
        Remove-Module FileHashDatabase -Force
        Write-Host "Removed existing module"
    }
    
    # Test import
    Import-Module $manifestPath -Force -Verbose
    $module = Get-Module FileHashDatabase
    
    if ($module) {
        Write-Host "✅ Module imported successfully"
        Write-Host "   Name: $($module.Name)"
        Write-Host "   Version: $($module.Version)"
        Write-Host "   Path: $($module.Path)"
        
        $commands = Get-Command -Module FileHashDatabase
        if ($commands) {
            Write-Host "   Exported Commands: $($commands.Name -join ', ')"
        } else {
            Write-Host "⚠️  No commands exported"
        }
    } else {
        Write-Host "❌ Module not found after import" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Module import failed: $_" -ForegroundColor Red
    Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
}

# Test class availability
Write-Host "`nTesting Class Availability:" -ForegroundColor Yellow
try {
    $classType = [FileHashDatabase] -as [type]
    if ($classType) {
        Write-Host "✅ FileHashDatabase class type is available"
        Write-Host "   Type: $($classType.FullName)"
        
        # Try instantiation
        try {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "DiagTest.db"
            $instance = [FileHashDatabase]::new($testPath)
            if ($instance) {
                Write-Host "✅ FileHashDatabase class can be instantiated"
                $instance = $null
                if (Test-Path $testPath) {
                    Remove-Item $testPath -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Host "❌ FileHashDatabase class instantiation failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "❌ FileHashDatabase class type not available" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error checking class availability: $_" -ForegroundColor Red
}

# Module dependencies
Write-Host "`nChecking Dependencies:" -ForegroundColor Yellow
$pssqlite = Get-Module -ListAvailable -Name PSSQLite
if ($pssqlite) {
    Write-Host "✅ PSSQLite available (version: $($pssqlite.Version))"
} else {
    Write-Host "⚠️  PSSQLite not available"
}

$pester = Get-Module -ListAvailable -Name Pester
if ($pester) {
    Write-Host "✅ Pester available (version: $($pester.Version))"
} else {
    Write-Host "⚠️  Pester not available"
}

Write-Host "`nDiagnostics completed!" -ForegroundColor Cyan
