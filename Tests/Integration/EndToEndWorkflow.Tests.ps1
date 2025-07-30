BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psm1"
    Import-Module $ModulePath -Force

    # Load test helpers
    $databaseHelpersPath = "$PSScriptRoot/../TestHelpers/DatabaseHelpers.ps1"
    $filesystemHelpersPath = "$PSScriptRoot/../TestHelpers/FileSystemHelpers.ps1"

    if (Test-Path $databaseHelpersPath) {
        . $databaseHelpersPath
    }
    if (Test-Path $filesystemHelpersPath) {
        . $filesystemHelpersPath
    }
}

Describe "End-to-End FileHashDatabase Workflow" -Tag "Integration", "E2E", "Workflow" {
    BeforeAll {
        # Set up test environment
        $script:testDbPath = Join-Path $TestDrive "e2e_workflow.db"
        $script:testRoot = Join-Path $TestDrive "test_files"
        $script:duplicatesPath = Join-Path $TestDrive "duplicates"

        # Create test directory structure
        New-Item -Path $script:testRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $script:duplicatesPath -ItemType Directory -Force | Out-Null

        # Create subdirectories for testing
        $script:subDir1 = Join-Path $script:testRoot "subdir1"
        $script:subDir2 = Join-Path $script:testRoot "subdir2"
        $script:subDir3 = Join-Path $script:testRoot "nested" | Join-Path -ChildPath "deep"

        New-Item -Path $script:subDir1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:subDir2 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:subDir3 -ItemType Directory -Force | Out-Null

        # Define test content for duplicates
        $script:duplicateContent = @"
This is duplicate content that will be shared across multiple files.
It contains various characters and formatting to test hash computation.
The content should be identical across all duplicate files.
"@

        # Create test files with different content
        $script:testFiles = @{
            # Unique files
            "unique1.txt" = "This is unique content for file 1"
            "unique2.txt" = "This is unique content for file 2"
            "unique3.txt" = "This is unique content for file 3"

            # Duplicate files (same content, different locations)
            "duplicate1.txt" = $script:duplicateContent
            "duplicate2.txt" = $script:duplicateContent
            "duplicate3.txt" = $script:duplicateContent

            # Additional unique files
            "unique4.txt" = "Another unique file with different content"
            "unique5.txt" = "Yet another unique file for testing"
        }

        # Create files in different directories
        $script:createdFiles = @()

        Write-Debug "Creating test files..."

        # Root directory files
        Write-Debug "Creating root directory files"
        $script:createdFiles += New-TestFile -Path (Join-Path $script:testRoot "unique1.txt") -Content $script:testFiles["unique1.txt"]
        $script:createdFiles += New-TestFile -Path (Join-Path $script:testRoot "duplicate1.txt") -Content $script:testFiles["duplicate1.txt"]

        # Subdirectory 1 files
        Write-Debug "Creating subdirectory 1 files"
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir1 "unique2.txt") -Content $script:testFiles["unique2.txt"]
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir1 "duplicate2.txt") -Content $script:testFiles["duplicate2.txt"]

        # Subdirectory 2 files
        Write-Debug "Creating subdirectory 2 files"
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir2 "unique3.txt") -Content $script:testFiles["unique3.txt"]
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir2 "unique4.txt") -Content $script:testFiles["unique4.txt"]

        # Deep nested directory file
        Write-Debug "Creating deep nested directory files"
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir3 "duplicate3.txt") -Content $script:testFiles["duplicate3.txt"]
        $script:createdFiles += New-TestFile -Path (Join-Path $script:subDir3 "unique5.txt") -Content $script:testFiles["unique5.txt"]

        Write-Debug "File creation completed"
        Write-Host "Created $($script:createdFiles.Count) test files across multiple directories"
        Write-Host "Files created:"
        foreach ($file in $script:createdFiles) {
            Write-Host "  - $($file.FullName)"
            Write-Host "    Size: $($file.Length) bytes"
            Write-Host "    Content hash: $((Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash)"
        }
        Write-Host "Test root: $script:testRoot"
        Write-Host "Duplicates folder: $script:duplicatesPath"

        # Verify all files exist and have content
        Write-Debug "Verifying all created files exist"
        foreach ($file in $script:createdFiles) {
            $exists = Test-Path $file.FullName
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            Write-Debug "File $($file.Name) - Exists: $exists, Content length: $($content.Length)"
        }

        # Scan all files into the database during setup
        Write-Debug "Scanning files into database during setup"
        Write-FileHashRecord -ScanDirectory $script:testRoot -DatabasePath $script:testDbPath -Recurse -InterfilePauseSeconds 0
        Write-Debug "File scan completed during setup"
    }

    AfterAll {
        # Clean up test files
        if (Test-Path $script:testRoot) {
            Remove-Item -Path $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:duplicatesPath) {
            Remove-Item -Path $script:duplicatesPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $script:testDbPath) {
            Remove-Item -Path $script:testDbPath -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Complete End-to-End Workflow" {
        It "Should scan files and compute hashes successfully" {
            Write-Debug "Starting file scan verification test"
            Write-Debug "Test database path: $script:testDbPath"
            Write-Debug "Test root directory: $script:testRoot"
            Write-Debug "Test root exists: $(Test-Path $script:testRoot)"
            Write-Debug "Files in test root: $(Get-ChildItem $script:testRoot -Recurse -File | ForEach-Object { $_.FullName })"

            # Verify that files were scanned during setup
            Write-Debug "Verifying files were scanned during setup"

            # Verify database was created
            Write-Debug "Checking if database file exists"
            Test-Path $script:testDbPath | Should -Be $true
            Write-Debug "Database file exists: $(Test-Path $script:testDbPath)"
            Write-Debug "Database file size: $((Get-Item $script:testDbPath -ErrorAction SilentlyContinue).Length) bytes"

            # Print Algorithm table contents
            Write-Debug "Importing PSSQLite module"
            Import-Module PSSQLite
            Write-Debug "Querying Algorithm table"
            $algos = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT * FROM Algorithm"
            Write-Host "Algorithm table after scan:"
            $algos | Format-Table
            Write-Debug "Algorithm table has $($algos.Count) records"

            # Verify all files were processed by checking database directly
            Write-Debug "Querying FileHash table count"
            $fileHashCount = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as Count FROM FileHash"
            Write-Debug "FileHash table count query result: $($fileHashCount | ConvertTo-Json -Depth 3)"
            $fileHashCount.Count | Should -Be 8
            Write-Host "Successfully processed $($fileHashCount.Count) files"

            # Additional debugging: Show all FileHash records
            Write-Debug "Querying all FileHash records"
            $allFileHashes = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT * FROM FileHash ORDER BY FilePath"
            Write-Debug "All FileHash records:"
            $allFileHashes | Format-Table
        }

        It "Should identify duplicate files correctly" {
            Write-Debug "Starting duplicate identification test"
            Write-Debug "Database path: $script:testDbPath"
            Write-Debug "Database exists: $(Test-Path $script:testDbPath)"

            # Get hash records using the module function
            Write-Debug "Calling Get-FileHashRecord"
            $hashRecords = Get-FileHashRecord -DatabasePath $script:testDbPath

            Write-Debug "Get-FileHashRecord returned $($hashRecords.Count) records"
            Write-Host "Get-FileHashRecord returned: $($hashRecords | ConvertTo-Json -Depth 3)"

            # Should have at least one duplicate group
            Write-Debug "Filtering for duplicate records (Count > 1)"
            $duplicateRecords = $hashRecords | Where-Object { $_.Count -gt 1 }
            Write-Debug "Found $($duplicateRecords.Count) duplicate records"
            Write-Debug "Duplicate records: $($duplicateRecords | ConvertTo-Json -Depth 3)"
            $duplicateRecords | Should -Not -BeNullOrEmpty

            # Find the group with 3 files (our duplicate content)
            Write-Debug "Looking for group with exactly 3 files"
            Write-Debug "All duplicate records: $($duplicateRecords | ConvertTo-Json -Depth 3)"
            $threeFileGroups = @($duplicateRecords | Where-Object { $_.Count -eq 3 })
            Write-Debug "Found $($threeFileGroups.Count) groups with 3 files"
            Write-Debug "Three file groups: $($threeFileGroups | ConvertTo-Json -Depth 3)"
            $threeFileGroups | Should -Not -BeNullOrEmpty

            # Verify we have exactly one group with 3 files
            Write-Debug "Verifying we have exactly one group with 3 files"
            Write-Debug "threeFileGroups type: $($threeFileGroups.GetType().Name)"
            Write-Debug "threeFileGroups is array: $($threeFileGroups -is [array])"
            Write-Debug "threeFileGroups Count property: $($threeFileGroups.Count)"
            $threeFileGroups.Count | Should -Be 1 -Because "Should have exactly one group with 3 duplicate files"
            Write-Debug "Verifying file count in the group"
            $threeFileGroups[0].Count | Should -Be 3 -Because "The duplicate group should contain exactly 3 files"

            # Verify all three duplicate files are present in the paths
            Write-Debug "Checking duplicate file paths"
            $duplicatePaths = $threeFileGroups[0].Paths
            Write-Debug "Duplicate paths: $($duplicatePaths -join ', ')"
            Write-Debug "Expected paths:"
            Write-Debug "  $(Join-Path $script:testRoot "duplicate1.txt")"
            Write-Debug "  $(Join-Path $script:subDir1 "duplicate2.txt")"
            Write-Debug "  $(Join-Path $script:subDir3 "duplicate3.txt")"

            $duplicatePaths | Should -Contain (Join-Path $script:testRoot "duplicate1.txt")
            $duplicatePaths | Should -Contain (Join-Path $script:subDir1 "duplicate2.txt")
            $duplicatePaths | Should -Contain (Join-Path $script:subDir3 "duplicate3.txt")

            Write-Host "Found duplicate group with hash: $($threeFileGroups[0].Hash.Hash)"
            Write-Host "Duplicate files: $($duplicatePaths -join ', ')"

            # Store the duplicate hash for later tests
            $script:originalDuplicateHash = $threeFileGroups[0].Hash
        }

        It "Should move duplicate files to staging folder while preserving one" {
            # Step 2: Move duplicate files to staging folder
            { Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $script:duplicatesPath -InterfilePauseSeconds 0 } | Should -Not -Throw

            # Verify duplicates folder was created (if it didn't exist)
            Test-Path $script:duplicatesPath | Should -Be $true

            # Check that exactly 2 files were moved (3 duplicates - 1 preserved = 2 moved)
            $movedFiles = Get-ChildItem -Path $script:duplicatesPath -Recurse -File
            $movedFiles.Count | Should -Be 2

            # Verify that one duplicate file remains in its original location
            $remainingDuplicates = @(
                (Join-Path $script:testRoot "duplicate1.txt"),
                (Join-Path $script:subDir1 "duplicate2.txt"),
                (Join-Path $script:subDir3 "duplicate3.txt")
            )

            $remainingCount = 0
            foreach ($path in $remainingDuplicates) {
                if (Test-Path $path) {
                    $remainingCount++
                }
            }
            $remainingCount | Should -Be 1

            Write-Host "Moved $($movedFiles.Count) duplicate files to staging folder"
            Write-Host "Preserved 1 duplicate file in original location"
        }

        It "Should maintain correct directory structure in duplicates folder" {
            # Verify the moved files maintain their relative directory structure
            $movedFiles = Get-ChildItem -Path $script:duplicatesPath -Recurse -File

            # Should have files in subdirectories that mirror the original structure
            $subDirFiles = Get-ChildItem -Path $script:duplicatesPath -Directory -Recurse
            $subDirFiles.Count | Should -BeGreaterThan 0

            # Verify at least one file is in a subdirectory (not just root of duplicates)
            $filesInSubdirs = $movedFiles | Where-Object { $_.Directory.Name -ne "duplicates" }
            $filesInSubdirs.Count | Should -BeGreaterThan 0

            Write-Host "Maintained directory structure in duplicates folder"
        }

        It "Should preserve all unique files in their original locations" {
            # Verify all unique files remain in their original locations
            $uniqueFiles = @(
                (Join-Path $script:testRoot "unique1.txt"),
                (Join-Path $script:subDir1 "unique2.txt"),
                (Join-Path $script:subDir2 "unique3.txt"),
                (Join-Path $script:subDir2 "unique4.txt"),
                (Join-Path $script:subDir3 "unique5.txt")
            )

            foreach ($file in $uniqueFiles) {
                Test-Path $file | Should -Be $true -Because "Unique file should remain in original location: $file"
            }

            Write-Host "All unique files preserved in original locations"
        }

        It "Should update database records after moving duplicates" {
            Write-Debug "Starting database update verification test"
            Write-Debug "Database path: $script:testDbPath"
            Write-Debug "Database exists: $(Test-Path $script:testDbPath)"

            # Get updated records after moving duplicates using the module function
            Write-Debug "Calling Get-FileHashRecord to check database state"
            $updatedHashRecords = Get-FileHashRecord -DatabasePath $script:testDbPath

            Write-Debug "Get-FileHashRecord returned $($updatedHashRecords.Count) records"
            Write-Debug "Updated hash records: $($updatedHashRecords | ConvertTo-Json -Depth 3)"

            # After moving duplicates, we should have records for the remaining files
            # (5 unique files + 1 preserved duplicate = 6 files total)
            $updatedHashRecords | Should -Not -BeNullOrEmpty -Because "Database should contain records for remaining files"
            $updatedHashRecords.Count | Should -Be 6 -Because "Should have 6 files remaining (5 unique + 1 preserved duplicate)"

            # Find the preserved duplicate record (should have Count = 1)
            Write-Debug "Original duplicate hash: $($script:originalDuplicateHash.Hash)"

            # Find the preserved duplicate record (should have Count = 1 and same hash)
            $preservedDuplicate = $updatedHashRecords | Where-Object {
                $_.Hash.Hash -eq $script:originalDuplicateHash.Hash -and $_.Count -eq 1
            }
            Write-Debug "Found $($preservedDuplicate.Count) preserved duplicate records"

            # Should have exactly one preserved duplicate
            $preservedDuplicate | Should -Not -BeNullOrEmpty -Because "Should have one preserved duplicate file"
            $preservedDuplicate.Count | Should -Be 1 -Because "Should have exactly one preserved duplicate file"

            Write-Host "Database updated correctly after moving duplicates"
        }

        It "Should handle the complete workflow without errors" {
            # Verify the entire workflow completed successfully
            $finalFileCount = (Get-ChildItem -Path $script:testRoot -Recurse -File).Count
            $movedFileCount = (Get-ChildItem -Path $script:duplicatesPath -Recurse -File).Count

            # Should have 6 files remaining (5 unique + 1 preserved duplicate)
            $finalFileCount | Should -Be 6

            # Should have 2 files moved to duplicates folder
            $movedFileCount | Should -Be 2

            # Total should equal original count (8 files)
            ($finalFileCount + $movedFileCount) | Should -Be 8

            Write-Host "Complete workflow summary:"
            Write-Host "  - Files remaining in original locations: $finalFileCount"
            Write-Host "  - Files moved to duplicates folder: $movedFileCount"
            Write-Host "  - Total files processed: $($finalFileCount + $movedFileCount)"
        }
    }

    Context "Data Integrity and Verification" {
        It "Should maintain file content integrity after moving" {
            # Verify that moved files have the same content as the preserved file
            $preservedDuplicate = Get-ChildItem -Path $script:testRoot -Recurse -Filter "duplicate*.txt" | Select-Object -First 1
            $preservedContent = Get-Content $preservedDuplicate.FullName -Raw

            $movedFiles = Get-ChildItem -Path $script:duplicatesPath -Recurse -File
            foreach ($movedFile in $movedFiles) {
                $movedContent = Get-Content $movedFile.FullName -Raw
                $movedContent | Should -Be $preservedContent -Because "Moved file should have same content as preserved file"
            }

            Write-Host "File content integrity verified for all moved files"
        }

        It "Should have correct hash values for all files" {
            # Verify that all files have valid hash values using the module function
            $hashRecords = Get-FileHashRecord -DatabasePath $script:testDbPath

            foreach ($record in $hashRecords) {
                $record.Hash.Hash | Should -Not -BeNullOrEmpty -Because "All files should have valid hash values"
            }

            Write-Host "All files have valid hash values"
        }
    }

    Context "Error Handling and Edge Cases" {
        It "Should handle non-existent duplicates folder gracefully" {
            # Test with a non-existent destination folder
            $nonExistentDest = Join-Path $TestDrive "nonexistent_duplicates"

            { Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $nonExistentDest -InterfilePauseSeconds 0 } | Should -Not -Throw

            # Verify the folder was created
            Test-Path $nonExistentDest | Should -Be $true

            # Clean up
            Remove-Item -Path $nonExistentDest -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Should handle empty directories appropriately" {
            # Create an empty directory
            $emptyDir = Join-Path $TestDrive "empty_test"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            # Should not throw when scanning empty directory
            { Write-FileHashRecord -ScanDirectory $emptyDir -DatabasePath (Join-Path $TestDrive "empty_test.db") -InterfilePauseSeconds 0 } | Should -Not -Throw

            # Clean up
            Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
