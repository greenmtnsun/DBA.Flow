function Assert-GESafeSave {
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
