@{
    # Suppress PSUseSingularNouns warnings for functions that intentionally use plural nouns
    Rules = @{
        PSUseSingularNouns = @{
            Enable = $true
            # Suppress warnings for specific function names that are intentionally plural
            ExcludeRules = @(
                'Get-FileHashes',
                'Convert-FiltersToParameters',
                'Move-FileHashDuplicates',
                'Write-FileHashes'
            )
        }
    }
}