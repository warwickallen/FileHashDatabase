BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force
}

Describe "Get-FileHashes" {
    Context "Function Availability" {
        It "Should be available after module import" {
            Get-Command Get-FileHashes | Should -Not -BeNullOrEmpty
        }

        It "Should have expected parameters" {
            $command = Get-Command Get-FileHashes
            $expectedParams = @('Path', 'DatabasePath', 'Algorithm')

            foreach ($param in $expectedParams) {
                $command.Parameters.Keys | Should -Contain $param -Because "Parameter $param should exist"
            }
        }
    }

    Context "Basic Functionality" -Tag "RequiresTestFiles" {
        BeforeAll {
            # Create test files in TestDrive
            $testFile1 = Join-Path $TestDrive "test1.txt"
            $testFile2 = Join-Path $TestDrive "test2.txt"
            Set-Content -Path $testFile1 -Value "Test content 1"
            Set-Content -Path $testFile2 -Value "Test content 2"

            $testDb = Join-Path $TestDrive "test.db"
        }

        It "Should process files without errors" {
            { Get-FileHashes -Path $TestDrive -DatabasePath $testDb } | Should -Not -Throw
        }
    }
}
