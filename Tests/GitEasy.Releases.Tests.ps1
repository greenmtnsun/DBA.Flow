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
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'release baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'release baseline') | Out-Null
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

Describe 'New-Release' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_NR_$script:Stem")
        $script:TempBare = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_NR_$($script:Stem)_remote.git")
        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_NR_$($script:Stem)_logs")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        New-TestBareRemote          -Path $script:TempBare
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

    It 'creates a release marker at the current saved point' {
        New-Release -Version v1.0.0 -Note 'first release' -NoPush

        $tags = Invoke-TestGit -ArgumentList @('tag', '--list')
        ($tags.Output -join "`n") | Should Match 'v1\.0\.0'
    }

    It 'records the note as the release annotation' {
        New-Release -Version v1.1.0 -Note 'phase 15 complete' -NoPush

        $msg = Invoke-TestGit -ArgumentList @('tag', '-l', '--format=%(subject)', 'v1.1.0')
        ($msg.Output -join '') | Should Be 'phase 15 complete'
    }

    It 'returns a structured object describing the release' {
        $result = New-Release -Version v0.2.0 -Note 'beta' -NoPush

        $result | Should Not BeNullOrEmpty
        $result.Version | Should Be 'v0.2.0'
        $result.Note    | Should Be 'beta'
    }

    It 'publishes the release marker when a remote is configured' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        New-Release -Version v3.0.0 -Note 'with publish'

        $remoteRefs = Invoke-TestGit -ArgumentList @('ls-remote', '--tags', $script:TempBare)
        ($remoteRefs.Output -join "`n") | Should Match 'refs/tags/v3\.0\.0'
    }

    It 'NoPush keeps the release marker local even when a remote is configured' {
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', $script:TempBare) | Out-Null

        New-Release -Version v4.0.0 -Note 'local only' -NoPush

        $remoteRefs = Invoke-TestGit -ArgumentList @('ls-remote', '--tags', $script:TempBare)
        @($remoteRefs.Output | Where-Object { $_ -match 'v4\.0\.0' }).Count | Should Be 0
    }

    It 'refuses to overwrite an existing release without -Force' {
        New-Release -Version v5.0.0 -Note 'first' -NoPush

        $thrown = $null
        try { New-Release -Version v5.0.0 -Note 'duplicate' -NoPush } catch { $thrown = $_ }

        $thrown | Should Not BeNullOrEmpty
        $thrown.Exception.Message | Should Match '(?i)Details:'

        $userMessage = $thrown.Exception.Message -replace '(?ms)Details:.*$',''
        $userMessage | Should Not Match '(?i)\bupstream\b'
    }

    It 'overwrites an existing release with -Force' {
        New-Release -Version v6.0.0 -Note 'original note' -NoPush
        New-Release -Version v6.0.0 -Note 'replacement note' -NoPush -Force

        $msg = Invoke-TestGit -ArgumentList @('tag', '-l', '--format=%(subject)', 'v6.0.0')
        ($msg.Output -join '') | Should Be 'replacement note'
    }

    It 'every invocation writes a log file' {
        New-Release -Version v7.0.0 -Note 'log test' -NoPush

        $logs = @(Get-ChildItem -LiteralPath $script:TempLogs -Filter 'New-Release-*.log' -File)
        $logs.Count -gt 0 | Should Be $true
        $body = Get-Content -LiteralPath ($logs | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw
        $body | Should Match 'Outcome: SUCCESS'
    }
}

Describe 'Show-Releases' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SR_$script:Stem")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns empty when there are no releases' {
        $r = @(Show-Releases)
        $r.Count | Should Be 0
    }

    It 'lists every release with Version, Date, Note' {
        New-Release -Version v1.0.0 -Note 'first'  -NoPush | Out-Null
        New-Release -Version v1.1.0 -Note 'second' -NoPush | Out-Null

        $r = @(Show-Releases)
        $r.Count | Should Be 2
        $first = $r | Select-Object -First 1
        ($first.PSObject.Properties.Name -contains 'Version') | Should Be $true
        ($first.PSObject.Properties.Name -contains 'Date')    | Should Be $true
        ($first.PSObject.Properties.Name -contains 'Note')    | Should Be $true
    }

    It 'filters by -Pattern' {
        New-Release -Version v1.0.0 -Note 'a'         -NoPush | Out-Null
        New-Release -Version v2.0.0 -Note 'b'         -NoPush | Out-Null
        New-Release -Version beta-1 -Note 'beta tag'  -NoPush | Out-Null

        $r = @(Show-Releases -Pattern 'v*')
        $r.Count | Should Be 2
    }
}
