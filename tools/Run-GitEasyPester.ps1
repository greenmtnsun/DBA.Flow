<#
.SYNOPSIS
Run the GitEasy Pester test suite using Pester 3 (the version the tests were written for).

.DESCRIPTION
Explicitly loads Pester 3 (preferring 3.4.x) and invokes the test runner over the Tests folder. GitEasy tests are written in Pester 3 syntax; loading Pester 5 would silently mis-run them via the legacy adapter, so this script pins Pester 3 to keep behavior deterministic across machines.

.PARAMETER ProjectRoot
Absolute path to the GitEasy source repository. Defaults to C:\Sysadmin\Scripts\GitEasy.

.EXAMPLE
.\tools\Run-GitEasyPester.ps1

.NOTES
Most environments ship Pester 3 by default with Windows PowerShell 5.1. Tests must work against Pester 3.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Sysadmin\Scripts\GitEasy'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "Missing project folder: $ProjectRoot"
}

$testRoot = Join-Path $ProjectRoot 'Tests'

if (-not (Test-Path -LiteralPath $testRoot)) {
    throw "Missing test folder: $testRoot"
}

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -lt 4 } | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pester) {
    throw "Pester 3 is not installed. Install it with: Install-Module Pester -RequiredVersion 3.4.0 -SkipPublisherCheck -Scope AllUsers -Force"
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module $pester.Path -Force

Write-Host ""
Write-Host "Running GitEasy Pester tests..." -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"
Write-Host "Pester:  $($pester.Version)"
Write-Host ""

$result = Invoke-Pester -Script $testRoot -PassThru

$summary = [PSCustomObject]@{
    Total   = $result.TotalCount
    Passed  = $result.PassedCount
    Failed  = $result.FailedCount
    Skipped = $result.SkippedCount
}

Write-Host ""
Write-Host "GitEasy Pester summary:" -ForegroundColor Cyan
$summary | Format-List

if ($result.FailedCount -gt 0) {
    throw "GitEasy Pester tests failed."
}

Write-Host "GitEasy Pester tests passed." -ForegroundColor Green
