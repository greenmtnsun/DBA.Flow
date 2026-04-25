function Get-GEProviderName {
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
