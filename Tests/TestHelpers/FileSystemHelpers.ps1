function New-TestFile {
    param(
        [string]$Path,
        [string]$Content = "Test content",
        [string]$Encoding = "UTF8"
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force
    }

    $Content | Out-File -FilePath $Path -Encoding $Encoding
    return Get-Item $Path
}

function Assert-FileExistence {
    param([string]$Path)

    Test-Path $Path | Should -Be $true
}

function Assert-FileNonExistence {
    param([string]$Path)

    Test-Path $Path | Should -Be $false
}

function New-DuplicateTestFile {
    param(
        [string]$BasePath,
        [string]$Content = "Duplicate content for testing",
        [int]$Count = 3
    )

    $files = @()
    for ($i = 1; $i -le $Count; $i++) {
        $filePath = Join-Path $BasePath "duplicate_file_$i.txt"
        $file = New-TestFile -Path $filePath -Content $Content
        $files += $file
    }

    return $files
}
