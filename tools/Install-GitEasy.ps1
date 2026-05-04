<#
.SYNOPSIS
Deploy the GitEasy module from its dev folder to a system module location.

.DESCRIPTION
Install-GitEasy.ps1 copies the runtime essentials of GitEasy (manifest, root module, Public\, Private\, README, LICENSE, CHANGELOG) from the dev folder to a system module path so that any PowerShell session on the machine can do `Import-Module GitEasy` without specifying a path.

By default, the script installs to BOTH:
- C:\Program Files\WindowsPowerShell\Modules\GitEasy   (Windows PowerShell 5.1)
- C:\Program Files\PowerShell\Modules\GitEasy          (PowerShell 7+)

Writing to Program Files requires administrative privileges. If the script is run from a non-elevated session, it tells you so and stops without modifying anything.

A backup of any existing install is taken first (renamed to `GitEasy.bak.<timestamp>`), so a rollback is one rename away.

The dev folder contents that are NOT copied to the install location:
- Tests\, tools\, .github\
- Update-GitEasy*Wiki.ps1 (development tools)
- Examples\, docs\
- Any \*.bak files

.PARAMETER Source
The dev folder to install from. Defaults to C:\Sysadmin\Scripts\GitEasy.

.PARAMETER Target
One or more target install paths. Defaults to both Windows PowerShell 5.1 and PowerShell 7+ AllUsers locations.

.PARAMETER SkipPesterCheck
Skip the pre-install Pester run. By default, the script refuses to install if any Pester test fails.

.EXAMPLE
.\tools\Install-GitEasy.ps1

.EXAMPLE
.\tools\Install-GitEasy.ps1 -Target 'C:\Program Files\WindowsPowerShell\Modules\GitEasy'

.NOTES
Run from an elevated PowerShell session (Run as Administrator). Writing to Program Files without elevation fails with a permission error.
#>

[CmdletBinding()]
param(
    [string]$Source = 'C:\Sysadmin\Scripts\GitEasy',

    [string[]]$Target = @(
        'C:\Program Files\WindowsPowerShell\Modules\GitEasy',
        'C:\Program Files\PowerShell\Modules\GitEasy'
    ),

    [switch]$SkipPesterCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host 'STATE CHECK: Install GitEasy from dev folder' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Source folder does not exist: $Source"
}

$manifestPath = Join-Path $Source 'GitEasy.psd1'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Source folder is not a GitEasy module (no GitEasy.psd1 found): $Source"
}

$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$moduleVersion = $manifest.ModuleVersion

Write-Host "Source:         $Source"
Write-Host "Module version: $moduleVersion"
Write-Host "Targets:"
foreach ($t in $Target) {
    Write-Host "  $t"
}
Write-Host ''

# Pester gate (pinned to Pester 3 - tests are written in Pester 3 syntax)
if (-not $SkipPesterCheck) {
    Write-Host 'Running Pester suite before install...' -ForegroundColor Cyan
    $pester3 = Get-Module -ListAvailable Pester | Where-Object { $_.Version.Major -lt 4 } | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester3) {
        throw 'Pester 3 is not installed. Install it with: Install-Module Pester -RequiredVersion 3.4.0 -SkipPublisherCheck -Scope AllUsers -Force'
    }
    Remove-Module Pester -Force -ErrorAction SilentlyContinue
    Import-Module $pester3.Path -Force
    $pesterResult = Invoke-Pester -Script (Join-Path $Source 'Tests') -PassThru -Quiet

    if ($pesterResult.FailedCount -gt 0) {
        $pesterResult.TestResult | Where-Object { -not $_.Passed } | ForEach-Object {
            Write-Host "  FAIL: $($_.Name)" -ForegroundColor Red
        }
        throw "Pester reported $($pesterResult.FailedCount) failure(s). Refusing to install. Use -SkipPesterCheck to override."
    }

    Write-Host "  $($pesterResult.PassedCount)/$($pesterResult.TotalCount) tests passed." -ForegroundColor Green
    Write-Host ''
}

# Permission check on each target
foreach ($t in $Target) {
    $parent = Split-Path -Path $t -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        Write-Host "Skipping target (parent folder does not exist): $t" -ForegroundColor Yellow
        continue
    }

    $probeFile = Join-Path $parent ('.giteasy-install-probe-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($probeFile, 'probe', [System.Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        throw "No write permission on $parent. Run this script from an elevated PowerShell (Run as Administrator) to install to Program Files."
    }
}

# Build the runtime manifest of files to copy
$includePaths = @(
    'GitEasy.psd1',
    'GitEasy.psm1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md'
)

$includeFolders = @(
    'Public',
    'Private'
)

$installedTargets = @()

foreach ($t in $Target) {
    $parent = Split-Path -Path $t -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        continue
    }

    Write-Host "Installing to: $t" -ForegroundColor Cyan

    if (Test-Path -LiteralPath $t -PathType Container) {
        $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
        $backupPath = "$t.bak.$stamp"
        Rename-Item -LiteralPath $t -NewName (Split-Path -Path $backupPath -Leaf) -Force
        Write-Host "  Backed up existing install: $backupPath"
    }

    New-Item -Path $t -ItemType Directory -Force | Out-Null

    foreach ($f in $includePaths) {
        $src = Join-Path $Source $f
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $t $f) -Force
        }
    }

    foreach ($folder in $includeFolders) {
        $src = Join-Path $Source $folder
        if (Test-Path -LiteralPath $src -PathType Container) {
            $dest = Join-Path $t $folder
            Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
        }
    }

    Write-Host "  Copied module runtime to $t"
    $installedTargets += $t
}

if ($installedTargets.Count -eq 0) {
    Write-Warning 'No targets were installed (no parent folders existed).'
    return
}

# Verify by importing the module from a fresh PowerShell child
Write-Host ''
Write-Host 'Verifying install...' -ForegroundColor Cyan

$verifyOutput = & powershell.exe -NoProfile -Command "Import-Module GitEasy -Force; (Get-Module GitEasy | Select-Object -First 1).Version.ToString()" 2>&1
$verifyExit = $LASTEXITCODE

if ($verifyExit -ne 0 -or [string]::IsNullOrWhiteSpace($verifyOutput)) {
    Write-Warning "Could not verify install via Import-Module. Output: $verifyOutput"
}
else {
    $reportedVersion = ($verifyOutput | Select-Object -Last 1).ToString().Trim()
    if ($reportedVersion -eq $moduleVersion) {
        Write-Host "  Verified: GitEasy $reportedVersion is importable without a path." -ForegroundColor Green
    }
    else {
        Write-Warning "Verified import returned version $reportedVersion (expected $moduleVersion)."
    }
}

Write-Host ''
Write-Host "Install complete. GitEasy $moduleVersion is now available system-wide." -ForegroundColor Green
Write-Host 'Any PowerShell session can now run:  Import-Module GitEasy' -ForegroundColor Green
