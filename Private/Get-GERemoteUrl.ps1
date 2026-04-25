function Get-GERemoteUrl {
    [CmdletBinding()]
    param(
        [string]$RemoteName = 'origin',
        [string]$Path = (Get-Location).Path
    )

    $root = Get-GERepoRoot -Path $Path
    $result = Invoke-GEGit -ArgumentList @('remote', 'get-url', $RemoteName) -WorkingDirectory $root -AllowFailure

    if ($result.ExitCode -ne 0) {
        return $null
    }

    $url = $result.Output | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($url)) {
        return $null
    }

    return $url
}
