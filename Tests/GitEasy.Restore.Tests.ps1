$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath  = Join-Path $ProjectRoot 'GitEasy.psd1'

function Invoke-TestGit {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [switch]$AllowFailure
    )

    $oldPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = 'Continue'
        $output = & git @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Git failed: git $($ArgumentList -join ' ')`n$($output -join [Environment]::NewLine)"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function New-TestRepositoryWithCommit {
    param([Parameter(Mandatory)] [string]$Path)

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $Path

    try {
        Invoke-TestGit -ArgumentList @('init') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.name', 'GitEasy Pester') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.email', 'giteasy-pester@example.invalid') | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'baseline content' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'baseline') | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe 'Restore-File' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_RF_$script:Stem")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_RF_$($script:Stem)_logs")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs

        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location

        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'restores a single tracked file to its last saved state' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'edited content' -Encoding UTF8

        Restore-File -Path 'README.md'

        $content = Get-Content -LiteralPath $target -Raw
        $content.Trim() | Should Be 'baseline content'
    }

    It 'leaves other modified files untouched' {
        $a = Join-Path $script:TempRepo 'a.txt'
        Set-Content -LiteralPath $a -Value 'original' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'add a') | Out-Null

        $readme = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $readme -Value 'edited readme' -Encoding UTF8
        Set-Content -LiteralPath $a -Value 'edited a' -Encoding UTF8

        Restore-File -Path 'README.md'

        $aContent = Get-Content -LiteralPath $a -Raw
        $aContent.Trim() | Should Be 'edited a'
    }

    It 'fails plainly when the path does not exist' {
        $thrown = $null
        try { Restore-File -Path 'nope/does-not-exist.txt' } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bgit\b'
    }

    It 'every invocation writes a log file with SUCCESS outcome' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'edited' -Encoding UTF8

        Restore-File -Path 'README.md'

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Restore-File-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
        $body = Get-Content -LiteralPath ($logs | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw
        $body | Should Match 'Outcome: SUCCESS'
    }

    It 'returns a structured object describing the restore' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'edited' -Encoding UTF8

        $result = Restore-File -Path 'README.md'

        $result | Should Not BeNullOrEmpty
        $result.Path | Should Match 'README\.md'
    }
}

Describe 'Undo-Changes' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_UC_$script:Stem")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_UC_$($script:Stem)_logs")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs

        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location

        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'discards unsaved changes when -Force is supplied' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'unsaved edit' -Encoding UTF8

        Undo-Changes -Force

        $content = Get-Content -LiteralPath $target -Raw
        $content.Trim() | Should Be 'baseline content'
    }

    It 'requires -Force or -Confirm so a bare invocation never quietly destroys work' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'unsaved edit' -Encoding UTF8

        $thrown = $null
        try { Undo-Changes } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
    }

    It 'reports cleanly when there is nothing to undo' {
        $messages = & { Undo-Changes -Force } *>&1
        ($messages -join ' ') | Should Match '(?i)nothing'
    }

    It 'every invocation writes a log file' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'unsaved' -Encoding UTF8

        Undo-Changes -Force

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Undo-Changes-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
    }

    It 'returns a structured object describing the undo' {
        $target = Join-Path $script:TempRepo 'README.md'
        Set-Content -LiteralPath $target -Value 'unsaved' -Encoding UTF8

        $result = Undo-Changes -Force

        $result | Should Not BeNullOrEmpty
        ($result.PSObject.Properties.Name -contains 'Repository') | Should Be $true
    }
}

Describe 'Clear-Junk' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_CJ_$script:Stem")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_CJ_$($script:Stem)_logs")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs

        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location

        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lists junk files without removing anything by default' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo '.gitignore') -Value '*.bak' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'leftover.bak') -Value 'junk' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'kept.txt')     -Value 'keep' -Encoding UTF8

        $result = Clear-Junk

        Test-Path -LiteralPath (Join-Path $script:TempRepo 'leftover.bak') | Should Be $true
        Test-Path -LiteralPath (Join-Path $script:TempRepo 'kept.txt')     | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Candidates') | Should Be $true
    }

    It 'removes ignored files when -Force is supplied' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo '.gitignore') -Value '*.bak' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'leftover.bak') -Value 'junk' -Encoding UTF8

        Clear-Junk -Force | Out-Null

        Test-Path -LiteralPath (Join-Path $script:TempRepo 'leftover.bak') | Should Be $false
    }

    It 'never removes tracked files even with -Force -Aggressive' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'edit' -Encoding UTF8

        Clear-Junk -Force -Aggressive | Out-Null

        Test-Path -LiteralPath (Join-Path $script:TempRepo 'README.md') | Should Be $true
    }

    It 'every invocation writes a log file' {
        Clear-Junk | Out-Null

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Clear-Junk-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
    }

    It '-Aggressive removes untracked files not in .gitignore when -Force is also supplied' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'random.tmp') -Value 'plain untracked' -Encoding UTF8

        Clear-Junk -Force -Aggressive | Out-Null

        Test-Path -LiteralPath (Join-Path $script:TempRepo 'random.tmp') | Should Be $false
    }
}
