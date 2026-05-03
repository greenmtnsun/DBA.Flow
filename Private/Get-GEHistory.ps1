function Get-GEHistory {
    <#
    .SYNOPSIS
    Return recent saved points (commits) for the active repository.

    .DESCRIPTION
    Wraps git log with a tab-separated pretty format and returns one PSCustomObject per saved point with Hash, Date, Author, and Message fields. Show-History wraps this for the user.

    .PARAMETER Count
    Maximum number of saved points to return. Range 1-200. Defaults to 20.

    .PARAMETER Path
    The folder to query. Defaults to the current location.

    .EXAMPLE
    Get-GEHistory -Count 5

    .NOTES
    Internal. Read-only.

    .LINK
    Show-History
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 200)]
        [int]$Count = 20,

        [string]$Path = (Get-Location).Path
    )

    $root = Get-GERepoRoot -Path $Path
    $result = Invoke-GEGit -ArgumentList @('log', "--max-count=$Count", '--date=short', '--pretty=format:%h%x09%ad%x09%an%x09%s') -WorkingDirectory $root -AllowFailure

    if ($result.ExitCode -ne 0) {
        return @()
    }

    foreach ($line in @($result.Output)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = @($line -split "`t", 4)

        if ($parts.Count -eq 4) {
            [PSCustomObject]@{
                Repository = $root
                Hash       = $parts[0]
                Date       = $parts[1]
                Author     = $parts[2]
                Message    = $parts[3]
            }
        }
    }
}
