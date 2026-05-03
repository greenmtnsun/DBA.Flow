function Get-GEProviderName {
    <#
    .SYNOPSIS
    Classify a remote URL as GitHub, GitLab, Unknown, or None.

    .DESCRIPTION
    Pure pattern match on the URL. Used to surface a friendly provider name in Show-Remote and Test-Login output without exposing raw URLs.

    .PARAMETER RemoteUrl
    The URL to classify. Empty or null returns 'None'.

    .EXAMPLE
    Get-GEProviderName -RemoteUrl 'https://github.com/example/repo.git'

    .NOTES
    Internal. Pure transformation. No I/O.

    .LINK
    Show-Remote

    .LINK
    Test-Login
    #>
    [CmdletBinding()]
    param([string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        return 'None'
    }

    if ($RemoteUrl -match 'github\.com[:/]') {
        return 'GitHub'
    }

    if ($RemoteUrl -match 'gitlab\.com[:/]') {
        return 'GitLab'
    }

    return 'Unknown'
}
