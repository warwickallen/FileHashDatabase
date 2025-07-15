# Simple.Tests.ps1 - Minimal test to verify CI setup
BeforeAll {
    # Basic environment check
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host "Current Location: $(Get-Location)"
    Write-Host "Available Modules: $(Get-Module -ListAvailable | Where-Object Name -like '*FileHash*' | Select-Object -ExpandProperty Name)"

    # Try to find and import the module
    $ModuleManifest = Get-ChildItem -Path $PSScriptRoot -Filter "*.psd1" -Recurse | Select-Object -First 1
    if ($ModuleManifest) {
        Write-Host "Found module manifest: $($ModuleManifest.FullName)"
        try {
            Import-Module $ModuleManifest.FullName -Force
            Write-Host "Module imported successfully"
        }
        catch {
            Write-Warning "Failed to import module: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "No module manifest found"
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
    It "Should find at least one PowerShell file" {
        $PSFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -Recurse
        $PSFiles.Count | Should -BeGreaterThan 0
    }

    It "Should find a module manifest" {
        $ManifestFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.psd1" -Recurse
        $ManifestFiles.Count | Should -BeGreaterOrEqual 1
    }
}

Describe "Module Import Tests" {
    BeforeAll {
        $ModuleManifest = Get-ChildItem -Path $PSScriptRoot -Filter "*.psd1" -Recurse | Select-Object -First 1
    }

    It "Should have a valid module manifest" {
        $ModuleManifest | Should -Not -BeNullOrEmpty
        Test-Path $ModuleManifest.FullName | Should -Be $true
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
}
