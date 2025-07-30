<#
.SYNOPSIS
    A class that provides a visual pause indicator with animated dots.

.DESCRIPTION
    The PauseIndicator class displays a string of dots that are gradually overwritten
    using backspace and space characters while a predefined wait time elapses. This is
    used to provide visual feedback during long-running operations.

.PARAMETER Width
    The width of the pause indicator. Default is 128.

.PARAMETER DotCount
    The number of dots to display. Default is 64.

.PARAMETER TotalSeconds
    The total time in seconds over which the dots will be animated. Default is 20.

.EXAMPLE
    $indicator = [PauseIndicator]::new(10)
    $indicator.SetWidth(256)
    $indicator.SetDotCount(64)
    $indicator.Start("Processing file.txt")
    # ... do work ...
    $indicator.Complete("Completed")
#>

class PauseIndicator {
    [int]$Width
    [int]$DotCount
    [float]$TotalSeconds
    [int]$InterdotPauseMs
    [string]$Dots

    PauseIndicator([float]$TotalSeconds) {
        $this.SetWidth(128)
        $this.SetDotCount(64)
        $this.TotalSeconds = $TotalSeconds
        $this.InterdotPauseMs = [math]::Round(1000 * $this.TotalSeconds / $this.DotCount, 0)
    }

    [void]SetWidth([int]$Width) {
        $this.Width = $Width
    }

    [void]SetDotCount([int]$DotCount) {
        $this.DotCount = $DotCount
        $this.Dots = '.' * $this.DotCount
    }

    [void]Start([string]$Message) {
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $str_width = $this.Width - $this.DotCount - 17
        if ($str_width -lt 1) { $str_width = 1 }
        $str = if ($Message.Length -gt $str_width) {
            $Message.Substring(0, $str_width - 3) + "..."
        } else {
            $Message.PadRight($str_width)
        }
        Write-Host -NoNewline "$timestamp $str $($this.Dots)"
    }

    [void]Animate() {
        for ($i = $this.DotCount; $i -gt 0; $i--) {
            Start-Sleep -Milliseconds $this.InterdotPauseMs
            Write-Host -NoNewline "`b `b"
        }
    }

    [void]Complete([string]$Result) {
        Write-Host $Result
    }

    [void]Fail([string]$Result) {
        for ($i = $this.DotCount; $i -gt 0; $i--) {
            Write-Host -NoNewline "`b `b"
        }
        Write-Host $Result
    }
}