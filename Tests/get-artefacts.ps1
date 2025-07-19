#!/usr/bin/env pwsh
#Requires -Version 5.1

param(
    [string]$RunId
)

if ([string]::IsNullOrEmpty($RunId)) {
    Write-Host "No run ID provided, using latest run"
    $RunId = gh run list --limit 1 --json databaseId --jq '.[0].databaseId'
    Write-Host "Using run ID: $RunId"
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
$latestLink = Join-Path $repoDir "Tests\Artefacts\latest"

# Create directory junction (Windows equivalent, doesn't require admin privileges)
if (Test-Path $latestLink) {
    Remove-Item $latestLink -Force -Recurse
}
New-Item -ItemType Junction -Path $latestLink -Target $artefactsDir -Force | Out-Null

# Create artefacts directory
New-Item -ItemType Directory -Path $artefactsDir -Force | Out-Null

foreach ($artefact in $artefacts) {
    Write-Host "Retrieving artefact: $artefact"
    gh run download $RunId --name $artefact --dir $artefactsDir
}

Write-Host "Artefacts downloaded to: $artefactsDir"
Write-Host "Latest artefacts are linked to: $latestLink"