# Diagnostic.ps1 - Run this from the repository root to diagnose issues
Write-Output "FileHashDatabase Module Diagnostics"
Write-Output "===================================="
# Basic environment info
Write-Output "`nEnvironment Information:"
Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Output "PowerShell Edition: $($PSVersionTable.PSEdition)"
Write-Output "OS: $($PSVersionTable.OS)"
Write-Output "Current Location: $(Get-Location)"
# Path information
Write-Output "`nPath Information:"
$repoRoot = Get-Location
$buildPath = Join-Path $repoRoot "Build"
$modulePath = Join-Path $repoRoot "src"
$manifestPath = Join-Path $modulePath "FileHashDatabase.psd1"
$psm1Path = Join-Path $modulePath "FileHashDatabase.psm1"
Write-Output "Repository Root: $repoRoot"
Write-Output "Build Directory: $buildPath (Exists: $(Test-Path $buildPath))"
Write-Output "Module Directory: $modulePath (Exists: $(Test-Path $modulePath))"
Write-Output "Manifest File: $manifestPath (Exists: $(Test-Path $manifestPath))"
Write-Output "PSM1 File: $psm1Path (Exists: $(Test-Path $psm1Path))"
# Test manifest
if (Test-Path $manifestPath) {
    Write-Output "`nTesting Manifest:"
    try {
        $manifest = Test-ModuleManifest -Path $manifestPath
        Write-Output "[OK] Manifest is valid"
        Write-Output "     Version: $($manifest.Version)"
        Write-Output "     Root Module: $($manifest.RootModule)"
        Write-Output "     Functions to Export: $($manifest.ExportedFunctions.Keys -join ', ')"
    } catch {
        Write-Output "[KO] Manifest test failed: $_"
    }
} else {
    Write-Output "[KO] Manifest file not found"
}
# Test PSM1 content
if (Test-Path $psm1Path) {
    Write-Output "`nAnalyzing PSM1 File:"
    $psm1Content = Get-Content $psm1Path -Raw
    if ($psm1Content -match '\$PSScriptRoot') {
        Write-Output "[OK] PSM1 file contains PSScriptRoot references"
    } else {
        Write-Output "[!!]  PSM1 file does not contain PSScriptRoot references"
    }
    if ($psm1Content -match 'Get-ModuleRoot') {
        Write-Output "[OK] PSM1 file contains Get-ModuleRoot function"
    } else {
        Write-Output "[KO] PSM1 file missing Get-ModuleRoot function"
    }
} else {
    Write-Output "[KO] PSM1 file not found"
}
# Test module import
Write-Output "`nTesting Module Import:"
try {
    # Remove if already loaded
    if (Get-Module FileHashDatabase) {
        Remove-Module FileHashDatabase -Force
        Write-Output "Removed existing module"
    }
    # Test import
    Import-Module $manifestPath -Force -Verbose
    $module = Get-Module FileHashDatabase
    if ($module) {
        Write-Output "[OK] Module imported successfully"
        Write-Output "     Name: $($module.Name)"
        Write-Output "     Version: $($module.Version)"
        Write-Output "     Path: $($module.Path)"
        $commands = Get-Command -Module FileHashDatabase
        if ($commands) {
            Write-Output "   Exported Commands: $($commands.Name -join ', ')"
        } else {
            Write-Output "[!!]  No commands exported"
        }
    } else {
        Write-Output "[KO] Module not found after import"
    }
} catch {
    Write-Output "[KO] Module import failed: $_"
    Write-Output "     Error details: $($_.Exception.Message)"
}
# Test class availability
Write-Output "`nTesting Class Availability:"
try {
    $classType = [FileHashDatabase] -as [type]
    if ($classType) {
        Write-Output "[OK] FileHashDatabase class type is available"
        Write-Output "   Type: $($classType.FullName)"
        # Try instantiation
        try {
            $testPath = Join-Path ([System.IO.Path]::GetTempPath()) "DiagTest.db"
            $instance = [FileHashDatabase]::new($testPath)
            if ($instance) {
                Write-Output "[OK] FileHashDatabase class can be instantiated"
                $instance = $null
                if (Test-Path $testPath) {
                    Remove-Item $testPath -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Output "[KO] FileHashDatabase class instantiation failed: $_"
        }
    } else {
        Write-Output "[KO] FileHashDatabase class type not available"
    }
} catch {
    Write-Output "[KO] Error checking class availability: $_"
}
# Module dependencies
Write-Output "`nChecking Dependencies:"
$pssqlite = Get-Module -ListAvailable -Name PSSQLite
if ($pssqlite) {
    Write-Output "[OK] PSSQLite available (version: $($pssqlite.Version))"
} else {
    Write-Output "[!!]  PSSQLite not available"
}
$pester = Get-Module -ListAvailable -Name Pester
if ($pester) {
    Write-Output "[OK] Pester available (version: $($pester.Version))"
} else {
    Write-Output "[!!]  Pester not available"
}
Write-Output "`nDiagnostics completed!"