function Set-Vault {
    <#
    .SYNOPSIS
    Choose where saved logins are stored.

    .DESCRIPTION
    Set-Vault tells the system which credential storage to use for saved logins. The default (manager) is appropriate for most modern Windows installs. Use this when first setting up GitEasy on a new machine, or when moving between credential storage backends.

    .PARAMETER Helper
    The credential storage name. One of: manager, manager-core, wincred, cache.

    .EXAMPLE
    Set-Vault

    .EXAMPLE
    Set-Vault -Helper wincred

    .NOTES
    Safety:
    - Never store secrets in plain-text files. Pick a storage backend that the operating system protects.
    - Use Get-VaultStatus to confirm the choice without exposing any secret values.

    .LINK
    Get-VaultStatus

    .LINK
    Set-Token

    .LINK
    Test-Login
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('manager', 'manager-core', 'wincred', 'cache')]
        [string]$Helper = 'manager'
    )

    Test-GEGitInstalled | Out-Null

    if (-not $PSCmdlet.ShouldProcess('global Git config', "Set credential.helper to $Helper")) {
        return
    }

    Invoke-GEGit -ArgumentList @('config', '--global', 'credential.helper', $Helper) | Out-Null

    [PSCustomObject]@{
        CredentialHelper = $Helper
        Message          = "Git credential helper set to $Helper."
    }
}
