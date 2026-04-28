function Assert-GESafeSave {
    [CmdletBinding()]
    param()

    $RepositoryRoot = git rev-parse --show-toplevel 2>$null

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        throw 'Not currently inside a Git repository.'
    }

    $UnmergedFiles = @(git diff --name-only --diff-filter=U 2>$null)

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to check for unresolved merge conflicts.'
    }

    if ($UnmergedFiles.Count -gt 0) {
        $Message = 'Unresolved merge conflicts found. Fix these files before Save-Work: ' + ($UnmergedFiles -join ', ')
        throw $Message
    }

    return $true
}
