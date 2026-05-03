function Reset-Login {
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
