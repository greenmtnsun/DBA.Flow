function Get-GERepoRoot {
    <#
    .SYNOPSIS
    Return the absolute path to the root of the active Git repository.

    .DESCRIPTION
    Wraps git rev-parse --show-toplevel. Throws when the path is not inside a repository.

    .PARAMETER Path
    The folder to query. Defaults to the current location.

    .EXAMPLE
    $root = Get-GERepoRoot

    .NOTES
    Internal. Read-only. Many other GitEasy helpers depend on this.

    .LINK
    Find-CodeChange

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)
    Test-GEGitInstalled | Out-Null
    $r = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -WorkingDirectory $Path
    $root = $r.Output | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($root)) { throw 'Not inside a Git repository.' }
    $root
}
