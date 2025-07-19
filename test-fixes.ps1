# Test script to verify fixes
Write-Host "Testing FileHashDatabase module fixes..." -ForegroundColor Green

# Test 1: Check if module can be imported
try {
    Import-Module ./src/FileHashDatabase.psd1 -Force -ErrorAction Stop
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
} catch {
    Write-Host "✗ Module import failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 2: Check exported functions
$functions = Get-Command -Module FileHashDatabase
Write-Host "✓ Found $($functions.Count) exported functions: $($functions.Name -join ', ')" -ForegroundColor Green

# Test 3: Check for Invoke-Expression usage (should be fixed)
$invokeExpressionFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern "Invoke-Expression" -Quiet
if ($invokeExpressionFound) {
    Write-Host "✗ Invoke-Expression still found in code" -ForegroundColor Red
} else {
    Write-Host "✓ Invoke-Expression usage fixed" -ForegroundColor Green
}

# Test 4: Check for unused variable (should be fixed)
$unusedVariableFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern "\$fileName\s*=" -Quiet
if ($unusedVariableFound) {
    Write-Host "✗ Unused variable \$fileName still found" -ForegroundColor Red
} else {
    Write-Host "✓ Unused variable \$fileName fixed" -ForegroundColor Green
}

# Test 5: Check for unapproved verb (should be fixed)
$unapprovedVerbFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern "function Parameterize-Filters" -Quiet
if ($unapprovedVerbFound) {
    Write-Host "✗ Unapproved verb 'Parameterize' still found" -ForegroundColor Red
} else {
    Write-Host "✓ Unapproved verb 'Parameterize' fixed" -ForegroundColor Green
}

Write-Host "`nTest completed!" -ForegroundColor Green