$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ProjectRoot 'GitEasy.psd1'

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
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'history baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'read only baseline') | Out-Null
        Invoke-TestGit -ArgumentList @('remote', 'add', 'origin', 'https://github.com/greenmtnsun/GitEasy.git') | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe 'read-only GitEasy commands' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_ReadOnly_" + [guid]::NewGuid().ToString('N'))
        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Show-Remote reports origin fetch and push remotes' {
        $remotes = @(Show-Remote)
        $remotes.Count | Should Be 2
        @($remotes | Where-Object { $_.Remote -eq 'origin' -and $_.Purpose -eq 'fetch' }).Count | Should Be 1
        @($remotes | Where-Object { $_.Remote -eq 'origin' -and $_.Purpose -eq 'push' }).Count | Should Be 1
        (@($remotes | Select-Object -ExpandProperty Provider -Unique) -contains 'GitHub') | Should Be $true
    }

    It 'Show-History returns recent commits' {
        $history = @(Show-History -Count 5)
        ($history.Count -gt 0) | Should Be $true
        ($history | Select-Object -First 1).Message | Should Be 'read only baseline'
    }

    It 'Find-CodeChange reports a clean tree and then a dirty tree' {
        $clean = Find-CodeChange
        $clean.IsClean | Should Be $true

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'pending change' -Encoding UTF8
        $dirty = Find-CodeChange

        $dirty.IsClean | Should Be $false
        ($dirty.ChangeCount -gt 0) | Should Be $true
        ($dirty.UntrackedCount -gt 0) | Should Be $true
    }

    It 'Find-CodeChange returns an object with PSTypeName GitEasy.CodeChange' {
        $r = Find-CodeChange
        ($r.PSObject.TypeNames -contains 'GitEasy.CodeChange') | Should Be $true
    }

    It 'Find-CodeChange counts an untracked directory as 1 entry, not one per file inside' {
        $dir = Join-Path $script:TempRepo 'untracked-folder'
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'a.txt') -Value 'a' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'b.txt') -Value 'b' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'c.txt') -Value 'c' -Encoding UTF8

        $r = Find-CodeChange
        $r.UntrackedCount | Should Be 1
    }
}

