function Set-Vault {
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
