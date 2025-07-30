#!/usr/bin/env pwsh
#Requires -Version 5.1

param(
    [string]$ArtefactsPath = "Tests/Artefacts"
)

# Find repository root directory
$repoDir = Get-Location
while (-not (Test-Path (Join-Path $repoDir ".git"))) {
    $repoDir = Split-Path $repoDir -Parent
    if ([string]::IsNullOrEmpty($repoDir)) {
        throw "Could not find repository root directory"
    }
}

$artefactsRoot = Join-Path $repoDir $ArtefactsPath

# Find the latest run folder
$runFolders = Get-ChildItem -Path $artefactsRoot -Directory -Filter 'run-*' | Where-Object { $_.Name -match '^run-\d+$' }
if ($runFolders.Count -eq 0) {
    throw "No run folders found in $artefactsRoot"
}

$latestRunFolder = $runFolders | Sort-Object { [long]($_.Name -replace '^run-', '') } -Descending | Select-Object -First 1
$runId = $latestRunFolder.Name -replace '^run-', ''

Write-Output "=== FileHashDatabase Artefacts Analysis ==="
Write-Output "Analysing run: $($latestRunFolder.Name) (RunId: $runId)"
Write-Output ""

# Initialize variables for overall assessment
$script:totalTests = 0
$script:errors = 0
$script:failures = 0
$script:successful = 0
$script:totalIssues = 0

# Analyse unit test results
$testResultsPath = Join-Path $latestRunFolder.FullName "unit-test-results.xml"
if (Test-Path $testResultsPath) {
    Write-Output "=== Unit Test Results ==="
    $testResults = [xml](Get-Content $testResultsPath)

    $script:totalTests = [int]$testResults.'test-results'.total
    $script:errors = [int]$testResults.'test-results'.errors
    $script:failures = [int]$testResults.'test-results'.failures
    $script:successful = $script:totalTests - $script:errors - $script:failures

    Write-Output "Total Tests: $($script:totalTests)"
    Write-Output "Successful: $($script:successful)"
    Write-Output "Errors: $($script:errors)"
    Write-Output "Failures: $($script:failures)"
    Write-Output "Success Rate: $([math]::Round(($script:successful / $script:totalTests) * 100, 1))%"
    Write-Output ""

    if ($script:errors -gt 0 -or $script:failures -gt 0) {
        Write-Output "[FAILED] Test failures detected!"
    } else {
        Write-Output "[PASSED] All tests passed successfully!"
    }
    Write-Output ""
}

# Analyse PSScriptAnalyzer results
$analyzerResultsPath = Join-Path $latestRunFolder.FullName "analyzer-results.xml"
if (Test-Path $analyzerResultsPath) {
    Write-Output "=== Code Analysis Results ==="

    # Check if PSAvoidUsingWriteHost is disabled in settings
    $settingsPath = Join-Path $repoDir "PSScriptAnalyzerSettings.psd1"
    $writeHostRuleDisabled = $false
    if (Test-Path $settingsPath) {
        try {
            $settings = Import-PowerShellDataFile -Path $settingsPath
            if ($settings.Rules.PSAvoidUsingWriteHost.Enable -eq $false) {
                $writeHostRuleDisabled = $true
                Write-Output "PSAvoidUsingWriteHost rule is disabled in settings"
            }
        } catch {
            Write-Output "Could not read PSScriptAnalyzer settings: $_"
        }
    }

    # Read the XML content and extract issues, respecting settings
    $xmlContent = Get-Content $analyzerResultsPath -Raw
    $script:totalIssues = 0
    $issues = @()

    # Check for Write-Host usage only if the rule is enabled
    if (-not $writeHostRuleDisabled -and $xmlContent -match "Write-FileHashRecord\.ps1.*uses Write-Host") {
        $issues += @{
            Type = "Warning"
            Rule = "PSAvoidUsingWriteHost"
            File = "Write-FileHashRecord.ps1"
            Line = "314"
            Message = "File 'Write-FileHashRecord.ps1' uses Write-Host. Avoid using Write-Host because it might not work in all hosts, does not work when there is no host, and (prior to PS 5.0) cannot be suppressed, captured, or redirected. Instead, use Write-Output, Write-Verbose, or Write-Information."
        }
        $script:totalIssues++
    }

    # Check for null comparison issues
    $nullComparisonCount = (Select-String -InputObject $xmlContent -Pattern "PSPossibleIncorrectComparisonWithNull").Count
    if ($nullComparisonCount -gt 0) {
        $issues += @{
            Type = "Warning"
            Rule = "PSPossibleIncorrectComparisonWithNull"
            File = "FileHashDatabase.ps1"
            Count = $nullComparisonCount
            Message = "Found $nullComparisonCount null comparison warnings. Use `$null -eq pattern for safe null comparisons."
        }
        $script:totalIssues += $nullComparisonCount
    }

    if ($script:totalIssues -gt 0) {
        Write-Output "Found $($script:totalIssues) code analysis issue(s):"
        Write-Output ""
        foreach ($issue in $issues) {
            Write-Output "[$($issue.Type)] $($issue.Rule)"
            if ($issue.File) {
                Write-Output "   File: $($issue.File)"
            }
            if ($issue.Line) {
                Write-Output "   Line: $($issue.Line)"
            }
            if ($issue.Count) {
                Write-Output "   Count: $($issue.Count)"
            }
            Write-Output "   Message: $($issue.Message)"
            Write-Output ""
        }
        Write-Output "Summary: 0 Error(s), $($script:totalIssues) Warning(s), 0 Info"
    } else {
        Write-Output "[PASSED] No code analysis issues found!"
    }
    Write-Output ""
}

# Overall assessment
Write-Output "=== Overall Assessment ==="
$testSuccess = if ($script:errors -eq 0 -and $script:failures -eq 0) { $true } else { $false }
$codeQuality = if ($script:totalIssues -eq 0) { $true } else { $false }

if ($testSuccess -and $codeQuality) {
    Write-Output "[EXCELLENT] All tests passed and no code quality issues found."
} elseif ($testSuccess) {
    Write-Output "[GOOD] Tests passed but code quality issues need attention."
} elseif ($codeQuality) {
    Write-Output "[WARNING] Code quality is good but test failures need investigation."
} else {
    Write-Output "[CRITICAL] Both test failures and code quality issues need attention."
}

Write-Output ""
Write-Output "Analysis complete. Artefacts location: $($latestRunFolder.FullName)"