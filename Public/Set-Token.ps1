function Set-Token {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$RemoteUrl,
        [string]$RemoteName = 'origin',
        [string]$LogPath = ''
    )

    Test-GERemoteUrlSafe -RemoteUrl $RemoteUrl | Out-Null

    if ($RemoteUrl -notmatch '^https://') {
        throw 'Set-Token only accepts clean HTTPS remote URLs.'
    }

    $repoRoot = $null
    try { $repoRoot = Get-GERepoRoot } catch { $repoRoot = $null }

    $session = Start-GELogSession -Command 'Set-Token' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = 'Could not configure the published location.'

    try {
        if (-not $repoRoot) {
            $repoRoot = Get-GERepoRoot
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Set $RemoteName to HTTPS remote URL")) {
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
            Message    = 'HTTPS remote configured. Run Test-Login to validate credentials.'
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
