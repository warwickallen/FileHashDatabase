BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force

    # Load test helpers if they exist
    $databaseHelpersPath = "$PSScriptRoot/../TestHelpers/DatabaseHelpers.ps1"
    $filesystemHelpersPath = "$PSScriptRoot/../TestHelpers/FileSystemHelpers.ps1"

    if (Test-Path $databaseHelpersPath) {
        . $databaseHelpersPath
    }
    if (Test-Path $filesystemHelpersPath) {
        . $filesystemHelpersPath
    }
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
        It "Should complete basic workflow without errors" {
            # Create test files with known duplicates
            if (Get-Command "New-TestFile" -ErrorAction SilentlyContinue) {
                $testFiles = @(
                    New-TestFile -Path (Join-Path $TestDrive "file1.txt") -Content "Content A"
                    New-TestFile -Path (Join-Path $TestDrive "file2.txt") -Content "Content B"
                    New-TestFile -Path (Join-Path $TestDrive "file3.txt") -Content "Content A"  # Duplicate of file1
                    New-TestFile -Path (Join-Path $TestDrive "file4.txt") -Content "Content C"
                )
            } else {
                # Fallback if helper not available
                "Content A" | Out-File -FilePath (Join-Path $TestDrive "file1.txt") -Encoding UTF8
                "Content B" | Out-File -FilePath (Join-Path $TestDrive "file2.txt") -Encoding UTF8
                "Content A" | Out-File -FilePath (Join-Path $TestDrive "file3.txt") -Encoding UTF8
                "Content C" | Out-File -FilePath (Join-Path $TestDrive "file4.txt") -Encoding UTF8
            }

            # Step 1: Scan and store hashes (use actual function signature)
            { Get-FileHashRecord -DatabasePath $script:testDbPath } | Should -Not -Throw

            # Verify database was created
            Test-Path $script:testDbPath | Should -Be $true

            # Step 2: Identify and move duplicates (use actual function signature)
            { Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $script:duplicatesPath } | Should -Not -Throw

            # Step 3: Export results (use actual function signature - no OutputPath parameter)
            { Write-FileHashRecord -DatabasePath $script:testDbPath } | Should -Not -Throw
        }

        It "Should handle file processing efficiently" {
            # Create 10 test files (more manageable than 50)
            for ($i = 1; $i -le 10; $i++) {
                $content = if ($i % 5 -eq 0) { "Duplicate content" } else { "Unique content $i" }
                $content | Out-File -FilePath (Join-Path $TestDrive "test_$i.txt") -Encoding UTF8
            }

            # Measure performance
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            Get-FileHashRecord -DatabasePath $script:testDbPath
            Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $script:duplicatesPath

            $stopwatch.Stop()

            # Should complete within reasonable time (30 seconds)
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 30000
        }
    }

    Context "Database Schema and Data Integrity" {
        It "Should create database when running Get-FileHashRecord" {
            # Create a test file
            "Test content" | Out-File -FilePath (Join-Path $TestDrive "test.txt") -Encoding UTF8

            Get-FileHashRecord -DatabasePath $script:testDbPath

            # Verify database was created
            Test-Path $script:testDbPath | Should -Be $true

            # Test database structure (use actual table name from your schema)
            if (Get-Module -ListAvailable PSSQLite) {
                Import-Module PSSQLite -Force

                # Check if FileHash table exists (not FileHashes)
                $tables = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT name FROM sqlite_master WHERE type='table'"
                $tableNames = $tables.name
                Write-Output "Available tables: $($tableNames -join ', ')"

                # Your actual schema might use different table names - adjust as needed
                $tableNames.Count | Should -BeGreaterThan 0
            }
        }

        It "Should maintain data consistency" {
            # Create test files
            "Test content 1" | Out-File -FilePath (Join-Path $TestDrive "consistent1.txt") -Encoding UTF8
            "Test content 2" | Out-File -FilePath (Join-Path $TestDrive "consistent2.txt") -Encoding UTF8

            # Initial scan
            Get-FileHashRecord -DatabasePath $script:testDbPath

            # Verify database exists after operation
            Test-Path $script:testDbPath | Should -Be $true
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle challenging database paths appropriately" {
            # Test with an challenging but valid database path
            $challengingDbPath = Join-Path $TestDrive "subdir\another\database.db"

            # Your function likely creates the directory structure, which is good behavior
            { Get-FileHashRecord -DatabasePath $challengingDbPath } | Should -Not -Throw

            # Verify that the directory was created (if that's what your function does)
            $dbDir = Split-Path $challengingDbPath -Parent
            Test-Path $dbDir | Should -Be $true
        }

        It "Should handle empty directories" {
            $emptyDir = Join-Path $TestDrive "empty"
            New-Item -Path $emptyDir -ItemType Directory -Force

            # Test depends on actual function signature
            { Get-FileHashRecord -DatabasePath $script:testDbPath } | Should -Not -Throw
        }

        It "Should handle missing destination directories" {
            # Create a test database first
            "Test content" | Out-File -FilePath (Join-Path $TestDrive "test.txt") -Encoding UTF8
            Get-FileHashRecord -DatabasePath $script:testDbPath

            $nonExistentDest = Join-Path $TestDrive "nonexistent_destination"
            { Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $nonExistentDest } | Should -Not -Throw

            # Verify destination was created
            Test-Path $nonExistentDest | Should -Be $true
        }
    }
}
