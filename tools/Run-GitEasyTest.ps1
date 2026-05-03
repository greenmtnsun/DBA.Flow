<#
.SYNOPSIS
Run the legacy GitEasy manifest sanity test in a fresh PowerShell child process.

.DESCRIPTION
Wrapper around Tests\Test-GitEasyManifest.ps1 that runs the test in a fresh Windows PowerShell child so leftover module state in the current session cannot mask a failure. Throws if the child exits non-zero.

.PARAMETER ProjectRoot
Absolute path to the GitEasy source repository. Defaults to C:\Sysadmin\Scripts\GitEasyV2.

.EXAMPLE
.\tools\Run-GitEasyTest.ps1

.NOTES
Use Run-GitEasyPester.ps1 for the full Pester suite. This script is the lighter manifest-only check.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Sysadmin\Scripts\GitEasyV2'
)
$ErrorActionPreference = 'Stop'
$test = Join-Path $ProjectRoot 'Tests\Test-GitEasyManifest.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test -ProjectRoot $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw 'GitEasy test failed.' }
