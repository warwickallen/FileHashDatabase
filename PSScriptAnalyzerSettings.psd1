@{
    # Custom PSScriptAnalyzer settings for FileHashDatabase
    # Configure rules to match our design choices
    Rules = @{
        PSUseSingularNouns = @{
            Enable = $false
        }
        PSAvoidUsingWriteHost = @{
            Enable = $false
        }
        PSUseProcessBlockForPipelineCommand = @{
            Enable = $false
        }
        PSAvoidDefaultValueForMandatoryParameter = @{
            Enable = $false
        }
    }
}