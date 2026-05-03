function Get-GECodeChange {
    <#
    .SYNOPSIS
    Return a structured summary of the active workspace state.

    .DESCRIPTION
    Reads git status --short and git diff --stat (both staged and unstaged) and assembles a single object describing the repository, the active working area, whether things are clean, and counts of staged, unstaged, and untracked changes. Find-CodeChange wraps this for the user.

    .PARAMETER Path
    The folder to query. Defaults to the current location.

    .EXAMPLE
    $state = Get-GECodeChange

    .NOTES
    Internal. Read-only.

    .LINK
    Find-CodeChange
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path
    )

    $root = Get-GERepoRoot -Path $Path
    $branch = Get-GEBranchName -Path $root
    $status = Invoke-GEGit -ArgumentList @('status', '--short') -WorkingDirectory $root -AllowFailure
    $diff = Invoke-GEGit -ArgumentList @('diff', '--stat') -WorkingDirectory $root -AllowFailure
    $stagedDiff = Invoke-GEGit -ArgumentList @('diff', '--cached', '--stat') -WorkingDirectory $root -AllowFailure

    $statusLines = @($status.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $diffLines = @($diff.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $stagedDiffLines = @($stagedDiff.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $untracked = @($statusLines | Where-Object { $_ -like '??*' })
    $staged = @($statusLines | Where-Object { $_.Length -ge 1 -and $_.Substring(0, 1) -notin @(' ', '?') })
    $unstaged = @($statusLines | Where-Object { $_.Length -ge 2 -and $_.Substring(1, 1) -notin @(' ', '?') })

    return [PSCustomObject]@{
        Repository     = $root
        Branch         = $branch
        IsClean        = ($statusLines.Count -eq 0)
        ChangeCount    = $statusLines.Count
        StagedCount    = $staged.Count
        UnstagedCount  = $unstaged.Count
        UntrackedCount = $untracked.Count
        Status         = $statusLines
        DiffStat       = $diffLines
        StagedDiffStat = $stagedDiffLines
    }
}
