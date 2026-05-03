function Clear-Junk {
    <#
    .SYNOPSIS
    Find or remove ignored files in the active project folder.

    .DESCRIPTION
    Clear-Junk uses your project's `.gitignore` to identify files that are considered junk - build outputs, editor leftovers, temporary files, anything you have already declared as not worth saving. By default, Clear-Junk lists what would be removed but takes no action. Pass -Force to actually delete the listed files.

    Tracked files are never touched. Files that are untracked but not matched by `.gitignore` are not touched either; pass -Aggressive together with -Force to also remove those.

    Each invocation writes a self-contained diagnostic log file. Successful runs log silently; failures throw a plain-English message and point at the log file with the technical detail.

    .PARAMETER Force
    Actually remove the listed files. Without this switch, Clear-Junk only lists what it would remove.

    .PARAMETER Aggressive
    Together with -Force, also remove untracked files that are not matched by `.gitignore`. Without this, only ignored files are removed.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written.

    .EXAMPLE
    Clear-Junk

    .EXAMPLE
    Clear-Junk -Force

    .EXAMPLE
    Find-CodeChange; Clear-Junk; Find-CodeChange

    .NOTES
    Safety:
    - Default is a list-only dry run; never deletes without -Force.
    - Tracked files are never touched.
    - Use Set-Vault -WriteIgnoreList if you want a starter .gitignore for a fresh project.
    - Refuses to run during an unfinished merge, rebase, cherry-pick, revert, or bisect.

    .LINK
    Find-CodeChange

    .LINK
    Set-Vault

    .LINK
    Save-Work

    .LINK
    Undo-Changes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Aggressive,

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

    $session = Start-GELogSession -Command 'Clear-Junk' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = 'Could not scan for junk files.'

    try {
        Assert-GESafeSave -Path ([string]$repoRoot) -LogPath $session.Path | Out-Null

        if (-not $repoRoot) {
            $rootResult = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -LogPath $session.Path
            $repoRoot = $rootResult.Output | Select-Object -First 1
        }

        $cleanFlags = if ($Aggressive) { '-fdx' } else { '-fdX' }
        $dryFlags   = if ($Aggressive) { '-ndx' } else { '-ndX' }

        $dryResult = Invoke-GEGit -ArgumentList @('clean', $dryFlags) -WorkingDirectory $repoRoot -LogPath $session.Path
        $candidates = @($dryResult.Output | Where-Object { $_ -match '^Would remove\s+(.+)$' } | ForEach-Object { ($_ -replace '^Would remove\s+','').Trim() })

        if ($candidates.Count -eq 0) {
            Write-Host 'No junk files found.'
            $result = [PSCustomObject]@{
                Repository = $repoRoot
                Candidates = @()
                Removed    = 0
                Message    = 'No junk files found.'
            }
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS'
            return $result
        }

        if (-not $Force) {
            Write-Host "Found $($candidates.Count) junk file(s). Re-run with -Force to remove them:"
            foreach ($c in $candidates) {
                Write-Host "  $c"
            }
            $result = [PSCustomObject]@{
                Repository = $repoRoot
                Candidates = @($candidates)
                Removed    = 0
                Message    = "$($candidates.Count) candidate(s) found. Pass -Force to remove."
            }
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS'
            return $result
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Remove $($candidates.Count) junk file(s)")) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        Invoke-GEGit -ArgumentList @('clean', $cleanFlags) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null

        $verifyResult = Invoke-GEGit -ArgumentList @('clean', $dryFlags) -WorkingDirectory $repoRoot -LogPath $session.Path
        $remaining = @($verifyResult.Output | Where-Object { $_ -match '^Would remove\s+' }).Count
        $removed = $candidates.Count - $remaining

        Write-Host "Removed $removed junk file(s)."

        $result = [PSCustomObject]@{
            Repository = $repoRoot
            Candidates = @($candidates)
            Removed    = $removed
            Message    = "Removed $removed junk file(s)."
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
