function Set-Token {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string]$RemoteUrl,
        [string]$RemoteName = 'origin'
    )

    Test-GERemoteUrlSafe -RemoteUrl $RemoteUrl | Out-Null

    if ($RemoteUrl -notmatch '^https://') {
        throw 'Set-Token only accepts clean HTTPS remote URLs.'
    }

    $root = Get-GERepoRoot

    if (-not $PSCmdlet.ShouldProcess($root, "Set $RemoteName to HTTPS remote URL")) {
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
        Message    = 'HTTPS remote configured. Run Test-Login to validate credentials.'
    }
}
