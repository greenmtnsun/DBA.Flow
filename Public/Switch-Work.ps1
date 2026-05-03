function Switch-Work {
    <#
    .SYNOPSIS
    Switch to another existing working area.

    .DESCRIPTION
    Switch-Work moves into a different existing working area. Use it to return to the main working area or to inspect a previous task's branch.

    The command refuses to switch when an unfinished merge, rebase, cherry-pick, revert, or bisect is in progress; when there are unfinished conflicts; or when there are unsaved changes that would be lost or carried into the destination. Save your work with Save-Work first, or use Save-Work -NoPush for a local checkpoint.

    Each invocation writes a self-contained diagnostic log file. Successful runs log silently; failures throw a plain-English message and point at the log file with the technical detail.

    .PARAMETER Name
    The name of the working area to switch into. Must already exist.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written.

    .EXAMPLE
    Switch-Work -Name main

    .EXAMPLE
    Find-CodeChange; Switch-Work -Name giteasy-v2-refresh

    .NOTES
    Safety:
    - Refuses to run during an unfinished merge, rebase, cherry-pick, revert, or bisect.
    - Refuses to run while there are unfinished conflicts.
    - Refuses to switch when there are unsaved changes in the active working area.
    - Refuses to switch into a working area that does not exist.

    .LINK
    New-WorkBranch

    .LINK
    Find-CodeChange

    .LINK
    Save-Work
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$LogPath = ''
    )

    $repoRoot = $null
    try {
        $rootProbe = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -AllowFailure
        if ($rootProbe.ExitCode -eq 0) {
            $repoRoot = $rootProbe.Output | Select-Object -First 1
        }
    }
    catch {
        $repoRoot = $null
    }

    $session = Start-GELogSession -Command 'Switch-Work' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = "Could not switch to working area '$Name'."

    try {
        Assert-GESafeSave -Path ([string]$repoRoot) -LogPath $session.Path | Out-Null

        if (-not $repoRoot) {
            $rootResult = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -LogPath $session.Path
            $repoRoot = $rootResult.Output | Select-Object -First 1
        }

        $existCheck = Invoke-GEGit -ArgumentList @('rev-parse', '--verify', '--quiet', "refs/heads/$Name") -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
        if ($existCheck.ExitCode -ne 0) {
            throw "No working area named '$Name' exists. Use New-WorkBranch to create one, or check Show-History for a list of existing names."
        }

        $statusResult = Invoke-GEGit -ArgumentList @('status', '--porcelain=v1') -WorkingDirectory $repoRoot -LogPath $session.Path
        $statusLines = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($statusLines.Count -gt 0) {
            throw "Cannot switch right now. There are unsaved changes in the active working area. Save them with Save-Work first, or use Save-Work -NoPush for a local checkpoint."
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Switch to working area '$Name'")) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        Invoke-GEGit -ArgumentList @('checkout', $Name) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null

        Write-Host "Switched to working area '$Name'."

        $result = [PSCustomObject]@{
            Repository = $repoRoot
            Branch     = $Name
            Message    = "Working area '$Name' is now active."
        }

        Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS'
        return $result
    }
    catch {
        $err = $_

        $innerMessage = $err.Exception.Message
        if ($innerMessage -like 'git *') {
            $finalMsg = $userMessageOnFailure
        }
        else {
            $finalMsg = $innerMessage
        }

        Complete-GELogSession -Path $session.Path -Outcome 'FAILURE' -UserMessage $finalMsg -ErrorMessage $innerMessage

        throw "$finalMsg Details: $($session.Path)"
    }
}
