function Test-GERemoteUrlSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        throw 'Remote URL is required.'
    }

    if ($RemoteUrl -match '://[^/]+@') {
        throw 'Do not embed usernames, passwords, or tokens in the remote URL. Use a clean HTTPS URL and Git Credential Manager.'
    }

    if (($RemoteUrl -notmatch '^https://') -and ($RemoteUrl -notmatch '^git@[^:]+:.+$')) {
        throw "Remote URL must be HTTPS or SSH format: $RemoteUrl"
    }

    return $true
}
