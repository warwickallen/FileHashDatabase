# Simple.Tests.ps1 - Minimal test to verify CI setup
BeforeAll {
    # Determine the correct module path
    if ($env:TEST_MODULE_PATH) {
        $ModulePath = $env:TEST_MODULE_PATH
        $ModuleManifest = Get-Item $ModulePath
        $ModuleDirectory = Split-Path $ModulePath -Parent
    } else {
        # Fallback for local testing - look in the parent directory's FileHashDatabase subdirectory
        $RepositoryRoot = Split-Path $PSScriptRoot -Parent
        $ModuleDirectory = Join-Path $RepositoryRoot "FileHashDatabase"
        $ModuleManifest = Get-ChildItem -Path $ModuleDirectory -Filter "*.psd1" -Recurse | Select-Object -First 1
        if ($ModuleManifest) {
            $ModulePath = $ModuleManifest.FullName
        }
    }

    # Basic environment check
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host "Current Location: $(Get-Location)"
    Write-Host "Test Script Root: $PSScriptRoot"
    Write-Host "Repository Root: $(Split-Path $PSScriptRoot -Parent)"
    Write-Host "Module Directory: $ModuleDirectory"
    Write-Host "Module Path: $ModulePath"
    Write-Host "Available Modules: $(Get-Module -ListAvailable | Where-Object Name -like '*FileHash*' | Select-Object -ExpandProperty Name)"

    # Try to find and import the module
    if ($ModuleManifest -and (Test-Path $ModuleManifest.FullName)) {
        Write-Host "Found module manifest: $($ModuleManifest.FullName)"
        try {
            Import-Module $ModuleManifest.FullName -Force
            Write-Host "Module imported successfully"
        }
        catch {
            Write-Warning "Failed to import module: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "No module manifest found in expected location: $ModuleDirectory"
    }
}

Describe "Basic Environment Tests" {
    It "Should be running PowerShell" {
        $PSVersionTable | Should -Not -BeNullOrEmpty
    }

    It "Should have Pester available" {
        Get-Module -Name Pester | Should -Not -BeNullOrEmpty
    }

    It "Should be able to find the repository root" {
        Test-Path $PSScriptRoot | Should -Be $true
    }
}

Describe "Module Discovery Tests" {
    BeforeAll {
        # Look in the correct location for module files
        $RepositoryRoot = Split-Path $PSScriptRoot -Parent
        $ModuleDirectory = Join-Path $RepositoryRoot "FileHashDatabase"
    }

    It "Should find at least one PowerShell file in the module directory" {
        $PSFiles = Get-ChildItem -Path $ModuleDirectory -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
        $PSFiles.Count | Should -BeGreaterThan 0
    }

    It "Should find a module manifest" {
        $ManifestFiles = Get-ChildItem -Path $ModuleDirectory -Filter "*.psd1" -Recurse -ErrorAction SilentlyContinue
        $ManifestFiles.Count | Should -BeGreaterOrEqual 1
    }

    It "Should find the FileHashDatabase directory" {
        Test-Path $ModuleDirectory | Should -Be $true
    }
}

Describe "Module Import Tests" {
    BeforeAll {
        # Use the same logic as the main BeforeAll block
        if ($env:TEST_MODULE_PATH) {
            $ModuleManifest = Get-Item $env:TEST_MODULE_PATH
        } else {
            $RepositoryRoot = Split-Path $PSScriptRoot -Parent
            $ModuleDirectory = Join-Path $RepositoryRoot "FileHashDatabase"
            $ModuleManifest = Get-ChildItem -Path $ModuleDirectory -Filter "*.psd1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }

    It "Should have a valid module manifest" {
        $ModuleManifest | Should -Not -BeNullOrEmpty
        if ($ModuleManifest) {
            Test-Path $ModuleManifest.FullName | Should -Be $true
        }
    }

    It "Should be able to test the module manifest" {
        if ($ModuleManifest) {
            { Test-ModuleManifest -Path $ModuleManifest.FullName } | Should -Not -Throw
        }
    }

    It "Should be able to import the module" {
        if ($ModuleManifest) {
            { Import-Module $ModuleManifest.FullName -Force } | Should -Not -Throw
        }
    }

    It "Should export at least one function after import" {
        if ($ModuleManifest) {
            Import-Module $ModuleManifest.FullName -Force
            $ModuleName = (Get-Item $ModuleManifest.FullName).BaseName
            $ExportedCommands = Get-Command -Module $ModuleName -ErrorAction SilentlyContinue
            $ExportedCommands.Count | Should -BeGreaterThan 0
        }
    }
}