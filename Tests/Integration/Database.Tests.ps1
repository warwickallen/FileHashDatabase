BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force

    # Load test helpers
    . "$PSScriptRoot/../TestHelpers/DatabaseHelpers.ps1"
    . "$PSScriptRoot/../TestHelpers/FileSystemHelpers.ps1"
}

Describe "End-to-End Integration Tests" -Tag "Integration", "E2E" {
    BeforeAll {
        $script:testDbPath = Join-Path $TestDrive "integration.db"
        $script:duplicatesPath = Join-Path $TestDrive "duplicates"
        New-Item -Path $script:duplicatesPath -ItemType Directory -Force
    }

    AfterEach {
        if (Test-Path $script:testDbPath) {
            Remove-Item $script:testDbPath -Force -ErrorAction SilentlyContinue
        }

        # Clean up test files
        Get-ChildItem $TestDrive -File | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Context "Complete Workflow: Scan, Store, Duplicate Detection, Export" {
        It "Should complete full workflow without errors" {
            # Create test files with known duplicates
            $testFiles = @(
                New-TestFile -Path (Join-Path $TestDrive "file1.txt") -Content "Content A"
                New-TestFile -Path (Join-Path $TestDrive "file2.txt") -Content "Content B"
                New-TestFile -Path (Join-Path $TestDrive "file3.txt") -Content "Content A"  # Duplicate of file1
                New-TestFile -Path (Join-Path $TestDrive "file4.txt") -Content "Content C"
            )

            # Step 1: Scan and store hashes
            { Get-FileHashes -DatabasePath $script:testDbPath } | Should -Not -Throw

            # Verify database was created and populated
            Test-Path $script:testDbPath | Should -Be $true
            Test-DatabaseConnection -DatabasePath $script:testDbPath | Should -Be $true

            # Step 2: Identify and move duplicates
            { Move-FileHashDuplicates -DatabasePath $script:testDbPath -Destination $script:duplicatesPath } | Should -Not -Throw

            # Step 3: Export results
            $exportPath = Join-Path $TestDrive "export.csv"
            { Write-FileHashes -DatabasePath $script:testDbPath -OutputPath $exportPath } | Should -Not -Throw

            # Verify export file exists and has content
            Test-Path $exportPath | Should -Be $true
            $exportContent = Get-Content $exportPath
            $exportContent.Count | Should -BeGreaterThan 1  # Header plus data
        }

        It "Should handle large file sets efficiently" {
            # Create 50 test files (some duplicates)
            $testFiles = @()
            for ($i = 1; $i -le 50; $i++) {
                $content = if ($i % 10 -eq 0) { "Duplicate content" } else { "Unique content $i" }
                $testFiles += New-TestFile -Path (Join-Path $TestDrive "test_$i.txt") -Content $content
            }

            # Measure performance
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            Get-FileHashes -DatabasePath $script:testDbPath
            Move-FileHashDuplicates -DatabasePath $script:testDbPath -Destination $script:duplicatesPath

            $stopwatch.Stop()

            # Should complete within reasonable time (30 seconds)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 30000

            # Verify duplicates were moved
            $duplicateFiles = Get-ChildItem $script:duplicatesPath -File
            $duplicateFiles.Count | Should -BeGreaterThan 0
        }
    }

    Context "Database Schema and Data Integrity" {
        It "Should create proper database schema" {
            Get-FileHashes -DatabasePath $script:testDbPath

            # Test database structure
            if (Get-Module -ListAvailable PSSQLite) {
                Import-Module PSSQLite -Force

                # Check if FileHashes table exists
                $tables = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='FileHashes'"
                $tables.name | Should -Contain "FileHashes"

                # Check table schema
                $schema = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "PRAGMA table_info(FileHashes)"
                $columnNames = $schema.name
                $columnNames | Should -Contain "Id"
                $columnNames | Should -Contain "FilePath"
                $columnNames | Should -Contain "Hash"
                $columnNames | Should -Contain "Algorithm"
            }
        }

        It "Should maintain data consistency across operations" {
            # Create test files
            $file1 = New-TestFile -Path (Join-Path $TestDrive "consistent1.txt") -Content "Test content"
            $file2 = New-TestFile -Path (Join-Path $TestDrive "consistent2.txt") -Content "Test content"

            # Initial scan
            Get-FileHashes -DatabasePath $script:testDbPath

            # Get initial record count
            if (Get-Module -ListAvailable PSSQLite) {
                Import-Module PSSQLite -Force
                $initialCount = (Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as count FROM FileHashes").count

                # Move duplicates
                Move-FileHashDuplicates -DatabasePath $script:testDbPath -Destination $script:duplicatesPath

                # Record count should remain the same (data integrity)
                $finalCount = (Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as count FROM FileHashes").count
                $finalCount | Should -Be $initialCount
            }
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle missing source directories gracefully" {
            $nonExistentPath = Join-Path $TestDrive "nonexistent"
            { Get-FileHashes -Path $nonExistentPath -DatabasePath $script:testDbPath } | Should -Throw
        }

        It "Should handle database permission errors" {
            # This test would be platform-specific, focusing on Windows
            # For now, just test with an invalid path
            $invalidDbPath = "Z:\invalid\path\database.db"
            { Get-FileHashes -DatabasePath $invalidDbPath } | Should -Throw
        }

        It "Should handle empty directories" {
            $emptyDir = Join-Path $TestDrive "empty"
            New-Item -Path $emptyDir -ItemType Directory -Force

            { Get-FileHashes -Path $emptyDir -DatabasePath $script:testDbPath } | Should -Not -Throw
        }
    }
}
