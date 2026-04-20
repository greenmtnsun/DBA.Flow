[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Branch = "main",
    [switch]$Push,
    [switch]$CreateCommit = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path ".git")) {
    throw "No .git folder found in the current directory. Run this from the root of your GitEasy repository."
}

$obsoleteFiles = @(
    "GitEasy.psd1",
    "GitEasy.psm1",
    "GitEasy_Master_Wiki.pdf",
    "README_GitEasy.md",
    "Wiki-Readme.txt",
    "Wiki-Readme-GitEasy.txt",
    "gitignore_GitEasy.txt"
)

$replacementFiles = @(
    "GitEasy.psd1",
    "GitEasy.psm1",
    "README.md",
    "GitEasy_Confluence_Wiki.txt"
)

foreach ($file in $replacementFiles) {
    if (-not (Test-Path $file)) {
        throw "Required replacement file not found: $file"
    }
}

Write-Host ""
Write-Host "Obsolete files targeted for removal:" -ForegroundColor Cyan
$found = @()
$missing = @()
foreach ($file in $obsoleteFiles) {
    if (Test-Path $file) {
        $found += $file
        Write-Host "  $file" -ForegroundColor Yellow
    }
    else {
        $missing += $file
    }
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Already missing:" -ForegroundColor DarkCyan
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "Files that will remain as the current GitEasy set:" -ForegroundColor Green
$replacementFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }

if ($PSCmdlet.ShouldProcess("legacy GitEasy and transitional rename files", "remove obsolete files and stage current GitEasy files")) {

    foreach ($file in $found) {
        Invoke-Git -Arguments @("rm", "-f", "--", $file)
    }

    Invoke-Git -Arguments @("add", "GitEasy.psd1", "GitEasy.psm1", "README.md", "GitEasy_Confluence_Wiki.txt")

    $status = git status --porcelain
    if (-not $status) {
        Write-Host "No changes detected after cleanup." -ForegroundColor Yellow
        exit 0
    }

    if ($CreateCommit) {
        Invoke-Git -Arguments @("commit", "-m", "Finalize GitEasy rename and remove obsolete GitEasy files")
    }

    if ($Push) {
        Invoke-Git -Arguments @("push", "origin", $Branch)
    }

    Write-Host ""
    Write-Host "Cleanup complete." -ForegroundColor Green
}

