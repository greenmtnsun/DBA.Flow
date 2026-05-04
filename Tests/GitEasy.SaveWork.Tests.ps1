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

function New-TestRepository {
    param([Parameter(Mandatory)] [string]$Path)

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $Path

    try {
        Invoke-TestGit -ArgumentList @('init') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.name', 'GitEasy Pester') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.email', 'giteasy-pester@example.invalid') | Out-Null
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

Describe 'Save-Work — new contract' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SW_$script:Stem")
        $script:TempBare = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SW_$($script:Stem)_remote.git")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SW_$($script:Stem)_logs")

        New-TestRepository  -Path $script:TempRepo
        New-TestBareRemote  -Path $script:TempBare
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs

        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location

        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempBare -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates the first commit when called with NoPush' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'first save' -Encoding UTF8

        Save-Work 'initial commit' -NoPush

        $log = Invoke-TestGit -ArgumentList @('log', '--oneline', '-1')
        ($log.Output -join ' ') | Should Match 'initial commit'

        $status = Invoke-TestGit -ArgumentList @('status', '--porcelain=v1')
        @($status.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should Be 0
    }

    It 'reports nothing to save when working tree is clean and branch is up to date' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'baseline content' -Encoding UTF8
        Save-Work 'baseline' -NoPush

        $before = (Invoke-TestGit -ArgumentList @('rev-parse', 'HEAD')).Output | Select-Object -First 1
        $messages = & { Save-Work 'should-noop' -NoPush } *>&1
        $after = (Invoke-TestGit -ArgumentList @('rev-parse', 'HEAD')).Output | Select-Object -First 1

        $after | Should Be $before
        ($messages -join ' ') | Should Match 'No changes to save'
    }

    It 'publishes a clean branch that is ahead of the remote' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'a.txt') -Value 'first commit' -Encoding UTF8
        Save-Work 'first work' -NoPush

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'b.txt') -Value 'second commit' -Encoding UTF8
        Save-Work 'second work' -NoPush

        Save-Work

        $remoteRefs = Invoke-TestGit -ArgumentList @('ls-remote', $script:TempBare)
        @($remoteRefs.Output | Where-Object { $_ -match 'refs/heads/' }).Count -gt 0 | Should Be $true
    }

    It 'first save with no upstream auto-publishes when a remote exists' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'first save with publish' -Encoding UTF8
        Save-Work 'auto-publish first save'

        $remoteRefs = Invoke-TestGit -ArgumentList @('ls-remote', $script:TempBare)
        @($remoteRefs.Output | Where-Object { $_ -match 'refs/heads/' }).Count -gt 0 | Should Be $true
    }

    It 'NoPush leaves work local even when a remote is configured' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'np test' -Encoding UTF8
        Save-Work 'local only' -NoPush

        $remoteRefs = Invoke-TestGit -ArgumentList @('ls-remote', $script:TempBare)
        @($remoteRefs.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should Be 0
    }

    It 'commit messages have no UTF-8 BOM' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'bom test' -Encoding UTF8
        Save-Work 'bom-free message' -NoPush

        $sha = (Invoke-TestGit -ArgumentList @('rev-parse', 'HEAD')).Output | Select-Object -First 1
        $cat = Invoke-TestGit -ArgumentList @('cat-file', 'commit', $sha)

        $blankIndex = -1
        for ($i = 0; $i -lt $cat.Output.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($cat.Output[$i])) { $blankIndex = $i; break }
        }

        $messageStart = if ($blankIndex -ge 0) { $blankIndex + 1 } else { 0 }
        $message = ($cat.Output[$messageStart..($cat.Output.Count - 1)] -join "`n").Trim()

        $message | Should Be 'bom-free message'

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
    }

    It 'LF-only files do not block save when autocrlf is enabled' {
        Invoke-TestGit -ArgumentList @('config', 'core.autocrlf', 'true') | Out-Null

        $lfPath = Join-Path $script:TempRepo 'lf.txt'
        [System.IO.File]::WriteAllText($lfPath, "line one`nline two`n", [System.Text.UTF8Encoding]::new($false))

        $thrown = $null
        try { Save-Work 'lf-warning test' -NoPush } catch { $thrown = $_ }
        $thrown | Should BeNullOrEmpty
    }

    It 'real merge conflicts block save with a plain-English message' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version A`n" -Encoding UTF8
        Save-Work 'baseline for merge conflict' -NoPush

        $baseBranch = Get-TestCurrentBranch -Path $script:TempRepo

        Invoke-TestGit -ArgumentList @('checkout', '-b', 'feature') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version B`n" -Encoding UTF8
        Save-Work 'feature change' -NoPush

        Invoke-TestGit -ArgumentList @('checkout', $baseBranch) | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "version C`n" -Encoding UTF8
        Save-Work 'base change' -NoPush

        $merge = Invoke-TestGit -ArgumentList @('merge', 'feature') -AllowFailure

        @($merge.Output | Where-Object { $_ -match 'CONFLICT' }).Count -gt 0 | Should Be $true

        $thrown = $null
        try { Save-Work 'attempt save during conflict' -NoPush } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Not Match '(?i)\bgit\b'
    }

    It 'every save invocation writes a log file with SUCCESS outcome' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'log test' -Encoding UTF8
        Save-Work 'logs-success' -NoPush

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Save-Work-*.log' -File)
        $logs.Count | Should Be 1

        $body = Get-Content -LiteralPath $logs[0].FullName -Raw
        $body | Should Match 'Outcome: SUCCESS'
        $body | Should Match 'Command:\s*Save-Work'
    }

    It 'logs failures and surfaces the path in the thrown message' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'fail test' -Encoding UTF8
        Save-Work 'baseline for failure' -NoPush

        $bogusUrl = 'file:///' + (Join-Path ([System.IO.Path]::GetTempPath()) ('does-not-exist-' + [guid]::NewGuid().ToString('N') + '.git')).Replace('\','/')
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $bogusUrl) | Out-Null

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'next change' -Encoding UTF8

        $thrown = $null
        try { Save-Work 'will-fail-on-publish' } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'Save-Work-*.log' -File | Sort-Object LastWriteTime)
        $logs.Count -gt 0 | Should Be $true

        $body = Get-Content -LiteralPath $logs[-1].FullName -Raw
        $body | Should Match 'Outcome: FAILURE'
    }

    It 'plain-English error message does not contain the word git' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'README.md') -Value 'plain test' -Encoding UTF8
        Save-Work 'plain baseline' -NoPush

        $bogusUrl = 'file:///' + (Join-Path ([System.IO.Path]::GetTempPath()) ('does-not-exist-' + [guid]::NewGuid().ToString('N') + '.git')).Replace('\','/')
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $bogusUrl) | Out-Null

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change2.txt') -Value 'plain change' -Encoding UTF8

        $thrown = $null
        try { Save-Work 'will-fail-plain' } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bgit\b'
        $userMessage | Should Not Match '(?i)\bupstream\b'
        $userMessage | Should Not Match '(?i)\bHEAD\b'
        $userMessage | Should Not Match '(?i)\brefspec\b'
    }

    It 'busy repo state (active merge) blocks save with a plain-English message' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "busy A`n" -Encoding UTF8
        Save-Work 'busy baseline' -NoPush

        $baseBranch = Get-TestCurrentBranch -Path $script:TempRepo

        Invoke-TestGit -ArgumentList @('checkout', '-b', 'busyfeat') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "busy B`n" -Encoding UTF8
        Save-Work 'busyfeat change' -NoPush

        Invoke-TestGit -ArgumentList @('checkout', $baseBranch) | Out-Null
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'shared.txt') -Value "busy C`n" -Encoding UTF8
        Save-Work 'base busy change' -NoPush

        $merge = Invoke-TestGit -ArgumentList @('merge', 'busyfeat') -AllowFailure
        @($merge.Output | Where-Object { $_ -match 'CONFLICT' }).Count -gt 0 | Should Be $true

        $thrown = $null
        try { Save-Work 'attempt during busy' -NoPush } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
    }
}
