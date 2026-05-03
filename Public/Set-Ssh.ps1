function Set-Ssh {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RemoteName = 'origin',
        [string]$RemoteUrl,
        [string]$LogPath = ''
    )

    $repoRoot = $null
    try { $repoRoot = Get-GERepoRoot } catch { $repoRoot = $null }

    $session = Start-GELogSession -Command 'Set-Ssh' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = 'Could not configure the SSH published location.'

    try {
        if (-not $repoRoot) {
            $repoRoot = Get-GERepoRoot
        }

        if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
            $currentUrl = Get-GERemoteUrl -RemoteName $RemoteName -Path $repoRoot

            if ([string]::IsNullOrWhiteSpace($currentUrl)) {
                throw "Remote '$RemoteName' is not configured. Provide -RemoteUrl."
            }

            $RemoteUrl = Convert-GERemoteToSsh -RemoteUrl $currentUrl
        }

        Test-GERemoteUrlSafe -RemoteUrl $RemoteUrl | Out-Null

        if ($RemoteUrl -notmatch '^git@[^:]+:.+$') {
            throw 'Set-Ssh requires an SSH remote URL or an existing HTTPS remote that can be converted.'
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Set $RemoteName to SSH remote URL")) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        $existing = Get-GERemoteUrl -RemoteName $RemoteName -Path $repoRoot

        if ([string]::IsNullOrWhiteSpace($existing)) {
            Invoke-GEGit -ArgumentList @('remote', 'add', $RemoteName, $RemoteUrl) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null
        }
        else {
            Invoke-GEGit -ArgumentList @('remote', 'set-url', $RemoteName, $RemoteUrl) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null
        }

        $result = [PSCustomObject]@{
            Repository = $repoRoot
            Remote     = $RemoteName
            Url        = $RemoteUrl
            Message    = 'SSH remote configured. Run Test-Login to validate access.'
        }

        Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS'
        return $result
    }
    catch {
        $err = $_
        $msg = if ($err.Exception.Message -like 'git *') { $userMessageOnFailure } else { $err.Exception.Message }
        Complete-GELogSession -Path $session.Path -Outcome 'FAILURE' -UserMessage $msg -ErrorMessage $err.Exception.Message
        throw "$msg Details: $($session.Path)"
    }
}
