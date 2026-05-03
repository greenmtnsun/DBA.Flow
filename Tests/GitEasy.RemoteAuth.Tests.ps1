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

function New-TestRepository {
    param([Parameter(Mandatory)] [string]$Path)

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Push-Location -LiteralPath $Path

    try {
        Invoke-TestGit -ArgumentList @('init') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.name', 'GitEasy Pester') | Out-Null
        Invoke-TestGit -ArgumentList @('config', 'user.email', 'giteasy-pester@example.invalid') | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'remote auth baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'remote auth baseline') | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe 'remote and credential helper commands' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_RemoteAuth_" + [guid]::NewGuid().ToString('N'))
        New-TestRepository -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Set-Token rejects embedded credentials' {
        $caught = $null
        try { Set-Token -RemoteUrl 'https://token@github.com/greenmtnsun/GitEasy.git' } catch { $caught = $_ }
        $caught | Should Not BeNullOrEmpty
    }

    It 'Set-Token configures a clean HTTPS origin' {
        Set-Token -RemoteUrl 'https://github.com/greenmtnsun/GitEasy.git'
        $url = (Invoke-TestGit -ArgumentList @('remote', 'get-url', 'origin')).Output | Select-Object -First 1
        $url | Should Be 'https://github.com/greenmtnsun/GitEasy.git'
    }

    It 'Set-Ssh converts an HTTPS origin to SSH' {
        Set-Token -RemoteUrl 'https://github.com/greenmtnsun/GitEasy.git' | Out-Null
        Set-Ssh | Out-Null
        $url = (Invoke-TestGit -ArgumentList @('remote', 'get-url', 'origin')).Output | Select-Object -First 1
        $url | Should Be 'git@github.com:greenmtnsun/GitEasy.git'
    }

    It 'Get-VaultStatus returns a structured object' {
        $status = Get-VaultStatus
        ($status.PSObject.Properties.Name -contains 'CredentialHelper') | Should Be $true
        ($status.PSObject.Properties.Name -contains 'Configured') | Should Be $true
    }
}


