function Convert-GERemoteToSsh {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$RemoteUrl)

    if ($RemoteUrl -match '^git@[^:]+:.+$') {
        return $RemoteUrl
    }

    if ($RemoteUrl -notmatch '^https://(?<Host>[^/]+)/(?<Path>.+)$') {
        throw "Remote URL is not a recognized HTTPS Git URL: $RemoteUrl"
    }

    return "git@$($Matches.Host):$($Matches.Path)"
}
