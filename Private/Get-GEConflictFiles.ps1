function Get-GEConflictFiles {
    <#
    .SYNOPSIS
    Return the list of files with unresolved merge conflicts.

    .DESCRIPTION
    Runs git diff --name-only --diff-filter=U and returns the filenames as a string array. Returns an empty array if there are no conflicts. Stderr is captured separately by Invoke-GEGit so warnings do not appear as filenames.

    .PARAMETER Path
    The folder to check. Defaults to the current location.

    .PARAMETER LogPath
    Optional diagnostic log path.

    .EXAMPLE
    $conflicts = Get-GEConflictFiles
    if ($conflicts.Count -gt 0) { ... }

    .NOTES
    Internal. Read-only.

    .LINK
    Assert-GESafeSave
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path,
        [string]$LogPath = ''
    )

    $root = Get-GERepoRoot -Path $Path

    $r = Invoke-GEGit -ArgumentList @('diff', '--name-only', '--diff-filter=U') -WorkingDirectory $root -LogPath $LogPath -AllowFailure

    @($r.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
