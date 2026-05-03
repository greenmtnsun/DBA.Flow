function Get-VaultStatus {
    <#
    .SYNOPSIS
    Report which credential storage GitEasy will use for saved logins.

    .DESCRIPTION
    Get-VaultStatus returns a small object describing the configured credential storage. It never returns the secret values themselves; it only reports the storage name and whether anything is configured.

    .EXAMPLE
    Get-VaultStatus

    .EXAMPLE
    Set-Vault; Get-VaultStatus

    .NOTES
    Output is safe to log or share. It does not contain credentials.

    .LINK
    Set-Vault

    .LINK
    Set-Token

    .LINK
    Test-Login
    #>
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
