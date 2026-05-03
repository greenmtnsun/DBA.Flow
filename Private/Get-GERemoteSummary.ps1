function Get-GERemoteSummary {
    <#
    .SYNOPSIS
    Return the list of configured published locations with provider and purpose.

    .DESCRIPTION
    Parses git remote -v and returns one PSCustomObject per fetch/push entry, including Repository, Remote, Purpose (fetch or push), Provider (GitHub, GitLab, Other), and Url. Show-Remote wraps this for the user.

    .PARAMETER Path
    The folder to query. Defaults to the current location.

    .EXAMPLE
    Get-GERemoteSummary

    .NOTES
    Internal. Read-only.

    .LINK
    Show-Remote
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path
    )

    $root = Get-GERepoRoot -Path $Path
    $result = Invoke-GEGit -ArgumentList @('remote', '-v') -WorkingDirectory $root -AllowFailure

    if ($result.ExitCode -ne 0) {
        return @()
    }

    foreach ($line in @($result.Output)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^(?<Name>\S+)\s+(?<Url>\S+)\s+\((?<Purpose>fetch|push)\)$') {
            $remoteName = $Matches['Name']
            $remoteUrl = $Matches['Url']
            $purpose = $Matches['Purpose']
            $provider = Get-GEProviderName -RemoteUrl $remoteUrl

            [PSCustomObject]@{
                Repository = $root
                Remote     = $remoteName
                Purpose    = $purpose
                Provider   = $provider
                Url        = $remoteUrl
            }
        }
    }
}
