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
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'auth baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'auth baseline') | Out-Null
    }
    finally {
        Pop-Location
    }
}

function New-TestBareRemote {
    param([Parameter(Mandatory)] [string]$Path)

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $Path

    try {
        Invoke-TestGit -ArgumentList @('init', '--bare') | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe 'Test-Login' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_TL_$script:Stem")
        $script:TempBare = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_TL_$($script:Stem)_remote.git")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-TestBareRemote          -Path $script:TempBare

        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempBare -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports Passed=false when no remote is configured' {
        $result = Test-Login
        $result.Passed | Should Be $false
    }

    It 'returns an object with the expected shape' {
        $result = Test-Login

        ($result.PSObject.Properties.Name -contains 'Repository') | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Branch')     | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Remote')     | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Provider')   | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Url')        | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Passed')     | Should Be $true
        ($result.PSObject.Properties.Name -contains 'Message')    | Should Be $true
    }

    It 'reports Passed=true when the remote is reachable' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        $result = Test-Login
        $result.Passed | Should Be $true
    }

    It 'reports Passed=false when the remote URL is bogus' {
        $bogus = 'file:///' + (Join-Path ([System.IO.Path]::GetTempPath()) ('does-not-exist-' + [guid]::NewGuid().ToString('N') + '.git')).Replace('\','/')
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $bogus) | Out-Null

        $result = Test-Login
        $result.Passed | Should Be $false
    }
}

Describe 'Set-Vault' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force

        $script:OriginalHelper = $null
        $r = Invoke-TestGit -ArgumentList @('config', '--global', '--get', 'credential.helper') -AllowFailure
        if ($r.ExitCode -eq 0) {
            $script:OriginalHelper = $r.Output | Select-Object -First 1
        }
    }

    AfterAll {
        if ($null -ne $script:OriginalHelper) {
            Invoke-TestGit -ArgumentList @('config', '--global', 'credential.helper', $script:OriginalHelper) -AllowFailure | Out-Null
        }
        else {
            Invoke-TestGit -ArgumentList @('config', '--global', '--unset', 'credential.helper') -AllowFailure | Out-Null
        }
    }

    It 'sets the global credential helper' {
        Set-Vault -Helper 'manager' | Out-Null

        $r = Invoke-TestGit -ArgumentList @('config', '--global', '--get', 'credential.helper') -AllowFailure
        $r.ExitCode | Should Be 0
        ($r.Output | Select-Object -First 1) | Should Be 'manager'
    }

    It 'returns an object describing the configured helper' {
        $result = Set-Vault -Helper 'wincred'

        $result | Should Not BeNullOrEmpty
        $result.CredentialHelper | Should Be 'wincred'
    }

    It 'rejects helper values outside the validate set' {
        $caught = $null
        try { Set-Vault -Helper 'bogus' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }
}

Describe 'Reset-Login' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_RL_$script:Stem")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_RL_$($script:Stem)_logs")

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

    It 'fails plainly when there is no remote configured' {
        $thrown = $null
        try { Reset-Login } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bgit\b'
    }

    It 'refuses non-HTTPS remotes plainly' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', 'git@example.com:foo/bar.git') | Out-Null

        $thrown = $null
        try { Reset-Login } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bupstream\b'
        $userMessage | Should Not Match '(?i)\bHEAD\b'
        $userMessage | Should Not Match '(?i)\brefspec\b'
    }

    It 'every invocation writes a log file' {
        try { Reset-Login } catch { }

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Reset-Login-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
    }
}
