function Test-Login {
    <#
    .SYNOPSIS
    Verify that GitEasy can talk to the published location.

    .DESCRIPTION
    Test-Login checks whether the current login can read the published location for the active project folder. It reports the project, the active working area, the published location, the provider (GitHub, GitLab, or Other), and whether the connectivity test passed.

    Run Test-Login before publishing for the first time, after Set-Token or Set-Ssh, or any time Save-Work cannot publish.

    .PARAMETER RemoteName
    The name of the published location to test. Defaults to origin.

    .EXAMPLE
    Test-Login

    .EXAMPLE
    Show-Remote; Test-Login

    .NOTES
    A failed Test-Login should be fixed before running Save-Work. The returned object includes the technical exit code for follow-up.

    .LINK
    Set-Token

    .LINK
    Set-Ssh

    .LINK
    Reset-Login

    .LINK
    Show-Remote
    #>
    [CmdletBinding()]
    param(
        [string]$RemoteName = 'origin'
    )

    $root = Get-GERepoRoot
    $branch = Get-GEBranchName -Path $root
    $remoteUrl = Get-GERemoteUrl -RemoteName $RemoteName -Path $root
    $provider = Get-GEProviderName -RemoteUrl $remoteUrl

    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        return [PSCustomObject]@{
            Repository = $root
            Branch     = $branch
            Remote     = $RemoteName
            Provider   = $provider
            Url        = $null
            Passed     = $false
            ExitCode   = $null
            Message    = "Remote '$RemoteName' is not configured."
        }
    }

    $result = Invoke-GEGit -ArgumentList @('ls-remote', '--heads', $RemoteName) -WorkingDirectory $root -AllowFailure

    if ($result.ExitCode -eq 0) {
        $message = 'Remote login/connectivity test passed.'
    }
    else {
        $message = $result.Output -join [Environment]::NewLine
    }

    return [PSCustomObject]@{
        Repository = $root
        Branch     = $branch
        Remote     = $RemoteName
        Provider   = $provider
        Url        = $remoteUrl
        Passed     = ($result.ExitCode -eq 0)
        ExitCode   = $result.ExitCode
        Message    = $message
    }
}
