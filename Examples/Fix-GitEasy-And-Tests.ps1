[CmdletBinding()]
param(
    [string]$RepoPath = "C:\Sysadmin\Scripts\giteasy"
)

$ErrorActionPreference = "Stop"

Set-Location $RepoPath

$psm1Path = Join-Path $RepoPath "GitEasy.psm1"
$examplesPath = Join-Path $RepoPath "Examples"
$testHarnessPath = Join-Path $examplesPath "Create-And-Run-GitEasy-Home-Tests.ps1"

if (-not (Test-Path $psm1Path)) {
    throw "Could not find $psm1Path"
}

if (-not (Test-Path $examplesPath)) {
    New-Item -ItemType Directory -Path $examplesPath -Force | Out-Null
}

$saveWorkFunction = @'
function Save-Work {
    <#
    .SYNOPSIS
        Snapshots every file and pushes to GitHub or GitLab.
        Handles module versioning and shows clearer errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Note,
        [switch]$NewVersion,
        [ValidateSet('Major', 'Minor', 'Build', 'Revision')]
        [string]$BumpType = 'Revision'
    )

    function Invoke-GitEasyGit {
        param(
            [Parameter(Mandatory = $true)][string]$Step,
            [Parameter(Mandatory = $true)][string[]]$Arguments
        )

        Write-Host ""
        Write-Host "[$Step]" -ForegroundColor Cyan
        Write-Host ("git " + ($Arguments -join ' ')) -ForegroundColor DarkGray

        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }

        if ($exitCode -ne 0) {
            throw "Git step failed: $Step (exit code $exitCode)"
        }

        [pscustomobject]@{
            Output   = $output
            ExitCode = $exitCode
        }
    }

    if ($NewVersion) {
        $manifest = Get-ChildItem *.psd1 | Select-Object -First 1
        if ($manifest) {
            $manifestData = Import-PowerShellDataFile $manifest.FullName
            $v = [version]$manifestData.ModuleVersion

            switch ($BumpType) {
                'Major'    { $newV = New-Object System.Version ($v.Major + 1), 0, 0, 0 }
                'Minor'    { $newV = New-Object System.Version $v.Major, ($v.Minor + 1), 0, 0 }
                'Build'    { $newV = New-Object System.Version $v.Major, $v.Minor, ($v.Build + 1), 0 }
                'Revision' { $newV = New-Object System.Version $v.Major, $v.Minor, $v.Build, ($v.Revision + 1) }
            }

            $pattern = "ModuleVersion\s*=\s*'[^']+'"
            $replacement = "ModuleVersion     = '$newV'"
            (Get-Content $manifest.FullName -Raw) -replace $pattern, $replacement | Set-Content $manifest.FullName

            $Note = "[v$newV] $Note"
            Write-Host "Bumped $BumpType to $newV" -ForegroundColor Green
        }
    }

    $statusBefore = git status --porcelain
    if (-not $statusBefore) {
        Write-Warning "No changes found to save."
        return
    }

    Write-Host ""
    Write-Host "[Pre-check]" -ForegroundColor Cyan
    $statusBefore | ForEach-Object { Write-Host $_ }

    $stashed = $false

    try {
        Write-Host ""
        Write-Host "[Stash local changes]" -ForegroundColor Cyan
        $stashResult = & git stash push -u -m "GitEasy temporary save before Save-Work" 2>&1
        $stashExit = $LASTEXITCODE
        $stashResult | ForEach-Object { Write-Host $_ }

        if ($stashExit -ne 0) {
            throw "Could not stash local changes before pull."
        }

        $stashed = $true

        Invoke-GitEasyGit -Step "Check for peer updates" -Arguments @("pull", "origin", "main", "--rebase")

        if ($stashed) {
            Write-Host ""
            Write-Host "[Restore stashed changes]" -ForegroundColor Cyan
            $popResult = & git stash pop 2>&1
            $popExit = $LASTEXITCODE
            $popResult | ForEach-Object { Write-Host $_ }

            if ($popExit -ne 0) {
                throw "Stash pop failed. Resolve the stash state before running Save-Work again."
            }

            $stashed = $false
        }

        Invoke-GitEasyGit -Step "Stage files" -Arguments @("add", ".")

        $statusAfterAdd = git status --porcelain
        if (-not $statusAfterAdd) {
            Write-Warning "No changes found to commit after staging."
            return
        }

        Write-Host ""
        Write-Host "[Commit preview]" -ForegroundColor Cyan
        $statusAfterAdd | ForEach-Object { Write-Host $_ }

        Invoke-GitEasyGit -Step "Commit changes" -Arguments @("commit", "-m", $Note)
        Invoke-GitEasyGit -Step "Push changes" -Arguments @("push", "origin", "main")

        Write-Host ""
        Write-Host "Work synced and secured." -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Warning $_.Exception.Message
        Write-Host "Your work is still local." -ForegroundColor Yellow
        throw
    }
}
'@

$testHarness = @'
[CmdletBinding()]
param(
    [string]$RepoPath = "C:\Sysadmin\Scripts\giteasy",
    [string]$ModuleManifest = ".\GitEasy.psd1",
    [string]$GitHubHost = "github.com",
    [string]$GitHubHttpsUrl = "https://github.com/greenmtnsun/GitEasy.git",
    [string]$GitHubSshUrl = "git@github.com:greenmtnsun/GitEasy.git",
    [switch]$RunSshTest,
    [switch]$RunSaveWorkTest
)

$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host $Title -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkGray
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [switch]$FailOnLastExitCode
    )

    Write-Host ""
    Write-Host ">> $Name" -ForegroundColor Yellow

    $global:LASTEXITCODE = 0

    try {
        & $Action

        if ($FailOnLastExitCode -and $LASTEXITCODE -ne 0) {
            throw "Last exit code: $LASTEXITCODE"
        }

        Write-Host "<< PASS: $Name" -ForegroundColor Green
    }
    catch {
        Write-Host "<< FAIL: $Name" -ForegroundColor Red
        Write-Host $_
    }
}

Write-Section "1. Move into repo and import module"

Set-Location $RepoPath
Import-Module $ModuleManifest -Force

Write-Host "Repo Path: $RepoPath" -ForegroundColor Gray
Write-Host "Module imported." -ForegroundColor Green

Write-Section "2. Show exported GitEasy commands"

Get-Command -Module GitEasy | Sort-Object Name | Format-Table Name, CommandType -AutoSize

Write-Section "3. Basic safe status tests"

Invoke-Step -Name "Show-Remote" -Action { Show-Remote }
Invoke-Step -Name "Get-VaultStatus" -Action { Get-VaultStatus }
Invoke-Step -Name "Show-History" -Action { Show-History }
Invoke-Step -Name "Find-CodeChange (search for GitEasy)" -Action { Find-CodeChange -SearchString "GitEasy" }

Write-Section "4. GitHub HTTPS test"

Invoke-Step -Name "Reset-Login for GitHub" -Action { Reset-Login -HostName $GitHubHost }
Invoke-Step -Name "Set-Token to GitHub HTTPS remote" -Action { Set-Token -WebAddress $GitHubHttpsUrl }
Invoke-Step -Name "Show-Remote after HTTPS change" -Action { Show-Remote }
Invoke-Step -Name "Test-Login over HTTPS" -Action {
    $result = Test-Login
    Write-Host "Test-Login returned: $result" -ForegroundColor Gray
    if (-not $result) { throw "Test-Login returned false." }
}

if ($RunSshTest) {
    Write-Section "5. GitHub SSH test"

    Invoke-Step -Name "Set-Ssh to GitHub SSH remote" -Action { Set-Ssh -SshAddress $GitHubSshUrl }
    Invoke-Step -Name "Show-Remote after SSH change" -Action { Show-Remote }
    Invoke-Step -Name "Test-Login over SSH" -Action {
        $result = Test-Login
        Write-Host "Test-Login returned: $result" -ForegroundColor Gray
        if (-not $result) { throw "Test-Login returned false." }
    }
    Invoke-Step -Name "Set-Token back to GitHub HTTPS remote" -Action { Set-Token -WebAddress $GitHubHttpsUrl }
    Invoke-Step -Name "Show-Remote after switching back to HTTPS" -Action { Show-Remote }
}

if ($RunSaveWorkTest) {
    Write-Section "10. Save-Work test"

    $saveTestFile = Join-Path $RepoPath "giteasy-savework-test.txt"
    "Save-Work test at $(Get-Date -Format s)" | Set-Content $saveTestFile

    Invoke-Step -Name "Get-VaultStatus before Save-Work" -Action { Get-VaultStatus }
    Invoke-Step -Name "Save-Work" -Action {
        Save-Work -Note "Test Save-Work from home against GitHub"
    } -FailOnLastExitCode
}

Write-Section "11. Final remote and status"

Show-Remote
Get-VaultStatus

Write-Host ""
Write-Host "Done." -ForegroundColor Green
'@

$psm1 = Get-Content $psm1Path -Raw

$start = $psm1.IndexOf("function Save-Work {")
if ($start -lt 0) {
    throw "Could not find start of Save-Work in $psm1Path"
}

$remaining = $psm1.Substring($start + 1)
$nextFunctionMatch = [regex]::Match($remaining, "(?m)^function\s+[A-Za-z0-9\-]+\s*\{")
if (-not $nextFunctionMatch.Success) {
    throw "Could not find the function after Save-Work in $psm1Path"
}

$nextFunctionIndex = $start + 1 + $nextFunctionMatch.Index
$before = $psm1.Substring(0, $start)
$after = $psm1.Substring($nextFunctionIndex)

$newPsm1 = $before + $saveWorkFunction + "`r`n`r`n" + $after
Set-Content -Path $psm1Path -Value $newPsm1 -Encoding UTF8

Set-Content -Path $testHarnessPath -Value $testHarness -Encoding UTF8

Write-Host ""
Write-Host "Updated files:" -ForegroundColor Green
Write-Host "  $psm1Path"
Write-Host "  $testHarnessPath"
Write-Host ""
Write-Host "Now run:" -ForegroundColor Yellow
Write-Host "  C:\Sysadmin\Scripts\GitEasy\Examples\Create-And-Run-GitEasy-Home-Tests.ps1"
Write-Host "or"
Write-Host "  C:\Sysadmin\Scripts\GitEasy\Examples\Create-And-Run-GitEasy-Home-Tests.ps1 -RunSshTest"