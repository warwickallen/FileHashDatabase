# Import the module
try {
    $manifestPath = Join-Path $PSScriptRoot '..\FileHashDatabase\FileHashDatabase.psd1'
    Import-Module -Name $manifestPath -Force -ErrorAction Stop -Verbose
} catch {
    Write-Error "Failed to import FileHashDatabase module: $_"
    throw
}

# Verify PSSQLite is available
if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
    Write-Error "PSSQLite module is required. Install with: Install-Module PSSQLite"
    throw
}

# Verify class availability
if (-not ([System.Management.Automation.PSModuleInfo]::new($true)).GetExportedTypeDefinitions()['FileHashDatabase']) {
    Write-Warning "FileHashDatabase class not found in module scope. Ensure it is defined in Private/FileHashDatabase.ps1 and dot-sourced in FileHashDatabase.psm1."
}

Describe "Move-FileHashDuplicates Tests" {
    InModuleScope FileHashDatabase {
        BeforeAll {
            # Set up temporary database
            $script:dbPath = Join-Path $env:TEMP "TestFileHashes_$(Get-Random).db"
            Write-Debug "Creating temporary database at: $script:dbPath"
            $script:db = [FileHashDatabase]::new($script:dbPath)
            $script:stagingDir = "C:\Staging"
        }

        AfterAll {
            if (Test-Path -Path $script:dbPath) {
                Write-Debug "Removing temporary database: $script:dbPath"
                Remove-Item -Path $script:dbPath -Force -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            # Clear database tables
            $script:db.InvokeQuery("DELETE FROM FileHash", @{})
            $script:db.InvokeQuery("DELETE FROM MovedFile", @{})
            $script:movedFiles = @()
        }

        Context "Basic Functionality" {
            BeforeEach {
                $algorithm = 'SHA256'
                $hash1 = 'ABC123'
                $time1 = [DateTimeOffset]::Now.AddMinutes(-20).ToUnixTimeMilliseconds()
                $time2 = [DateTimeOffset]::Now.AddMinutes(-10).ToUnixTimeMilliseconds()
                $time3 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time1).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time2).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\file3.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time3).DateTime)
            }

            It "Moves duplicates with PreserveBy EarliestProcessed" {
                Mock Move-Item { $script:movedFiles += $args[0] } -Verifiable
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'EarliestProcessed'
                $script:movedFiles | Should -Not -Contain "C:\file1.txt"
                $script:movedFiles | Should -Contain "C:\file2.txt"
                $script:movedFiles | Should -Contain "C:\file3.txt"
                $movedRecords = $script:db.InvokeQuery("SELECT SourcePath FROM MovedFile", @{})
                $movedPaths = $movedRecords | ForEach-Object { $_.SourcePath }
                $movedPaths.Count | Should -Be 2
            }
        }

        Context "PreserveBy Criteria" {
            BeforeEach {
                $algorithm = 'SHA256'
                $hash1 = 'ABC123'
                $time1 = [DateTimeOffset]::Now.AddMinutes(-20).ToUnixTimeMilliseconds()
                $time2 = [DateTimeOffset]::Now.AddMinutes(-10).ToUnixTimeMilliseconds()
                $time3 = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm, "C:\short.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time1).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\longername.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time2).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\a\very\long\path\file.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time3).DateTime)
            }

            It "Preserves LongestName" {
                Mock Move-Item { $script:movedFiles += $args[0] }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'LongestName'
                $script:movedFiles | Should -Not -Contain "C:\longername.txt"
                $script:movedFiles | Should -Contain "C:\short.txt"
            }

            It "Preserves LongestPath" {
                Mock Move-Item { $script:movedFiles += $args[0] }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -PreserveBy 'LongestPath'
                $script:movedFiles | Should -Not -Contain "C:\a\very\long\path\file.txt"
            }
        }

        Context "Filtering" {
            BeforeEach {
                $algorithm1 = 'SHA256'
                $algorithm2 = 'MD5'
                $hash1 = 'ABC123'
                $hash2 = 'DEF456'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm1, "C:\DirA\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash($hash1, $algorithm1, "C:\DirA\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash($hash2, $algorithm2, "C:\DirB\file3.txt", 200, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
            }

            It "Filters by Algorithm" {
                Mock Move-Item { $script:movedFiles += $args[0] }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -Filter @{ individual = @("Algorithm = 'SHA256'") }
                $script:movedFiles.Count | Should -Be 1
                $script:movedFiles | Should -Not -Contain "C:\DirB\file3.txt"
            }
        }

        Context "Reprocess" {
            BeforeEach {
                $algorithm = 'SHA256'
                $hash1 = 'ABC123'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogMovedFile($hash1, $algorithm, "C:\file2.txt", "C:\Staging\file2.txt", (Get-Date))
            }

            It "Reprocesses moved files with -Reprocess" {
                Mock Move-Item { $script:movedFiles += $args[0] }
                Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\file2.txt" }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -Reprocess
                $script:movedFiles | Should -Contain "C:\file2.txt"
            }
        }

        Context "CopyMode" {
            BeforeEach {
                $algorithm = 'SHA256'
                $hash1 = 'ABC123'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
            }

            It "Copies instead of moves with -CopyMode" {
                Mock Copy-Item { $script:movedFiles += $args[0] }
                Mock Move-Item { throw "Move-Item should not be called" }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -CopyMode
                $script:movedFiles.Count | Should -Be 1
            }
        }

        Context "Error Handling" {
            BeforeEach {
                $algorithm = 'SHA256'
                $hash1 = 'ABC123'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash($hash1, $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash($hash1, $algorithm, "C:\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
            }

            It "Stops on error with HaltOnFailure $true" {
                Mock Move-Item { throw "Simulated error" }
                { Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -HaltOnFailure $true } | Should -Throw
            }

            It "Continues on error with HaltOnFailure $false" {
                Mock Move-Item { throw "Simulated error" }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256' -HaltOnFailure $false
                $movedRecords = $script:db.InvokeQuery("SELECT * FROM MovedFile", @{})
                $movedRecords.Count | Should -BeGreaterThan 0
            }
        }

        Context "Edge Cases" {
            It "Does nothing with no duplicates" {
                $algorithm = 'SHA256'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash('HASH1', $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                $script:db.LogFileHash('HASH2', $algorithm, "C:\file2.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                Mock Move-Item { $script:movedFiles += $args[0] }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256'
                $script:movedFiles.Count | Should -Be 0
            }

            It "Does nothing with single file" {
                $algorithm = 'SHA256'
                $time = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
                $script:db.LogFileHash('HASH1', $algorithm, "C:\file1.txt", 100, [DateTimeOffset]::FromUnixTimeMilliseconds($time).DateTime)
                Mock Move-Item { $script:movedFiles += $args[0] }
                Move-FileHashDuplicates -Destination $script:stagingDir -DatabasePath $script:dbPath -Algorithm 'SHA256'
                $script:movedFiles.Count | Should -Be 0
            }
        }
    }
}