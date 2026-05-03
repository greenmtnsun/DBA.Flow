@{
    RootModule        = 'GitEasy.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '2e113abf-c0e7-4dfb-9cb1-69476d7541f6'
    Author            = 'Keith Ramsey'
    CompanyName       = 'Keith Ramsey'
    Copyright         = '(c) Keith Ramsey. Licensed under the Mozilla Public License 2.0.'
    Description       = 'Plain-English Git workflow for PowerShell. Classic GitEasy public commands with a safer engine, per-invocation diagnostic logs, and no jargon in the user surface.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Clear-Junk'
        'Find-CodeChange'
        'Get-VaultStatus'
        'New-WorkBranch'
        'Reset-Login'
        'Restore-File'
        'Save-Work'
        'Search-History'
        'Set-Ssh'
        'Set-Token'
        'Set-Vault'
        'Show-Diagnostic'
        'Show-History'
        'Show-Remote'
        'Switch-Work'
        'Test-Login'
        'Undo-Changes'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('git', 'github', 'gitlab', 'sysadmin', 'plain-english', 'beginner-friendly', 'powershell', 'workflow')
            LicenseUri   = 'https://www.mozilla.org/MPL/2.0/'
            ProjectUri   = 'https://github.com/greenmtnsun/GitEasy'
            ReleaseNotes = 'See https://github.com/greenmtnsun/GitEasy/blob/main/CHANGELOG.md'
        }
    }
}
