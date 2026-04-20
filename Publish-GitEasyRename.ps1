[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteUrl,

    [string]$Branch = "main",

    [string]$UserName = "Keith Ramsey",

    [string]$UserEmail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Preparing GitEasy repository update..." -ForegroundColor Cyan

if (-not (Test-Path ".git")) {
    throw "No .git folder found in the current directory."
}

if ($UserName)  { git config user.name  $UserName }
if ($UserEmail) { git config user.email $UserEmail }

# Only remove files that are truly obsolete
$legacyFiles = @(
    "GitEasy.psd1",
    "GitEasy.psm1",
    "GitEasy_Master_Wiki.pdf",
    "README_GitEasy.md",
    "Wiki-Readme.txt",
    "Wiki-Readme-GitEasy.txt",
    "gitignore_GitEasy.txt"
)

foreach ($file in $legacyFiles) {
    if (Test-Path $file) {
        git rm -f -- $file 2>$null
        if (Test-Path $file) {
            Remove-Item -Force $file
        }
    }
}

$originExists = git remote 2>$null | Where-Object { $_ -eq "origin" }
if ($originExists) {
    git remote set-url origin $RemoteUrl
}
else {
    git remote add origin $RemoteUrl
}

# Stage everything that currently exists
git add -A

$changes = git status --porcelain
if (-not $changes) {
    Write-Host "No changes detected." -ForegroundColor Yellow
    exit 0
}

git commit -m "Finalize GitEasy rename and publish current files"
git push -u origin $Branch
