function Reset-Login {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$RemoteName = 'origin')

    $root = Get-GERepoRoot
    $remoteUrl = Get-GERemoteUrl -RemoteName $RemoteName -Path $root

    if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
        throw "Remote '$RemoteName' is not configured."
    }

    if ($remoteUrl -notmatch '^https://(?<Host>[^/]+)/') {
        throw "Reset-Login currently supports HTTPS remotes only. Current remote: $remoteUrl"
    }

    $hostName = $Matches.Host

    if (-not $PSCmdlet.ShouldProcess($hostName, 'Reject cached Git HTTPS credential')) {
        return
    }

    $inputLines = @(
        'protocol=https'
        "host=$hostName"
        ''
    )

    $inputLines | git credential reject

    if ($LASTEXITCODE -ne 0) {
        throw "Git credential reject failed for host: $hostName"
    }

    [PSCustomObject]@{
        Host    = $hostName
        Message = 'Cached credential reject request sent. Run Test-Login to prompt again.'
    }
}
