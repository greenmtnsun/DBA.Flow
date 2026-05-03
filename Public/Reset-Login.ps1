function Reset-Login {
    <#
    .SYNOPSIS
    Forget any saved login for the active project folder so it can be set up again.

    .DESCRIPTION
    Reset-Login asks the system to forget the saved login for the host that publishes your project. Use it when the saved login has gone stale (token rotated, password changed) or when GitEasy keeps using the wrong identity.

    Reset-Login tries every supported way to clear the saved login: it asks Git's credential layer to reject and erase the saved entry, and on Windows it also removes matching cmdkey entries. After Reset-Login, the next operation that needs a login will prompt for fresh credentials.

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

        if (-not $PSCmdlet.ShouldProcess($hostName, 'Forget cached login')) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        $clearedSomething = $false

        # Step 1: ask git's credential layer to reject the saved entry
        $rejectInput = @(
            'protocol=https'
            "host=$hostName"
            ''
        )

        $rejectOutput = $rejectInput | & git credential reject 2>&1
        $rejectExit = $LASTEXITCODE

        Add-GELogStep -Path $session.Path -Step "git credential reject (host=$hostName)" -ExitCode $rejectExit -Output @($rejectOutput | ForEach-Object { $_.ToString() })

        if ($rejectExit -eq 0) {
            $clearedSomething = $true
        }

        # Step 2: ask the credential manager to erase any cached entry (best-effort)
        try {
            $helperResult = Invoke-GEGit -ArgumentList @('config', '--global', '--get', 'credential.helper') -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
            $helperValue = ''
            if ($helperResult.ExitCode -eq 0) {
                $helperValue = $helperResult.Output | Select-Object -First 1
            }

            if ($helperValue -and ($helperValue -match 'manager')) {
                $eraseInput = "protocol=https`nhost=$hostName`n"
                $eraseOutput = $eraseInput | & git credential-manager erase 2>&1
                $eraseExit = $LASTEXITCODE

                Add-GELogStep -Path $session.Path -Step "git credential-manager erase (host=$hostName)" -ExitCode $eraseExit -Output @($eraseOutput | ForEach-Object { $_.ToString() })

                if ($eraseExit -eq 0) {
                    $clearedSomething = $true
                }
            }
        }
        catch {
            # Erase is best-effort - reject above is the primary path
        }

        # Step 3: remove matching cmdkey entries on Windows
        if (Get-Command cmdkey.exe -ErrorAction SilentlyContinue) {
            $cmdkeyTargets = @(
                "git:$hostName",
                "git:https://$hostName",
                "LegacyGeneric:target=git:https://$hostName",
                "LegacyGeneric:target=git:$hostName"
            )

            foreach ($target in $cmdkeyTargets) {
                $cmdOutput = & cmdkey.exe /delete:$target 2>&1
                $cmdExit = $LASTEXITCODE
                Add-GELogStep -Path $session.Path -Step "cmdkey /delete:$target" -ExitCode $cmdExit -Output @($cmdOutput | ForEach-Object { $_.ToString() })
            }

            $clearedSomething = $true
        }

        if (-not $clearedSomething) {
            throw "Could not find any saved-login storage to clear for $hostName."
        }

        $result = [PSCustomObject]@{
            Host    = $hostName
            Message = "Saved login for $hostName has been forgotten. Run Test-Login to be prompted again."
        }

        Write-Host "Saved login for $hostName has been forgotten."

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
