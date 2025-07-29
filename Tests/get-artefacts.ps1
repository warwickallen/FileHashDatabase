#!/usr/bin/env pwsh
#Requires -Version 5.1

param(
    [string]$RunId
)

if ([string]::IsNullOrEmpty($RunId)) {
    Write-Output "No run ID provided, searching for highest run folder in Tests/Artefacts"
    $artefactsRoot = Join-Path $repoDir "Tests\Artefacts"
    $runFolders = Get-ChildItem -Path $artefactsRoot -Directory -Filter 'run-*' | Where-Object { $_.Name -match '^run-\\d+$' }
    if ($runFolders.Count -eq 0) {
        throw "No run folders found in $artefactsRoot"
    }
    $highestRunFolder = $runFolders | Sort-Object { [int]($_.Name -replace '^run-', '') } -Descending | Select-Object -First 1
    $RunId = $highestRunFolder.Name -replace '^run-', ''
    Write-Output "Using highest run folder: $($highestRunFolder.Name) (RunId: $RunId)"
}

$artefacts = @(
    'quick-validation-results'
)

# Find repository root directory
$repoDir = Get-Location
while (-not (Test-Path (Join-Path $repoDir ".git"))) {
    $repoDir = Split-Path $repoDir -Parent
    if ([string]::IsNullOrEmpty($repoDir)) {
        throw "Could not find repository root directory"
    }
}

$artefactsDir = Join-Path $repoDir "Tests\Artefacts\run-$RunId"

# Create artefacts directory
New-Item -ItemType Directory -Path $artefactsDir -Force | Out-Null

foreach ($artefact in $artefacts) {
    Write-Output "Retrieving artefact: $artefact"
    gh run download $RunId --name $artefact --dir $artefactsDir
}

Write-Output "Artefacts downloaded to: $artefactsDir"