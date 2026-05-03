@{
    RootModule = 'GitEasy.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a7f52f47-87b2-42c4-9f37-9f329edb7a01'
    Author = 'Keith Ramsey'
    CompanyName = 'Keith Ramsey'
    Copyright = '(c) Keith Ramsey. All rights reserved.'
    Description = 'Classic GitEasy public commands with a safer V2 PowerShell engine.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Clear-Junk'
        'Find-CodeChange'
        'Get-VaultStatus'
        'New-WorkBranch'
        'Reset-Login'
        'Restore-File'
        'Save-Work'
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
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
