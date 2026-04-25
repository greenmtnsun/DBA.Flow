function Set-Ssh {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RemoteName = 'origin',
        [string]$RemoteUrl
    )

    $root = Get-GERepoRoot

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        $currentUrl = Get-GERemoteUrl -RemoteName $RemoteName -Path $root

        if ([string]::IsNullOrWhiteSpace($currentUrl)) {
            throw "Remote '$RemoteName' is not configured. Provide -RemoteUrl."
        }

        $RemoteUrl = Convert-GERemoteToSsh -RemoteUrl $currentUrl
    }

    Test-GERemoteUrlSafe -RemoteUrl $RemoteUrl | Out-Null

    if ($RemoteUrl -notmatch '^git@[^:]+:.+$') {
        throw 'Set-Ssh requires an SSH remote URL or an existing HTTPS remote that can be converted.'
    }

    if (-not $PSCmdlet.ShouldProcess($root, "Set $RemoteName to SSH remote URL")) {
        return
    }

    $existing = Get-GERemoteUrl -RemoteName $RemoteName -Path $root

    if ([string]::IsNullOrWhiteSpace($existing)) {
        Invoke-GEGit -ArgumentList @('remote', 'add', $RemoteName, $RemoteUrl) -WorkingDirectory $root | Out-Null
    }
    else {
        Invoke-GEGit -ArgumentList @('remote', 'set-url', $RemoteName, $RemoteUrl) -WorkingDirectory $root | Out-Null
    }

    [PSCustomObject]@{
        Repository = $root
        Remote     = $RemoteName
        Url        = $RemoteUrl
        Message    = 'SSH remote configured. Run Test-Login to validate access.'
    }
}
