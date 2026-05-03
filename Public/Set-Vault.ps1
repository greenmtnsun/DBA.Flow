function Set-Vault {
    <#
    .SYNOPSIS
    Choose where saved logins are stored, and optionally write a starter ignore list.

    .DESCRIPTION
    Set-Vault tells the system which credential storage to use for saved logins. The default (manager) is appropriate for most modern Windows installs. Use this when first setting up GitEasy on a new machine, or when moving between credential storage backends.

    With -WriteIgnoreList, Set-Vault also writes a starter .gitignore file in the active project folder, populated with patterns common to PowerShell, .NET, and SQL/SSIS projects (build artifacts, IDE leftovers, log files, secret files, etc.). Existing .gitignore content is preserved; the starter patterns are appended only if missing.

    .PARAMETER Helper
    The credential storage name. One of: manager, manager-core, wincred, cache.

    .PARAMETER WriteIgnoreList
    Also write a starter .gitignore in the active project folder. Adds common junk patterns; preserves anything already in the file.

    .EXAMPLE
    Set-Vault

    .EXAMPLE
    Set-Vault -Helper wincred

    .EXAMPLE
    Set-Vault -Helper manager -WriteIgnoreList

    .NOTES
    Safety:
    - Never store secrets in plain-text files. Pick a storage backend that the operating system protects.
    - Use Get-VaultStatus to confirm the choice without exposing any secret values.
    - -WriteIgnoreList never overwrites your existing patterns; it only appends what is missing.

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
        [string]$Helper = 'manager',

        [switch]$WriteIgnoreList
    )

    Test-GEGitInstalled | Out-Null

    if (-not $PSCmdlet.ShouldProcess('global Git config', "Set credential.helper to $Helper")) {
        return
    }

    Invoke-GEGit -ArgumentList @('config', '--global', 'credential.helper', $Helper) | Out-Null

    $ignoreInfo = $null

    if ($WriteIgnoreList) {
        $repoRoot = $null
        try {
            $repoRoot = Get-GERepoRoot
        }
        catch {
            $repoRoot = $null
        }

        if ($repoRoot) {
            $starterPatterns = @(
                '# Added by Set-Vault -WriteIgnoreList',
                '*.user',
                '*.suo',
                '*.tmp',
                '*.log',
                '*.bak',
                'bin/',
                'obj/',
                'TestResults/',
                '.vs/',
                '.idea/',
                '.vscode/',
                '*.pfx',
                'secrets.json',
                '*.rdl.data'
            )

            $ignorePath = Join-Path $repoRoot '.gitignore'
            $existing = @()

            if (Test-Path -LiteralPath $ignorePath -PathType Leaf) {
                $existing = @(Get-Content -LiteralPath $ignorePath)
            }

            $missing = @()
            foreach ($pattern in $starterPatterns) {
                if (-not ($existing -contains $pattern)) {
                    $missing += $pattern
                }
            }

            if ($missing.Count -gt 0) {
                $appendBody = ''
                if ($existing.Count -gt 0) {
                    $appendBody = ($existing -join "`r`n")
                    if (-not $appendBody.EndsWith("`r`n")) {
                        $appendBody += "`r`n"
                    }
                    $appendBody += "`r`n"
                }
                $appendBody += ($missing -join "`r`n") + "`r`n"

                [System.IO.File]::WriteAllText($ignorePath, $appendBody, [System.Text.UTF8Encoding]::new($false))
            }

            $ignoreInfo = [PSCustomObject]@{
                Path    = $ignorePath
                Added   = $missing.Count
                Skipped = $starterPatterns.Count - $missing.Count
            }
        }
    }

    [PSCustomObject]@{
        CredentialHelper = $Helper
        IgnoreList       = $ignoreInfo
        Message          = "Credential storage set to $Helper."
    }
}
