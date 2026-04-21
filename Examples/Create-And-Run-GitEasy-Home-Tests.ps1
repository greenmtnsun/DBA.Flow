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
