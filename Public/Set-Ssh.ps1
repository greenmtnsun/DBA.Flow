function Set-Ssh {
    <#
    .SYNOPSIS
    Configure or convert the published location to SSH-based access.

    .DESCRIPTION
    Set-Ssh sets the published location for the active project folder to an SSH URL. If you do not provide one, Set-Ssh reads the existing HTTPS URL and converts it to its SSH form (for example, https://github.com/example/repo.git becomes git@github.com:example/repo.git). Use it when SSH is preferred over HTTPS, or when corporate environments require key-based authentication.

    .PARAMETER RemoteName
    The name of the published location to configure. Defaults to origin.

    .PARAMETER RemoteUrl
    Optional SSH URL. If omitted, Set-Ssh converts the existing HTTPS URL.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written.

    .EXAMPLE
    Set-Ssh

    .EXAMPLE
    Set-Ssh -RemoteUrl 'git@github.com:example/repo.git'

    .NOTES
    Safety:
    - Do not commit private keys.
    - After Set-Ssh, run Test-Login to confirm key-based authentication works.
    - If SSH unexpectedly prompts for credentials, run Show-Remote and verify the URL.

    .LINK
    Test-Login

    .LINK
    Show-Remote

    .LINK
    Reset-Login
    #>
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
