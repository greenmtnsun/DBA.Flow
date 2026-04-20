@{
    RootModule        = 'GitEasy.psm1'
    ModuleVersion     = '1.0.0.2'
    GUID              = '2e113abf-c0e7-4dfb-9cb1-69476d7541f6'
    Author            = 'Keith Ramsey'
    CompanyName       = 'Keith Ramsey'
    Description       = 'GitEasy workflow for SQL, modules, and customer ecosystems.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Set-Vault','Save-Work','Show-History','Find-CodeChange','Restore-File','Clear-Junk','Undo-Changes','New-WorkBranch','Switch-Work','Get-VaultStatus')
}
