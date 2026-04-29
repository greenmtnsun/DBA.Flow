$ErrorActionPreference = 'Stop'

$GitEasyRoot = 'C:\Sysadmin\Scripts\GitEasyV2'
$ScriptPath = 'C:\Sysadmin\Scripts\GitEasyV2\Update-GitEasyCommandWiki.ps1'
$GitEasyModule = 'C:\Sysadmin\Scripts\GitEasyV2\GitEasy.psd1'

Write-Host 'STATE CHECK: Commit GitEasy wiki enrichment script'

if (-not (Test-Path -LiteralPath "$GitEasyRoot\.git" -PathType Container)) {
    throw "Missing GitEasy repo: $GitEasyRoot\.git"
}

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Missing script: $ScriptPath"
}

$Tokens = $null
$ParseErrors = $null

$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $ScriptPath,
    [ref]$Tokens,
    [ref]$ParseErrors
)

if ($ParseErrors.Count -gt 0) {
    $ParseErrors | ForEach-Object {
        Write-Warning "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }

    throw 'Script has parser errors. Not committing.'
}

Set-Location $GitEasyRoot

Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
Import-Module $GitEasyModule -Force

Find-CodeChange
Save-Work -Message 'Add GitEasy command wiki enrichment script'
Show-History -Count 5
git status -sb