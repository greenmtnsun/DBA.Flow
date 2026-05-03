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
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'workarea baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'workarea baseline') | Out-Null
    }
    finally {
        Pop-Location
    }
}

function Get-TestCurrentBranch {
    param([Parameter(Mandatory)][string]$Path)
    Push-Location -LiteralPath $Path
    try {
        $r = Invoke-TestGit -ArgumentList @('symbolic-ref', '--short', 'HEAD') -AllowFailure
        return ($r.Output | Select-Object -First 1)
    }
    finally {
        Pop-Location
    }
}

Describe 'New-WorkBranch' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem      = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo  = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_NWB_$script:Stem")
        $script:TempLogs  = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_NWB_$($script:Stem)_logs")

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

    It 'creates a new working area and switches to it' {
        New-WorkBranch -Name 'feature/test-one'

        $current = Get-TestCurrentBranch -Path $script:TempRepo
        $current | Should Be 'feature/test-one'
    }

    It 'returns a structured object describing the new working area' {
        $result = New-WorkBranch -Name 'feature/test-result'

        $result | Should Not BeNullOrEmpty
        $result.Branch | Should Be 'feature/test-result'
    }

    It 'refuses to create a working area that already exists' {
        New-WorkBranch -Name 'feature/already-here'

        $caught = $null
        try { New-WorkBranch -Name 'feature/already-here' } catch { $caught = $_ }

        $caught | Should Not BeNullOrEmpty
    }

    It 'rejects invalid working-area names' {
        $caught = $null
        try { New-WorkBranch -Name 'has spaces' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }

    It 'every invocation writes a log file with SUCCESS outcome' {
        New-WorkBranch -Name 'feature/log-success'

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'New-WorkBranch-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
        $body = Get-Content -LiteralPath ($logs | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw
        $body | Should Match 'Outcome: SUCCESS'
    }

    It 'plain-English failure surfaces the log path with no raw git word' {
        New-WorkBranch -Name 'feature/already-fail'

        $thrown = $null
        try { New-WorkBranch -Name 'feature/already-fail' } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bgit\b'
    }

    It 'refuses to create a working area while there are unfinished conflicts' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version A`n" -Encoding UTF8
        Save-Work 'baseline' -NoPush

        $baseBranch = Get-TestCurrentBranch -Path $script:TempRepo

        Invoke-TestGit -ArgumentList @('checkout', '-b', 'conflict-feature') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version B`n" -Encoding UTF8
        Save-Work 'feature change' -NoPush

        Invoke-TestGit -ArgumentList @('checkout', $baseBranch) | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version C`n" -Encoding UTF8
        Save-Work 'main change' -NoPush

        Invoke-TestGit -ArgumentList @('merge', 'conflict-feature') -AllowFailure | Out-Null

        $caught = $null
        try { New-WorkBranch -Name 'feature/should-fail-during-conflict' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }
}

Describe 'Switch-Work' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem      = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo  = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SW2_$script:Stem")
        $script:TempLogs  = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SW2_$($script:Stem)_logs")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs

        Push-Location -LiteralPath $script:TempRepo

        $script:BaseBranch = Get-TestCurrentBranch -Path $script:TempRepo

        Invoke-TestGit -ArgumentList @('branch', 'feature/already') | Out-Null
    }

    AfterEach {
        Pop-Location

        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'switches to an existing working area' {
        Switch-Work -Name 'feature/already'

        $current = Get-TestCurrentBranch -Path $script:TempRepo
        $current | Should Be 'feature/already'
    }

    It 'returns a structured object describing the switch' {
        $result = Switch-Work -Name 'feature/already'

        $result | Should Not BeNullOrEmpty
        $result.Branch | Should Be 'feature/already'
    }

    It 'refuses to switch to a working area that does not exist' {
        $caught = $null
        try { Switch-Work -Name 'feature/does-not-exist' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }

    It 'refuses to switch when there are unsaved changes' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'pending.txt') -Value 'unsaved' -Encoding UTF8

        $caught = $null
        try { Switch-Work -Name 'feature/already' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty

        $current = Get-TestCurrentBranch -Path $script:TempRepo
        $current | Should Be $script:BaseBranch
    }

    It 'every invocation writes a log file with SUCCESS outcome' {
        Switch-Work -Name 'feature/already'

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Switch-Work-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
        $body = Get-Content -LiteralPath ($logs | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw
        $body | Should Match 'Outcome: SUCCESS'
    }

    It 'plain-English failure surfaces the log path with no raw git word' {
        $thrown = $null
        try { Switch-Work -Name 'feature/does-not-exist' } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bgit\b'
    }

    It 'refuses to switch while there are unfinished conflicts' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version A`n" -Encoding UTF8
        Save-Work 'baseline' -NoPush

        $baseBranch = Get-TestCurrentBranch -Path $script:TempRepo

        Invoke-TestGit -ArgumentList @('checkout', '-b', 'conflict-feature-sw') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version B`n" -Encoding UTF8
        Save-Work 'feature change' -NoPush

        Invoke-TestGit -ArgumentList @('checkout', $baseBranch) | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version C`n" -Encoding UTF8
        Save-Work 'main change' -NoPush

        Invoke-TestGit -ArgumentList @('merge', 'conflict-feature-sw') -AllowFailure | Out-Null

        $caught = $null
        try { Switch-Work -Name 'feature/already' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }
}
