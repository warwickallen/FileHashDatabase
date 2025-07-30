# Test script to verify fixes
Write-Output "Testing FileHashDatabase module fixes..."

# Test 1: Check if module can be imported
try {
    Import-Module ./src/FileHashDatabase.psd1 -Force -ErrorAction Stop
    Write-Output "[OK] Module imported successfully"
} catch {
    Write-Output "[KO] Module import failed: $($_.Exception.Message)"
    exit 1
}

# Test 2: Check exported functions
$functions = Get-Command -Module FileHashDatabase
Write-Output "[OK] Found $($functions.Count) exported functions: $($functions.Name -join ', ')"
# Test 3: Check for Invoke-Expression usage (should be fixed)
$invokeExpressionFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern "Invoke-Expression" -Quiet
if ($invokeExpressionFound) {
    Write-Output "[KO] Invoke-Expression still found in code"
} else {
    Write-Output "[OK] Invoke-Expression usage fixed"
}

# Test 4: Check for unused variable (should be fixed)
$unusedVariableFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern '\$fileName\s*=' -Quiet
if ($unusedVariableFound) {
    Write-Output '[KO] Unused variable "\$fileName" still found'
} else {
    Write-Output '[OK] Unused variable "\$fileName" fixed'
}

# Test 5: Check for unapproved verb (should be fixed)
$unapprovedVerbFound = Get-ChildItem -Path ./src -Recurse -Filter "*.ps1" |
    Select-String -Pattern "function Parameterize-Filter" -Quiet
if ($unapprovedVerbFound) {
    Write-Output "[KO] Unapproved verb 'Parameterize' still found"
} else {
    Write-Output "[OK] Unapproved verb 'Parameterize' fixed"
}

Write-Output "`nTest completed!"