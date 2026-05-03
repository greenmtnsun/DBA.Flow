function Invoke-GEGit {
    <#
    .SYNOPSIS
    Run a Git command and return its exit code and output as separate stdout and stderr arrays.

    .DESCRIPTION
    Invoke-GEGit is the engine's single point of contact with Git. It captures stdout and stderr separately so that warnings (for example, LF/CRLF notices) do not poison parsed output. By default it throws when Git exits non-zero; -AllowFailure suppresses that and returns the result for the caller to inspect.

    Pass -LogPath to append a per-step record (command, exit code, stdout, stderr) to a diagnostic log file.

    .PARAMETER ArgumentList
    The Git command and its arguments, as a string array.

    .PARAMETER WorkingDirectory
    Where to run the command. Defaults to the current location.

    .PARAMETER AllowFailure
    Return the result instead of throwing when the exit code is non-zero.

    .PARAMETER LogPath
    Optional path to a diagnostic log file. When set, every call appends a step record.

    .EXAMPLE
    $r = Invoke-GEGit -ArgumentList @('rev-parse', '--show-toplevel')

    .EXAMPLE
    $r = Invoke-GEGit -ArgumentList @('push') -WorkingDirectory $root -LogPath $session.Path

    .NOTES
    Internal. Public commands route every Git call through this helper.

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [string]$WorkingDirectory = (Get-Location).Path,

        [switch]$AllowFailure,

        [string]$LogPath = ''
    )

    $previousLocation = Get-Location

    try {
        Set-Location -LiteralPath $WorkingDirectory

        $previousActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'

        $merged = & git @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE

        $ErrorActionPreference = $previousActionPreference
    }
    finally {
        $ErrorActionPreference = 'Stop'
        Set-Location -LiteralPath $previousLocation
    }

    $stdoutLines = New-Object System.Collections.Generic.List[string]
    $stderrLines = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($merged)) {
        if ($null -eq $entry) { continue }

        if ($entry -is [System.Management.Automation.ErrorRecord]) {
            $stderrLines.Add($entry.ToString())
        }
        else {
            $stdoutLines.Add($entry.ToString())
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $stepText = 'git ' + ($ArgumentList -join ' ')

        $logLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in $stdoutLines) {
            $logLines.Add($line)
        }
        foreach ($line in $stderrLines) {
            $logLines.Add('[stderr] ' + $line)
        }

        Add-GELogStep -Path $LogPath -Step $stepText -ExitCode $exitCode -Output $logLines
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        $combined = New-Object System.Collections.Generic.List[string]
        foreach ($line in $stdoutLines) { $combined.Add($line) }
        foreach ($line in $stderrLines) { $combined.Add($line) }

        throw ("git " + ($ArgumentList -join ' ') + " exited with code $exitCode" + [Environment]::NewLine + ($combined -join [Environment]::NewLine))
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($stdoutLines)
        Stderr   = @($stderrLines)
    }
}
