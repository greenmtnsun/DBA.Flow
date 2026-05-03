function Complete-GELogSession {
    <#
    .SYNOPSIS
    Append the final outcome marker (SUCCESS or FAILURE) to a diagnostic log.

    .DESCRIPTION
    Closes the per-invocation log with a separator line, the outcome, and the finish time. Optionally records the user-facing message and the inner exception message for failures. Silently no-ops if the log file does not exist.

    .PARAMETER Path
    The log file path returned by Start-GELogSession.

    .PARAMETER Outcome
    Either SUCCESS or FAILURE.

    .PARAMETER UserMessage
    The plain-English message that the user saw (recorded for support).

    .PARAMETER ErrorMessage
    The inner technical exception message (recorded for support).

    .EXAMPLE
    Complete-GELogSession -Path $session.Path -Outcome SUCCESS

    .EXAMPLE
    Complete-GELogSession -Path $session.Path -Outcome FAILURE -UserMessage $msg -ErrorMessage $err

    .NOTES
    Internal. Append-only.

    .LINK
    Start-GELogSession

    .LINK
    Add-GELogStep
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('SUCCESS','FAILURE')]
        [string]$Outcome,

        [string]$UserMessage = '',

        [string]$ErrorMessage = ''
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $tail = New-Object System.Collections.Generic.List[string]
    $tail.Add('')
    $tail.Add(('=' * 60))
    $tail.Add("Outcome: $Outcome")
    $tail.Add("Finished UTC: $((Get-Date).ToUniversalTime().ToString('o'))")

    if (-not [string]::IsNullOrWhiteSpace($UserMessage)) {
        $tail.Add('')
        $tail.Add('User-facing message:')
        $tail.Add('  ' + $UserMessage)
    }

    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $tail.Add('')
        $tail.Add('Inner error:')
        foreach ($subLine in ($ErrorMessage -split "`r?`n")) {
            $tail.Add('  ' + $subLine)
        }
    }

    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $tail) {
        [void]$sb.AppendLine($l)
    }

    [System.IO.File]::AppendAllText(
        $Path,
        $sb.ToString(),
        [System.Text.UTF8Encoding]::new($false)
    )
}
