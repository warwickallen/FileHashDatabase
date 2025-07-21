#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Test script to verify newline handling in commit messages.

.DESCRIPTION
    This script creates a test commit to verify that newlines are handled correctly.
    It demonstrates the proper way to handle newlines in PowerShell commit messages.
#>

Write-Host "Testing newline handling in commit messages..." -ForegroundColor Green

# Test message with newlines
$header = "test: verify newline handling"
$body = @"
This is a test commit message with multiple lines.

The first paragraph should be separated from the second paragraph
by a blank line. Each line should be properly word-wrapped to
stay within the 72-character limit.

This demonstrates proper newline handling in PowerShell.
"@

Write-Host "Header: $header" -ForegroundColor Cyan
Write-Host "Body:" -ForegroundColor Cyan
Write-Host $body -ForegroundColor White

# Create a temporary file for the commit message
$tempFile = [System.IO.Path]::GetTempFileName()
try {
    # Write the commit message to the temporary file
    $commitMessage = @"
$header

$body
"@
    Set-Content -Path $tempFile -Value $commitMessage -Encoding UTF8

    Write-Host "`nCommit message written to: $tempFile" -ForegroundColor Yellow
    Write-Host "Content preview:" -ForegroundColor Yellow
    Get-Content $tempFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    Write-Host "`nTo test the commit, run:" -ForegroundColor Green
    Write-Host "git commit -F `"$tempFile`"" -ForegroundColor Cyan

} catch {
    Write-Error "Error creating test commit message: $_"
} finally {
    # Note: We don't delete the temp file here so you can inspect it
    Write-Host "`nTemporary file preserved for inspection: $tempFile" -ForegroundColor Yellow
}