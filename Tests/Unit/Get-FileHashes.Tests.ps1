BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force
}

Describe "Get-FileHashRecord.Function Availability" {
    It "Should be available after module import" {
        Get-Command Get-FileHashRecord | Should -Not -BeNullOrEmpty
    }
    It "Should have expected parameters" {
        $params = (Get-Command Get-FileHashRecord).Parameters.Keys
        $params | Should -Contain 'DatabasePath'
        $params | Should -Contain 'Limit'
        $params | Should -Contain 'Filter'
    }
}

Describe "Get-FileHashRecord.Basic Functionality" {
    BeforeAll {
        # Create test files in TestDrive
        $testFile1 = Join-Path $TestDrive "test1.txt"
        $testFile2 = Join-Path $TestDrive "test2.txt"
        Set-Content -Path $testFile1 -Value "Test content 1"
        Set-Content -Path $testFile2 -Value "Test content 2"

        $testDb = Join-Path $TestDrive "test.db"
    }

    It "Should process files without errors" {
        { Get-FileHashRecord -DatabasePath $testDb } | Should -Not -Throw
    }
}
