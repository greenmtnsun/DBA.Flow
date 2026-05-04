function New-Release {
    <#
    .SYNOPSIS
    Mark the current saved point as a named release version.

    .DESCRIPTION
    New-Release creates a permanent, annotated marker at the current saved point - the GitEasy term for what Git calls an "annotated tag". Use it to stamp a release version (v1.0.0, v1.5.0, etc.) with a note that travels alongside the project.

    By default, New-Release also publishes the marker to the project's published location. Use -NoPush to keep it local. If a release of the same version already exists, New-Release refuses to overwrite unless you pass -Force.

    Each invocation writes a self-contained diagnostic log file. Successful runs log silently; failures throw a plain-English message and point at the log file with the technical detail.

    .PARAMETER Version
    The release version name. Conventional format is `v` followed by major.minor.patch (for example, `v1.5.0`), but any valid name is accepted.

    .PARAMETER Note
    A short message describing the release. Travels permanently with the marker; appears in `Show-Releases` output.

    .PARAMETER NoPush
    Create the release marker locally only. Do not publish.

    .PARAMETER Force
    Overwrite an existing release of the same version. Without -Force, New-Release refuses to clobber an existing release.

    .PARAMETER LogPath
    Override the directory where the diagnostic log for this run is written.

    .EXAMPLE
    New-Release -Version v1.5.0 -Note 'Phase 15 complete: ...'

    .EXAMPLE
    New-Release v1.5.0 'phase 15' -NoPush

    .EXAMPLE
    New-Release -Version v1.5.0 -Note 'corrected release note' -Force

    .NOTES
    Safety:
    - Refuses to run during an unfinished merge, rebase, cherry-pick, revert, or bisect.
    - Refuses to run while there are unfinished conflicts.
    - Refuses to overwrite an existing release without -Force.
    - Writes the release note without UTF-8 BOM.

    .LINK
    Show-Releases

    .LINK
    Save-Work

    .LINK
    Show-History
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Version,

        [Parameter(Mandatory, Position = 1)]
        [string]$Note,

        [Parameter()]
        [switch]$NoPush,

        [Parameter()]
        [switch]$Force,

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

    $session = Start-GELogSession -Command 'New-Release' -Repository ([string]$repoRoot) -LogPath $LogPath

    $userMessageOnFailure = "Could not create the release '$Version'."

    try {
        Assert-GESafeSave -Path ([string]$repoRoot) -LogPath $session.Path | Out-Null

        if (-not $repoRoot) {
            $rootResult = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel') -LogPath $session.Path
            $repoRoot = $rootResult.Output | Select-Object -First 1
        }

        $checkRef = Invoke-GEGit -ArgumentList @('check-ref-format', "refs/tags/$Version") -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
        if ($checkRef.ExitCode -ne 0) {
            throw "'$Version' is not a valid release name. Use letters, digits, dashes, slashes, underscores, and dots (for example, v1.5.0)."
        }

        $existCheck = Invoke-GEGit -ArgumentList @('rev-parse', '--verify', '--quiet', "refs/tags/$Version") -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
        $existsLocally = ($existCheck.ExitCode -eq 0)

        if ($existsLocally -and -not $Force) {
            throw "A release named '$Version' already exists. Use -Force to overwrite, or pick a different version name."
        }

        if (-not $PSCmdlet.ShouldProcess($repoRoot, "Create release '$Version'")) {
            Complete-GELogSession -Path $session.Path -Outcome 'SUCCESS' -UserMessage 'Skipped (WhatIf).'
            return
        }

        if ($existsLocally -and $Force) {
            Invoke-GEGit -ArgumentList @('tag', '-d', $Version) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null
        }

        $noteFile = Join-Path ([System.IO.Path]::GetTempPath()) ('GitEasyRelease_' + [guid]::NewGuid().ToString('N') + '.txt')

        try {
            [System.IO.File]::WriteAllText($noteFile, $Note, [System.Text.UTF8Encoding]::new($false))
            Invoke-GEGit -ArgumentList @('tag', '-a', $Version, '-F', $noteFile) -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null
        }
        finally {
            Remove-Item -LiteralPath $noteFile -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Created release '$Version'."

        $remoteName = ''
        if (-not $NoPush) {
            $remoteResult = Invoke-GEGit -ArgumentList @('remote') -WorkingDirectory $repoRoot -LogPath $session.Path -AllowFailure
            $remotes = @($remoteResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            if ($remotes.Count -eq 0) {
                Write-Host 'No published location is configured. Release marker is local only.'
            }
            else {
                if ($remotes -contains 'origin') { $remoteName = 'origin' } else { $remoteName = $remotes[0] }

                $userMessageOnFailure = "Could not publish the release '$Version'."

                $pushArgs = @('push', $remoteName, $Version)
                if ($Force) {
                    $pushArgs += '--force'
                }
                Invoke-GEGit -ArgumentList $pushArgs -WorkingDirectory $repoRoot -LogPath $session.Path | Out-Null

                Write-Host "Published release '$Version' to '$remoteName'."
            }
        }
        else {
            Write-Host 'Saved locally only - the release has not been published.'
        }

        $result = [PSCustomObject]@{
            Repository = $repoRoot
            Version    = $Version
            Note       = $Note
            Published  = (-not $NoPush -and -not [string]::IsNullOrWhiteSpace($remoteName))
            Message    = "Release '$Version' created."
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
