function Set-Token {
    <#
    .SYNOPSIS
    Configure or update the HTTPS published location for token-based login.

    .DESCRIPTION
    Set-Token registers an HTTPS published-location URL for the active project folder. It rejects URLs that embed credentials (like https://token@host/path) and only accepts clean HTTPS URLs, so secrets never end up in published configuration. Use this before Test-Login when first setting up a project against GitHub or GitLab over HTTPS.

    .PARAMETER RemoteUrl
    The HTTPS URL of the published location. Must start with https:// and must not embed a username, password, or token.

    .PARAMETER RemoteName
    The name of the published location to configure. Defaults to origin.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written. Defaults to %LOCALAPPDATA%\GitEasy\Logs.

    .EXAMPLE
    Set-Token -RemoteUrl 'https://github.com/example/repo.git'

    .EXAMPLE
    Set-Token -RemoteUrl 'https://gitlab.com/example/repo.git' -RemoteName origin

    .NOTES
    Safety:
    - Never paste tokens into the URL itself. Use a credential helper instead.
    - After Set-Token, run Test-Login to confirm authentication works.
    - Failures point at a log file with the full technical detail.

    .LINK
    Set-Vault

    .LINK
    Get-VaultStatus

    .LINK
    Test-Login

    .LINK
    Reset-Login
    #>
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
