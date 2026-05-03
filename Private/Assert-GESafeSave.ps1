function Assert-GESafeSave {
    <#
    .SYNOPSIS
    Throw a plain-English exception if it is not safe to save right now.

    .DESCRIPTION
    Assert-GESafeSave guards Save-Work against three failure modes: not being in a saveable workspace; an unfinished merge / rebase / cherry-pick / revert / bisect being in progress; and unfinished merge conflicts. It uses Test-GERepositoryBusy and Get-GEConflictFiles for those checks so the logic is single-sourced.

    .PARAMETER Path
    The folder to check. Defaults to the current location.

    .PARAMETER LogPath
    Optional diagnostic log path; passed through to inner Git calls.

    .EXAMPLE
    Assert-GESafeSave

    .NOTES
    Internal. Returns $true on success; throws plain-English on every failure.

    .LINK
    Save-Work

    .LINK
    Test-GERepositoryBusy

    .LINK
    Get-GEConflictFiles
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path,
        [string]$LogPath = ''
    )

    try {
        $root = Get-GERepoRoot -Path $Path
    }
    catch {
        throw 'This folder is not inside a saveable workspace. Move into your project folder first.'
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        throw 'This folder is not inside a saveable workspace. Move into your project folder first.'
    }

    $busy = Test-GERepositoryBusy -Path $root -LogPath $LogPath

    if ($busy.IsBusy) {
        $opList = ($busy.Operations -join ', ')
        throw "Cannot save right now. A $opList is in progress. Finish or cancel that first."
    }

    $conflicts = @(Get-GEConflictFiles -Path $root -LogPath $LogPath)

    if ($conflicts.Count -gt 0) {
        $list = ($conflicts -join ', ')
        throw "Cannot save while there are unfinished conflicts. Resolve these files first: $list"
    }

    return $true
}
