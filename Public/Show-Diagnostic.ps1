function Show-Diagnostic {
    <#
    .SYNOPSIS
    Open or list the diagnostic log files written by GitEasy.

    .DESCRIPTION
    Every GitEasy command writes a small log file describing exactly what happened during that run. Show-Diagnostic gives you a friendly way to find and open those logs without knowing where they live.

    With no parameters, Show-Diagnostic opens the most recent log in the default editor. With -List, it prints a table of recent logs with timestamps and sizes. With -All, it opens the logs folder in Explorer.

    .PARAMETER List
    Print a table of recent logs. Use with -Count to control how many.

    .PARAMETER All
    Open the logs folder in Explorer.

    .PARAMETER Count
    With -List, the maximum number of log entries to print. Defaults to 10.

    .PARAMETER LogPath
    Override the directory to look in. Defaults to %LOCALAPPDATA%\GitEasy\Logs and can be overridden site-wide through the GITEASY_LOG_PATH environment variable.

    .EXAMPLE
    Show-Diagnostic

    .EXAMPLE
    Show-Diagnostic -List

    .EXAMPLE
    Show-Diagnostic -List -Count 5

    .EXAMPLE
    Show-Diagnostic -All

    .NOTES
    Logs older than 30 days are automatically pruned each time a new log is written. To send a log to a colleague, attach the file directly - it is self-contained.

    .LINK
    Save-Work

    .LINK
    Test-Login
    #>
    [CmdletBinding(DefaultParameterSetName = 'Open')]
    param(
        [Parameter(ParameterSetName = 'List')]
        [switch]$List,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(ParameterSetName = 'List')]
        [int]$Count = 10,

        [Parameter()]
        [string]$LogPath
    )

    $logDirectory = Get-GELogPath -OverridePath $LogPath

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        Write-Host "No diagnostic logs yet. Folder will be created on first failure: $logDirectory"
        return
    }

    if ($All) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $logDirectory
        return
    }

    $allLogs = @(
        Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )

    if ($allLogs.Count -eq 0) {
        Write-Host "No diagnostic logs found in $logDirectory."
        return
    }

    if ($List) {
        $top = $allLogs | Select-Object -First $Count

        $rows = foreach ($log in $top) {
            [PSCustomObject]@{
                Name        = $log.Name
                LastWritten = $log.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                SizeKB      = [math]::Round($log.Length / 1KB, 2)
            }
        }

        return $rows
    }

    $mostRecent = $allLogs | Select-Object -First 1
    Write-Host "Opening: $($mostRecent.FullName)"

    Start-Process -FilePath $mostRecent.FullName
}
