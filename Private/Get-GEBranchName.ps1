function Get-GEBranchName {
    <#
    .SYNOPSIS
    Return the active working area name for the repository.

    .DESCRIPTION
    Tries git branch --show-current, falling back to git symbolic-ref --short HEAD. Throws when the repository is in a detached state.

    .PARAMETER Path
    The folder to query. Defaults to the current location.

    .EXAMPLE
    $branch = Get-GEBranchName

    .NOTES
    Internal. Read-only.

    .LINK
    Find-CodeChange
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)
    $root = Get-GERepoRoot -Path $Path
    $r = Invoke-GEGit -ArgumentList @('branch', '--show-current') -WorkingDirectory $root -AllowFailure
    $branch = $r.Output | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $r = Invoke-GEGit -ArgumentList @('symbolic-ref', '--short', 'HEAD') -WorkingDirectory $root -AllowFailure
        $branch = $r.Output | Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Unable to determine current branch. Repository may be detached or corrupt.'
    }
    $branch
}
