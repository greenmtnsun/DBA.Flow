function Convert-GERemoteToSsh {
    <#
    .SYNOPSIS
    Convert an HTTPS Git URL to its SSH form.

    .DESCRIPTION
    Translates https://host/path to git@host:path. Returns SSH URLs unchanged. Throws when the input is not a recognized HTTPS URL.

    .PARAMETER RemoteUrl
    The URL to convert.

    .EXAMPLE
    Convert-GERemoteToSsh -RemoteUrl 'https://github.com/example/repo.git'

    .NOTES
    Internal. Pure transformation. No I/O.

    .LINK
    Set-Ssh
    #>
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
