function Reset-Login {
    <#
    .SYNOPSIS
    Forget any saved login for the active project folder so it can be set up again.

    .DESCRIPTION
    Reset-Login asks the system credential helper to forget the saved login for the host of the active project folder. Use it when the saved login has gone stale (token rotated, password changed) or when GitEasy keeps using the wrong identity.

    Reset-Login currently supports HTTPS published locations only.

    .PARAMETER RemoteName
    The name of the published location whose login should be forgotten. Defaults to origin.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written.

    .EXAMPLE
    Reset-Login

    .EXAMPLE
    Reset-Login; Test-Login

    .NOTES
    Safety:
    - After Reset-Login, you may be prompted again for credentials on the next operation. That is expected.
    - Do not run during an active save or merge.
    - Always run Test-Login after Reset-Login before saving more work.

    .LINK
    Set-Token

    .LINK
    Set-Ssh

    .LINK
    Test-Login
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RemoteName = 'origin',
        [string]$LogPath = ''
    )

    $repoRoot = $null
    try { $repoRoot = Get-GERepoRoot } catch { $repoRoot = $null }

    $session = Start-GELogSession -Command 'Reset-Login' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = 'Could not refresh the saved login.'

    try {
        if (-not $repoRoot) {
            $repoRoot = Get-GERepoRoot
        }

        $remoteUrl = Get-GERemoteUrl -RemoteName $RemoteName -Path $repoRoot

        if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
            throw "Remote '$RemoteName' is not configured."
        }

        if ($remoteUrl -notmatch '^https://(?<Host>[^/]+)/') {
            throw "Reset-Login currently supports HTTPS remotes only. Current remote: $remoteUrl"
        }

        $hostName = $Matches.Host

        if (-not $PSCmdlet.ShouldProcess($hostName, 'Reject cached HTTPS credential')) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        $inputLines = @(
            'protocol=https'
            "host=$hostName"
            ''
        )

        $credOutput = $inputLines | & git credential reject 2>&1
        $credExit = $LASTEXITCODE

        Add-GELogStep -Path $session.Path -Step "git credential reject (host=$hostName)" -ExitCode $credExit -Output @($credOutput | ForEach-Object { $_.ToString() })

        if ($credExit -ne 0) {
            throw "Credential reject failed for host: $hostName"
        }

        $result = [PSCustomObject]@{
            Host    = $hostName
            Message = 'Saved login was rejected. Run Test-Login to be prompted again.'
        }

        Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS'
        return $result
    }
    catch {
        $err = $_
        $msg = if ($err.Exception.Message -like 'git *') { $userMessageOnFailure } else { $err.Exception.Message }
        Complete-GELogSession -Path $session.Path -Outcome 'FAILURE' -UserMessage $msg -ErrorMessage $err.Exception.Message
        throw "$msg Details: $($session.Path)"
    }
}
