BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot "../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force
}

Describe "FileHashDatabase Module" {
    Context "Module Loading" {
        It "Should load without errors" {
            { Import-Module $ModulePath -Force } | Should -Not -Throw
        }

        It "Should export expected commands" {
            $commands = Get-Command -Module FileHashDatabase
            $expectedCommands = @('Get-FileHashRecord', 'Move-FileHashDuplicates', 'Write-FileHashRecord')

            foreach ($expected in $expectedCommands) {
                $commands.Name | Should -Contain $expected
            }
        }
    }

    Context "Module Manifest" {
        BeforeAll {
            $manifest = Test-ModuleManifest -Path $ModulePath
        }

        It "Should have a valid manifest" {
            $manifest | Should -Not -BeNullOrEmpty
        }

        It "Should have required metadata" {
            $manifest.Name | Should -Be "FileHashDatabase"
            $manifest.Version | Should -Not -BeNullOrEmpty
            $manifest.Author | Should -Not -BeNullOrEmpty
        }
    }
}
