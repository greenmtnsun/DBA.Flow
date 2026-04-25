function Get-VaultStatus {
    [CmdletBinding()]
    param()

    Test-GEGitInstalled | Out-Null
    $helper = Invoke-GEGit -ArgumentList @('config', '--global', '--get', 'credential.helper') -AllowFailure
    $value = $helper.Output | Select-Object -First 1

    [PSCustomObject]@{
        CredentialHelper = $value
        Configured       = ($helper.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($value))
    }
}
