@{
    # Custom PSScriptAnalyzer settings for FileHashDatabase
    # Configure rules to match our design choices
    Rules = @{
        PSUseSingularNouns = @{
            Enable = $false
        }
        PSAvoidUsingWriteHost = @{
            Enable = $true
            # Allow Write-Host for progress display with backspace characters
            ExcludeRules = @(
                'Write-Host -NoNewline',
                'Write-Host -NoNewLine'
            )
        }
        PSUseProcessBlockForPipelineCommand = @{
            Enable = $true
        }
        PSAvoidDefaultValueForMandatoryParameter = @{
            Enable = $true
        }
    }
}