function Test-Login {
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
