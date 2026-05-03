function Start-GELogSession {
    <#
    .SYNOPSIS
    Create a per-invocation diagnostic log file and return its path.

    .DESCRIPTION
    Writes the header (time, command, repository, working area, PowerShell version, GitEasy version) to a new file under the resolved log directory and returns a session object whose Path property points at the file. Prunes logs older than RetentionDays before writing the new one. Filename uses millisecond-precision UTC timestamp to avoid collisions when commands fire rapidly.

    .PARAMETER Command
    The friendly name of the public command (used in the filename and header).

    .PARAMETER Repository
    Optional repository path to record in the header.

    .PARAMETER Branch
    Optional working-area name to record in the header.

    .PARAMETER LogPath
    Explicit log directory override. See Get-GELogPath for resolution order.

    .PARAMETER RetentionDays
    Logs older than this many days are removed before writing. Defaults to 30.

    .EXAMPLE
    $session = Start-GELogSession -Command 'Save-Work' -Repository $root -Branch $branch

    .NOTES
    Internal. Touches the log directory.

    .LINK
    Add-GELogStep

    .LINK
    Complete-GELogSession

    .LINK
    Show-Diagnostic
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [string]$Repository = '',

        [string]$Branch = '',

        [string]$LogPath,

        [int]$RetentionDays = 30
    )

    $logDirectory = Get-GELogPath -OverridePath $LogPath

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
    }

    Remove-GEOldLog -Directory $logDirectory -RetentionDays $RetentionDays -ErrorAction SilentlyContinue

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    $fileName = "$Command-$stamp.log"
    $filePath = Join-Path $logDirectory $fileName

    $moduleVersion = ''
    $module = Get-Module GitEasy | Select-Object -First 1
    if ($module) {
        $moduleVersion = $module.Version.ToString()
    }

    $headerLines = @(
        "GitEasy $Command session",
        ('=' * 60),
        "Time UTC:    $((Get-Date).ToUniversalTime().ToString('o'))",
        "Command:     $Command",
        "Repository:  $Repository",
        "Branch:      $Branch",
        "PowerShell:  $($PSVersionTable.PSVersion)",
        "GitEasy:     $moduleVersion",
        ''
    )

    [System.IO.File]::WriteAllLines(
        $filePath,
        $headerLines,
        [System.Text.UTF8Encoding]::new($false)
    )

    return [PSCustomObject]@{
        Path     = $filePath
        Command  = $Command
        Started  = (Get-Date).ToUniversalTime()
    }
}
