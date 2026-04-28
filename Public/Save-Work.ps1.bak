function Save-Work {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)] [string]$Message,
        [switch]$NoPush,
        [switch]$SetUpstream
    )

    $state = Assert-GESafeSave -NoPush:$NoPush -SetUpstream:$SetUpstream

    if ($state.Status.IsClean) {
        if ($NoPush) {
            Write-Host 'Nothing to save. Working tree is clean.'
            return
        }

        if (-not $PSCmdlet.ShouldProcess($state.Root, 'Push already-saved work')) {
            return
        }

        if ([string]::IsNullOrWhiteSpace($state.Upstream)) {
            if (-not $SetUpstream) {
                throw 'No upstream branch. Use Save-Work -SetUpstream or Save-Work -NoPush.'
            }

            Invoke-GEGit -ArgumentList @('push', '-u', 'origin', $state.Branch) -WorkingDirectory $state.Root | Out-Null
            Write-Host "Working tree was clean. Published branch $($state.Branch) and set upstream."
            return
        }

        Invoke-GEGit -ArgumentList @('push') -WorkingDirectory $state.Root | Out-Null
        Write-Host "Working tree was clean. Published existing commits on branch $($state.Branch)."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Save work $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    }

    if (-not $PSCmdlet.ShouldProcess($state.Root, 'Save work')) {
        return
    }

    Invoke-GEGit -ArgumentList @('add', '-A') -WorkingDirectory $state.Root | Out-Null
    Invoke-GEGit -ArgumentList @('commit', '-m', $Message) -WorkingDirectory $state.Root | Out-Null

    if (-not $NoPush) {
        if ([string]::IsNullOrWhiteSpace($state.Upstream)) {
            Invoke-GEGit -ArgumentList @('push', '-u', 'origin', $state.Branch) -WorkingDirectory $state.Root | Out-Null
        }
        else {
            Invoke-GEGit -ArgumentList @('push') -WorkingDirectory $state.Root | Out-Null
        }
    }

    Write-Host "Saved work on branch $($state.Branch)."
}
