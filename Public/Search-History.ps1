function Search-History {
    <#
    .SYNOPSIS
    Search saved-point history for a specific text.

    .DESCRIPTION
    Search-History finds every saved point in the active project that added or removed the text you give it. Useful for forensic questions like "when did the connection string change?" or "when was that function name dropped?"

    By default, Search-History returns structured objects (one per matching saved point), so you can pipe and filter. With -Patch, it includes the actual change text alongside each result.

    .PARAMETER Pattern
    The text to search for in the saved-point history. Plain text, not a regular expression.

    .PARAMETER Count
    The maximum number of matching saved points to return. Defaults to 50. Validated to the range 1-500.

    .PARAMETER Patch
    Include the change text (the lines that were added or removed) for each matching saved point.

    .EXAMPLE
    Search-History -Pattern 'DROP TABLE'

    .EXAMPLE
    Search-History -Pattern 'connection string' -Count 10

    .EXAMPLE
    Search-History -Pattern 'old-function-name' -Patch

    .NOTES
    Search-History looks at every saved point in history, not just recent ones, so it can be slow on very large projects. Use -Count to limit how many results to return.

    .LINK
    Show-History

    .LINK
    Find-CodeChange

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [ValidateRange(1, 500)]
        [int]$Count = 50,

        [switch]$Patch
    )

    $root = Get-GERepoRoot
    $delim = '<<<GE-SEARCH-DELIM>>>'

    $args = @('log', "-S$Pattern", "--max-count=$Count", '--date=short', "--pretty=format:$delim%h%x09%ad%x09%an%x09%s")
    if ($Patch) { $args += '--patch' }

    $r = Invoke-GEGit -ArgumentList $args -WorkingDirectory $root -AllowFailure

    if ($r.ExitCode -ne 0) {
        return @()
    }

    $output = ($r.Output -join "`n")
    $chunks = $output -split [regex]::Escape($delim)

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($chunk in $chunks) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }

        $lines = @($chunk -split "`n")
        $headerLine = $lines[0]
        $parts = @($headerLine -split "`t", 4)

        if ($parts.Count -lt 4) { continue }

        $entry = [PSCustomObject]@{
            Repository = $root
            Hash       = $parts[0].Trim()
            Date       = $parts[1].Trim()
            Author     = $parts[2].Trim()
            Message    = $parts[3].Trim()
        }

        if ($Patch -and $lines.Count -gt 1) {
            $patchText = ($lines[1..($lines.Count - 1)] -join "`n").Trim()
            Add-Member -InputObject $entry -NotePropertyName 'Change' -NotePropertyValue $patchText
        }

        $results.Add($entry)
    }

    return $results.ToArray()
}
