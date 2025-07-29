#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Commits staged changes with a conventional commit message.

.DESCRIPTION
    This script helps create conventional commit messages for staged changes.
    It validates the commit message format and ensures proper PowerShell syntax.

.PARAMETER Type
    The conventional commit type (feat, fix, docs, style, refactor, perf, test, chore).

.PARAMETER Scope
    Optional scope for the commit (e.g., module, tests, build).

.PARAMETER Description
    Short description of the changes (max 50 characters including type and scope).

.PARAMETER Body
    Detailed description of the changes. Use actual line breaks for formatting.

.EXAMPLE
    .\Scripts\commit-staged.ps1 -Type "feat" -Description "add new validation function" -Body "Add comprehensive validation function for file hashes.

    This function validates SHA256 hashes and provides detailed error
    messages for invalid formats. Includes unit tests and documentation
    updates."

.EXAMPLE
    .\Scripts\commit-staged.ps1 -Type "fix" -Scope "tests" -Description "resolve module import failures" -Body "Fixed missing function exports and updated test expectations."
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'chore')]
    [string]$Type,

    [Parameter()]
    [string]$Scope,

    [Parameter(Mandatory)]
    [ValidateLength(1, 50)]
    [string]$Description,

    [Parameter()]
    [string]$Body
)

# Check if there are staged changes
$stagedFiles = git status --porcelain | Where-Object { $_.StartsWith('A ') -or $_.StartsWith('M ') -or $_.StartsWith('D ') }
if (-not $stagedFiles) {
    Write-Error "No staged changes found. Please stage files before committing."
    exit 1
}

# Build the header
$header = if ($Scope) {
    "$Type($Scope): $Description"
} else {
    "$Type`: $Description"
}

# Validate header length
if ($header.Length -gt 50) {
    Write-Error "Header is too long ($($header.Length) characters). Maximum is 50 characters."
    Write-Output "Current header: $header"
    exit 1
}

# Validate body line lengths if provided
if ($Body) {
    $lines = $Body -split "`n"
    foreach ($line in $lines) {
        if ($line.Length -gt 72) {
            Write-Warning "Body line is too long ($($line.Length) characters): $line"
        }
    }
}

# Show what will be committed
Write-Output "Staged files:"
git status --porcelain | Where-Object { $_.StartsWith('A ') -or $_.StartsWith('M ') -or $_.StartsWith('D ') } | ForEach-Object {
    $status = $_.Substring(0, 2).Trim()
    $file = $_.Substring(3)
    Write-Output "  $status $file"
}

Write-Output "`nCommit message:"
Write-Output "Header: $header"
if ($Body) {
    Write-Output "Body:"
    Write-Output $Body
}

# Confirm commit
$confirm = Read-Host "`nProceed with commit? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Output "Commit cancelled."
    exit 0
}

# Execute commit
try {
    if ($Body) {
        # Use Start-Process to properly handle newlines in the body
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            # Write the commit message to a temporary file
            $commitMessage = @"
$header

$Body
"@
            Set-Content -Path $tempFile -Value $commitMessage -Encoding UTF8

            # Use git commit with the message file
            git commit -F $tempFile
        }
        finally {
            # Clean up temporary file
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        git commit -m $header
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Output "`nCommit successful!"
        $commitHash = git rev-parse HEAD
        Write-Output "Commit hash: $commitHash"
    } else {
        Write-Error "Commit failed."
        exit 1
    }
} catch {
    Write-Error "Error during commit: $_"
    exit 1
}