function Test-GEGitInstalled {
    <#
    .SYNOPSIS
    Throw if git is not on PATH.

    .DESCRIPTION
    Sanity check that the git executable is reachable. Returns $true on success; throws otherwise.

    .EXAMPLE
    Test-GEGitInstalled | Out-Null

    .NOTES
    Internal. Read-only.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git was not found in PATH.'
    }
    $true
}
