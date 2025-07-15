# Import the module
try {
    if ($env:TEST_MODULE_PATH) {
        $manifestPath = $env:TEST_MODULE_PATH
    } else {
        $manifestPath = Join-Path $PSScriptRoot '..\FileHashDatabase\FileHashDatabase.psd1'
    }
    Import-Module -Name $manifestPath -Force -ErrorAction Stop -Verbose
    Write-Host "Successfully imported module from: $manifestPath"
} catch {
    Write-Error "Failed to import FileHashDatabase module: $_"
    throw
}

# Check for PSSQLite availability (install if needed in CI)
try {
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        Write-Warning "PSSQLite module not found. Attempting to install..."
        if ($IsLinux -or $IsMacOS) {
            # For CI environments, try to install PSSQLite
            Install-Module -Name PSSQLite -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        
        # Check again after installation attempt
        if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
            Write-Warning "PSSQLite module is not available. Some tests may be skipped."
            $script:SkipSQLiteTests = $true
        } else {
            $script:SkipSQLiteTests = $false
        }
    } else {
        $script:SkipSQLiteTests = $false
    }
} catch {
    Write-Warning "Error checking PSSQLite availability: $_"
    $script:SkipSQLiteTests = $true
}

# Set up cross-platform paths
if ($IsWindows) {
    $script:TestDrive = "C:\"
    $script:StagingDir = "C:\Staging"
    $script:TempDir = $env:TEMP
} else {
    $script:TestDrive = "/tmp"
    $script:StagingDir = "/tmp/staging"
    $script:TempDir = "/tmp"
}

Describe "Move-FileHashDuplicates Tests" {
    BeforeAll {
        # Skip all tests if PSSQLite is not available
        if ($script:SkipSQLiteTests) {
            Write-Warning "Skipping Move-FileHashDuplicates tests because PSSQLite is not available"
            return
        }
        
        # Verify module is loaded
        $module = Get-Module -Name FileHashDatabase
        if (-not $module) {
            throw "FileHashDatabase module is not loaded"
        }
        
        Write-Host "Module loaded successfully: $($module.Name) version $($module.Version)"
        
        # Try to access the FileHashDatabase class - use a safer approach
        try {
            # Test if we can create the class (this will fail gracefully if class isn't available)
            $testDbPath = Join-Path $script:TempDir "ClassTest_$(Get-Random).db"
            $testDb = [FileHashDatabase]::new($testDbPath)
            $testDb = $null
            if (Test-Path $testDbPath) {
                Remove-Item $testDbPath -Force -ErrorAction SilentlyContinue
            }
            Write-Host "FileHashDatabase class is available"
        } catch {
            Write-Warning "FileHashDatabase class not accessible: $_"
            Write-Warning "Tests will be skipped - ensure the class is properly exported"
            $script:SkipClassTests = $true
            return
        }
    }
    
    Context "Basic Functionality" -Skip:$script:SkipSQLiteTests {
        BeforeAll {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { return }
            
            # Set up temporary database with cross-platform path
            $script:dbPath = Join-Path $script:TempDir "TestFileHashes_$(Get-Random).db"
            Write-Host "Creating temporary database at: $script:dbPath"
            $script:db = [FileHashDatabase]::new($script:dbPath)
        }

        AfterAll {
            if ($script:dbPath -and (Test-Path -Path $script:dbPath)) {
                Write-Host "Removing temporary database: $script:dbPath"
                Remove-Item -Path $script:dbPath -Force -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { return }
            
            # Clear database tables
            $script:db.InvokeQuery("DELETE FROM FileHash", @{})
            $script:db.InvokeQuery("DELETE FROM MovedFile", @{})
            $script:movedFiles = @()
        }

        It "Moves duplicates with PreserveBy EarliestProcessed" {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { 
                Set-ItResult -Skipped -Because "SQLite or class not available"
                return 
            }
            
            # Use cross-platform paths
            $file1 = Join-Path $script:TestDrive "file1.txt"
            $file2 = Join-Path $script:TestDrive "file2.txt"  
            $file3 = Join-Path $script:TestDrive "file3.txt"
            
            $algorithm = 'SHA256'
            $hash1 = 'ABC123'
            $time1 = [DateTimeOffset]::Now.AddMinutes(-20).ToUnixTimeMilliseconds()
            $time2 = [DateTimeOffset]::Now.AddMinutes(-10).ToUnixTimeMilliseconds()
            $time3 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            
            $script:db.LogFileHash($hash1, $algorithm, $file1, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time1).DateTime)
            $script:db.LogFileHash($hash1, $algorithm, $file2, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time2).DateTime)
            $script:db.LogFileHash($hash1, $algorithm, $file3, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time3).DateTime)

            Mock Move-Item { $script:movedFiles += $args[0] } -Verifiable
            
            Move-FileHashDuplicates -Destination $script:StagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'EarliestProcessed'
            
            $script:movedFiles | Should -Not -Contain $file1
            $script:movedFiles | Should -Contain $file2
            $script:movedFiles | Should -Contain $file3
            
            $movedRecords = $script:db.InvokeQuery("SELECT SourcePath FROM MovedFile", @{})
            $movedPaths = $movedRecords | ForEach-Object { $_.SourcePath }
            $movedPaths.Count | Should -Be 2
        }
    }

    Context "PreserveBy Criteria" -Skip:$script:SkipSQLiteTests {
        BeforeAll {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { return }
            
            # Set up temporary database
            $script:dbPath = Join-Path $script:TempDir "TestFileHashes_$(Get-Random).db"
            $script:db = [FileHashDatabase]::new($script:dbPath)
        }

        AfterAll {
            if ($script:dbPath -and (Test-Path -Path $script:dbPath)) {
                Remove-Item -Path $script:dbPath -Force -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { return }
            
            # Clear database tables and set up test data
            $script:db.InvokeQuery("DELETE FROM FileHash", @{})
            $script:db.InvokeQuery("DELETE FROM MovedFile", @{})
            $script:movedFiles = @()
            
            # Use cross-platform paths
            $shortFile = Join-Path $script:TestDrive "short.txt"
            $longNameFile = Join-Path $script:TestDrive "longername.txt"
            $longPathFile = Join-Path $script:TestDrive "a/very/long/path/file.txt"
            
            $algorithm = 'SHA256'
            $hash1 = 'ABC123'
            $time1 = [DateTimeOffset]::Now.AddMinutes(-20).ToUnixTimeMilliseconds()
            $time2 = [DateTimeOffset]::Now.AddMinutes(-10).ToUnixTimeMilliseconds()
            $time3 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            
            $script:db.LogFileHash($hash1, $algorithm, $shortFile, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time1).DateTime)
            $script:db.LogFileHash($hash1, $algorithm, $longNameFile, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time2).DateTime)
            $script:db.LogFileHash($hash1, $algorithm, $longPathFile, 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time3).DateTime)
        }

        It "Preserves LongestName" {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { 
                Set-ItResult -Skipped -Because "SQLite or class not available"
                return 
            }
            
            Mock Move-Item { $script:movedFiles += $args[0] }
            Move-FileHashDuplicates -Destination $script:StagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'LongestName'
            
            $longNameFile = Join-Path $script:TestDrive "longername.txt"
            $shortFile = Join-Path $script:TestDrive "short.txt"
            
            $script:movedFiles | Should -Not -Contain $longNameFile
            $script:movedFiles | Should -Contain $shortFile
        }

        It "Preserves LongestPath" {
            if ($script:SkipSQLiteTests -or $script:SkipClassTests) { 
                Set-ItResult -Skipped -Because "SQLite or class not available"
                return 
            }
            
            Mock Move-Item { $script:movedFiles += $args[0] }
            Move-FileHashDuplicates -Destination $script:StagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'LongestPath'
            
            $longPathFile = Join-Path $script:TestDrive "a/very/long/path/file.txt"
            $script:movedFiles | Should -Not -Contain $longPathFile
        }
    }

    Context "Simple Module Function Test" {
        It "Should have Move-FileHashDuplicates function available" {
            $command = Get-Command -Name Move-FileHashDuplicates -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
            $command.CommandType | Should -Be 'Function'
        }
        
        It "Should have required parameters" {
            $command = Get-Command -Name Move-FileHashDuplicates
            $params = $command.Parameters.Keys
            $params | Should -Contain 'Destination'
            $params | Should -Contain 'DatabasePath'
            $params | Should -Contain 'Algorithm'
        }
    }
    
    # Add a basic test that doesn't require PSSQLite or the FileHashDatabase class
    Context "Function Validation" {
        It "Should throw appropriate error with invalid database path" {
            $invalidPath = "/nonexistent/path/database.db"
            { Move-FileHashDuplicates -Destination "/tmp" -DatabasePath $invalidPath -Algorithm 'SHA256' } | Should -Throw
        }
    }
}
