function New-TestFileStructure {
    param(
        [string]$BasePath,
        [hashtable]$Structure
    )

    foreach ($item in $Structure.GetEnumerator()) {
        $itemPath = Join-Path $BasePath $item.Key

        if ($item.Value -is [hashtable]) {
            New-Item -Path $itemPath -ItemType Directory -Force
            New-TestFileStructure -BasePath $itemPath -Structure $item.Value
        } else {
            New-Item -Path $itemPath -ItemType Directory -Force
            foreach ($file in $item.Value) {
                $filePath = Join-Path $itemPath $file.Name
                $file.Content | Out-File -FilePath $filePath -Encoding UTF8
            }
        }
    }
}

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

function Get-TestFileHash {
    param(
        [string]$Path,
        [string]$Algorithm = "SHA256"
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    return (Get-FileHash -Path $Path -Algorithm $Algorithm).Hash
}

function Assert-FileExists {
    param([string]$Path)

    Test-Path $Path | Should -Be $true
}

function Assert-FileNotExists {
    param([string]$Path)

    Test-Path $Path | Should -Be $false
}

function New-DuplicateTestFiles {
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
