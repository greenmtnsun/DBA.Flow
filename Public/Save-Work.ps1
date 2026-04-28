function Save-Work {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message = 'Save work',

        [Parameter()]
        [switch]$NoPush
    )

    Assert-GESafeSave

    $StatusOutput = @(git status --porcelain)

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to read git status.'
    }

    if ($StatusOutput.Count -eq 0) {
        Write-Host 'No changes to save.'
        return
    }

    git add --all

    if ($LASTEXITCODE -ne 0) {
        throw 'git add failed.'
    }

    git commit -m $Message

    if ($LASTEXITCODE -ne 0) {
        throw 'git commit failed.'
    }

    $BranchName = git branch --show-current

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($BranchName)) {
        throw 'Unable to determine current branch.'
    }

    Write-Host "Saved work on branch $BranchName."

    if ($NoPush) {
        Write-Host 'NoPush requested. Skipping push.'
        return
    }

    git push

    if ($LASTEXITCODE -ne 0) {
        throw 'git push failed.'
    }
}
