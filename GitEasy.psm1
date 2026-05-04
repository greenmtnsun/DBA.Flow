Set-StrictMode -Version Latest
$privatePath = Join-Path $PSScriptRoot 'Private'
$publicPath = Join-Path $PSScriptRoot 'Public'
Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object { . $_.FullName }
Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object { . $_.FullName }
Export-ModuleMember -Function @(
    'Clear-Junk',
    'Find-CodeChange',
    'Get-VaultStatus',
    'New-Release',
    'New-WorkBranch',
    'Reset-Login',
    'Restore-File',
    'Save-Work',
    'Search-History',
    'Set-Ssh',
    'Set-Token',
    'Set-Vault',
    'Show-Diagnostic',
    'Show-History',
    'Show-Releases',
    'Show-Remote',
    'Switch-Work',
    'Test-Login',
    'Undo-Changes'
)
