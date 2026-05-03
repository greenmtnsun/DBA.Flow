function New-WorkBranch {
    <#
    .SYNOPSIS
    Start a new working area for an isolated task, fix, or doc change.

    .DESCRIPTION
    New-WorkBranch creates a new working area starting from the current point and switches to it. Use it when starting a new feature, a bug fix, or a documentation pass that should not mix with the active working area.

    The command refuses to start a new working area when an unfinished merge, rebase, cherry-pick, revert, or bisect is in progress, or when there are unfinished conflicts. It also rejects names that are not valid working-area identifiers (spaces, control characters, leading dashes, and similar) and refuses to overwrite a working area that already exists.

    Each invocation writes a self-contained diagnostic log file. Successful runs log silently; failures throw a plain-English message and point at the log file with the technical detail.

    .PARAMETER Name
    The name of the new working area. Must be a valid identifier (no spaces, no control characters, no leading dash, etc.).

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written. Defaults to %LOCALAPPDATA%\GitEasy\Logs.

    .EXAMPLE
    New-WorkBranch -Name fix-readme

    .EXAMPLE
    Find-CodeChange; New-WorkBranch -Name docs-refresh

    .NOTES
    Safety:
    - Refuses to run during an unfinished merge, rebase, cherry-pick, revert, or bisect.
    - Refuses to run while there are unfinished conflicts.
    - Refuses to overwrite an existing working area.
    - Validates the name through git check-ref-format.

    .LINK
    Switch-Work

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

    $session = Start-GELogSession -Command 'New-WorkBranch' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = "Could not start the new working area '$Name'."

    try {
        Assert-GESafeSave -Path ([string]$repoRoot) -LogPath $session.Path | Out-Null

        if (-not $repoRoot) {
            $rootResult = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -LogPath $session.Path
            $repoRoot = $rootResult.Output | Select-Object -First 1
        }

        $checkRef = Invoke-GEGit -ArgumentList @('check-ref-format', '--branch', $Name) -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
        if ($checkRef.ExitCode -ne 0) {
            throw "'$Name' is not a valid working-area name. Use letters, digits, dashes, slashes, underscores, and dots."
        }

        $existCheck = Invoke-GEGit -ArgumentList @('rev-parse', '--verify', '--quiet', "refs/heads/$Name") -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
        if ($existCheck.ExitCode -eq 0) {
            throw "A working area named '$Name' already exists. Use Switch-Work to move into it, or pick a different name."
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Create working area '$Name'")) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        Invoke-GEGit -ArgumentList @('checkout', '-b', $Name) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null

        Write-Host "Started new working area '$Name'."

        $result = [PSCustomObject]@{
            Repository = $repoRoot
            Branch     = $Name
            Message    = "Working area '$Name' created and active."
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
