BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "../../src/FileHashDatabase.psd1"
    Import-Module $ModulePath -Force
}

Describe "Simple End-to-End Test" -Tag "Integration", "Simple" {
    BeforeAll {
        $script:testDbPath = Join-Path $TestDrive "simple_test.db"
        $script:testDir = Join-Path $TestDrive "simple_files"
        $script:duplicatesPath = Join-Path $TestDrive "simple_duplicates"

        # Create test directory
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:duplicatesPath -ItemType Directory -Force | Out-Null

        # Create simple test files
        "Content A" | Out-File -FilePath (Join-Path $script:testDir "file1.txt") -Encoding UTF8
        "Content B" | Out-File -FilePath (Join-Path $script:testDir "file2.txt") -Encoding UTF8
        "Content A" | Out-File -FilePath (Join-Path $script:testDir "file3.txt") -Encoding UTF8  # Duplicate of file1
    }

    AfterAll {
        # Don't clean up immediately for debugging
        Write-Host "Test completed. Database location: $script:testDbPath"
        Write-Host "Test files location: $script:testDir"
        Write-Host "Duplicates location: $script:duplicatesPath"

        # Uncomment the following lines to clean up after debugging
        # if (Test-Path $script:testDir) {
        #     Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
        # }
        # if (Test-Path $script:duplicatesPath) {
        #     Remove-Item -Path $script:duplicatesPath -Recurse -Force -ErrorAction SilentlyContinue
        # }
        # if (Test-Path $script:testDbPath) {
        #     Remove-Item -Path $script:testDbPath -Force -ErrorAction SilentlyContinue
        # }
    }

    It "Should scan files and create database" {
        # Step 1: Scan files
        { Write-FileHashRecord -ScanDirectory $script:testDir -DatabasePath $script:testDbPath -InterfilePauseSeconds 0 } | Should -Not -Throw

        # Verify database was created
        Test-Path $script:testDbPath | Should -Be $true

        Write-Host "Database created successfully at: $script:testDbPath"
    }

    It "Should retrieve hash records from database" {
        # Step 2: Get hash records
        $records = Get-FileHashRecord -DatabasePath $script:testDbPath

        # Debug output
        Write-Host "Get-FileHashRecord returned: $($records | ConvertTo-Json -Depth 3)"

        # Debug: Check database directly
        Write-Host "Database path: $script:testDbPath"
        if (Test-Path $script:testDbPath) {
            Write-Host "Database exists!"
            Import-Module PSSQLite
            $tables = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT name FROM sqlite_master WHERE type='table'"
            Write-Host "Tables: $($tables.name -join ', ')"

            $views = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT name FROM sqlite_master WHERE type='view'"
            Write-Host "Views: $($views.name -join ', ')"

            $fileHashCount = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as Count FROM FileHash"
            Write-Host "FileHash records: $($fileHashCount.Count)"

            # Check actual FileHash data
            $fileHashData = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT * FROM FileHash LIMIT 3"
            Write-Host "FileHash data:"
            $fileHashData | Format-Table

            # Check Algorithm data
            $algorithmData = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT * FROM Algorithm"
            Write-Host "Algorithm data:"
            $algorithmData | Format-Table

            if ($views.name -contains 'DeduplicatedFile') {
                $dedupCount = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as Count FROM DeduplicatedFile"
                Write-Host "DeduplicatedFile records: $($dedupCount.Count)"
            } else {
                Write-Host "DeduplicatedFile view does not exist!"

                # Try to create the view manually
                Write-Host "Attempting to create view manually..."
                $createView = @"
CREATE VIEW IF NOT EXISTS DeduplicatedFile AS
SELECT
  fh.Hash
, a.AlgorithmName AS Algorithm
, GROUP_CONCAT(fh.FilePath, CHAR(10)) AS FilePaths
, COUNT(DISTINCT fh.FilePath) AS FileCount
, MAX(fh.FileSize) AS MaxFileSize
, MIN(fh.ProcessedAt) AS MinProcessedAt
, MAX(fh.ProcessedAt) AS MaxProcessedAt
, COUNT(*) AS RecordCount
FROM FileHash fh
JOIN Algorithm a ON fh.AlgorithmId = a.AlgorithmId
LEFT JOIN MovedFile mf ON fh.FilePath = mf.SourcePath AND mf.Hash IS NOT NULL
WHERE fh.Hash IS NOT NULL
  AND mf.SourcePath IS NULL
GROUP BY fh.Hash, fh.AlgorithmId
ORDER BY fh.Hash, a.AlgorithmName;
"@
                try {
                    Invoke-SqliteQuery -DataSource $script:testDbPath -Query $createView
                    Write-Host "View created manually!"

                    $dedupCount = Invoke-SqliteQuery -DataSource $script:testDbPath -Query "SELECT COUNT(*) as Count FROM DeduplicatedFile"
                    Write-Host "DeduplicatedFile records after manual creation: $($dedupCount.Count)"
                } catch {
                    Write-Host "Failed to create view manually: $_"
                }
            }
        } else {
            Write-Host "Database does not exist!"
        }

        # Should have records
        $records | Should -Not -BeNullOrEmpty

        # Should have 2 unique hash records (1 duplicate group + 1 unique file)
        $records.Count | Should -Be 2

        # Should have processed 3 files total
        $totalFiles = ($records | Measure-Object -Property Count -Sum).Sum
        $totalFiles | Should -Be 3

        Write-Host "Successfully retrieved $($records.Count) hash records with $totalFiles total files"
    }

    It "Should identify duplicates correctly" {
        $records = Get-FileHashRecord -DatabasePath $script:testDbPath

        # Find duplicate group (should have 2 files with same content)
        $duplicateGroup = $records | Where-Object { $_.Count -eq 2 }
        $duplicateGroup | Should -Not -BeNullOrEmpty

        Write-Host "Found duplicate group with $($duplicateGroup[0].Count) files"
    }

    It "Should move duplicate files" {
        # Step 3: Move duplicates
        { Move-FileHashDuplicate -DatabasePath $script:testDbPath -Destination $script:duplicatesPath -InterfilePauseSeconds 0 } | Should -Not -Throw

        # Should have moved 1 file (2 duplicates - 1 preserved = 1 moved)
        $movedFiles = Get-ChildItem -Path $script:duplicatesPath -Recurse -File
        $movedFiles.Count | Should -Be 1

        # Should have 2 files remaining (1 unique + 1 preserved duplicate)
        $remainingFiles = Get-ChildItem -Path $script:testDir -Recurse -File
        $remainingFiles.Count | Should -Be 2

        Write-Host "Moved $($movedFiles.Count) files, $($remainingFiles.Count) remaining"
    }
}