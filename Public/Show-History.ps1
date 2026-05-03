function Show-History {
    <#
    .SYNOPSIS
    Show recent saved points in a readable form.

    .DESCRIPTION
    Show-History returns the most recent saved points (commits) for the active project folder, with the short identifier, date, author, and message for each. Run it after Save-Work to confirm the saved point was recorded, or any time you want to inspect recent work.

    .PARAMETER Count
    How many recent saved points to show. Defaults to 20. Validated to the range 1-200 so the output stays readable.

    .EXAMPLE
    Show-History

    .EXAMPLE
    Show-History -Count 5

    .NOTES
    A saved point in the history may still be local only if your active working area is ahead of the published version. Use Save-Work without -NoPush to publish, or check Find-CodeChange and Show-Remote to see the state.

    .LINK
    Save-Work

    .LINK
    Find-CodeChange

    .LINK
    Show-Remote
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 200)]
        [int]$Count = 20
    )

    $history = @(Get-GEHistory -Count $Count)

    if ($history.Count -eq 0) {
        return [PSCustomObject]@{
            Repository = Get-GERepoRoot
            Message    = 'No commit history found.'
        }
    }

    return $history
}
