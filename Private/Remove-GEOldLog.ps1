function Remove-GEOldLog {
    <#
    .SYNOPSIS
    Delete diagnostic log files older than the retention threshold.

    .DESCRIPTION
    Removes only *.log files whose LastWriteTime is older than the cutoff. Recent files are never touched. No-ops when the directory does not exist or RetentionDays is zero or negative.

    .PARAMETER Directory
    The directory to prune.

    .PARAMETER RetentionDays
    Files older than this many days are removed. Defaults to 30.

    .EXAMPLE
    Remove-GEOldLog -Directory $logDir -RetentionDays 30

    .NOTES
    Internal. Destructive but bounded; only touches *.log files.

    .LINK
    Start-GELogSession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [int]$RetentionDays = 30
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    if ($RetentionDays -le 0) {
        return
    }

    $cutoff = (Get-Date).AddDays(-1 * $RetentionDays)

    $oldFiles = @(
        Get-ChildItem -LiteralPath $Directory -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }
    )

    foreach ($file in $oldFiles) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }
}
