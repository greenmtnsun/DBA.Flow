function Test-GERepositoryBusy {
    <#
    .SYNOPSIS
    Check whether the repository is in the middle of a multi-step Git operation.

    .DESCRIPTION
    Returns an object with IsBusy and Operations. Inspects the .git directory for sentinel files (MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_START, rebase-merge, rebase-apply) and reports which operations are in progress.

    .PARAMETER Path
    The folder to check. Defaults to the current location.

    .PARAMETER LogPath
    Optional diagnostic log path.

    .EXAMPLE
    $busy = Test-GERepositoryBusy
    if ($busy.IsBusy) { ... }

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

    $gitDirResult = Invoke-GEGit -ArgumentList @('rev-parse', '--git-dir') -WorkingDirectory $root -LogPath $LogPath
    $gitDir = $gitDirResult.Output | Select-Object -First 1

    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
        $gitDir = Join-Path $root $gitDir
    }

    $checks = @(
        @{ Name = 'merge';       Path = 'MERGE_HEAD' },
        @{ Name = 'cherry-pick'; Path = 'CHERRY_PICK_HEAD' },
        @{ Name = 'revert';      Path = 'REVERT_HEAD' },
        @{ Name = 'bisect';      Path = 'BISECT_START' },
        @{ Name = 'rebase';      Path = 'rebase-merge' },
        @{ Name = 'rebase';      Path = 'rebase-apply' }
    )

    $found = @()
    foreach ($check in $checks) {
        if (Test-Path -LiteralPath (Join-Path $gitDir $check.Path)) {
            $found += $check.Name
        }
    }

    [PSCustomObject]@{
        IsBusy     = ($found.Count -gt 0)
        Operations = @($found | Select-Object -Unique)
    }
}
