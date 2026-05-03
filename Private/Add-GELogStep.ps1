function Add-GELogStep {
    <#
    .SYNOPSIS
    Append one step record to an open diagnostic log file.

    .DESCRIPTION
    Each record contains the step name, exit code, optional note, and optional output lines. Output lines are written line by line, indented two spaces. Stderr output is conventionally prefixed [stderr]. The file is appended without a UTF-8 BOM. Silently no-ops if the log file does not exist.

    .PARAMETER Path
    The log file path returned by Start-GELogSession.

    .PARAMETER Step
    Friendly description of what was attempted (e.g. "git push").

    .PARAMETER ExitCode
    Numeric exit code from the operation.

    .PARAMETER Output
    Output lines (stdout, stderr, or both) to record.

    .PARAMETER Note
    Optional free-form note recorded under [note].

    .EXAMPLE
    Add-GELogStep -Path $session.Path -Step 'git push' -ExitCode 0 -Output $output

    .NOTES
    Internal. Append-only.

    .LINK
    Start-GELogSession

    .LINK
    Complete-GELogSession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Step,

        [int]$ExitCode = 0,

        [string[]]$Output = @(),

        [string]$Note = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("[step] $Step")
    $lines.Add("[exit] $ExitCode")

    if (-not [string]::IsNullOrWhiteSpace($Note)) {
        $lines.Add("[note] $Note")
    }

    if ($Output -and $Output.Count -gt 0) {
        $lines.Add('[out]')
        foreach ($line in $Output) {
            if ($null -eq $line) { continue }
            $text = $line.ToString()
            foreach ($subLine in ($text -split "`r?`n")) {
                $lines.Add('  ' + $subLine)
            }
        }
    }

    $lines.Add('')

    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $lines) {
        [void]$sb.AppendLine($l)
    }

    [System.IO.File]::AppendAllText(
        $Path,
        $sb.ToString(),
        [System.Text.UTF8Encoding]::new($false)
    )
}
