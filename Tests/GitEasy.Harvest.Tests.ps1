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
        Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'baseline' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'baseline') | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe 'Search-History' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_SH_$script:Stem")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'data.sql') -Value 'CREATE TABLE Foo;' -Encoding UTF8
        Save-Work 'Add Foo table' -NoPush

        Add-Content -LiteralPath (Join-Path $script:TempRepo 'data.sql') -Value 'DROP TABLE Foo;'
        Save-Work 'Drop Foo table' -NoPush

        Add-Content -LiteralPath (Join-Path $script:TempRepo 'data.sql') -Value 'CREATE TABLE Bar;'
        Save-Work 'Add Bar table' -NoPush
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds saved points that touched a string' {
        $hits = @(Search-History -Pattern 'DROP TABLE Foo')
        $hits.Count -gt 0 | Should Be $true
    }

    It 'returns objects with Hash, Date, Author, Message' {
        $hits = @(Search-History -Pattern 'CREATE TABLE Foo')
        $first = $hits | Select-Object -First 1
        ($first.PSObject.Properties.Name -contains 'Hash')    | Should Be $true
        ($first.PSObject.Properties.Name -contains 'Date')    | Should Be $true
        ($first.PSObject.Properties.Name -contains 'Author')  | Should Be $true
        ($first.PSObject.Properties.Name -contains 'Message') | Should Be $true
    }

    It '-Patch adds a Change property with the diff text' {
        $hits = @(Search-History -Pattern 'DROP TABLE Foo' -Patch)
        $first = $hits | Select-Object -First 1
        ($first.PSObject.Properties.Name -contains 'Change') | Should Be $true
        $first.Change | Should Match 'DROP TABLE Foo'
    }

    It 'returns empty when no saved point touched the pattern' {
        $hits = @(Search-History -Pattern 'NonExistentString12345')
        $hits.Count | Should Be 0
    }
}

Describe 'Show-History -Graph' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_Graph_$script:Stem")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'does not throw when -Graph is supplied' {
        { Show-History -Graph } | Should Not Throw
    }
}

Describe 'Save-Work -BumpVersion' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_BV_$script:Stem")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo

        Set-Content -LiteralPath (Join-Path $script:TempRepo 'TestModule.psd1') -Encoding UTF8 -Value @"
@{
    RootModule = 'TestModule.psm1'
    ModuleVersion = '1.2.3'
    GUID = '00000000-0000-0000-0000-000000000099'
    Author = 'Test'
}
"@
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'TestModule.psm1') -Value 'function Test-Func {}' -Encoding UTF8
        Invoke-TestGit -ArgumentList @('add', '-A') | Out-Null
        Invoke-TestGit -ArgumentList @('commit', '-m', 'add test module manifest') | Out-Null
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'bumps the Build segment by default' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'change' -Encoding UTF8
        Save-Work 'change' -NoPush -BumpVersion

        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:TempRepo 'TestModule.psd1')
        $manifest.ModuleVersion | Should Be '1.2.4'
    }

    It 'bumps the Minor segment when -BumpKind Minor is supplied' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'change' -Encoding UTF8
        Save-Work 'change' -NoPush -BumpVersion -BumpKind Minor

        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:TempRepo 'TestModule.psd1')
        $manifest.ModuleVersion | Should Be '1.3.0'
    }

    It 'bumps the Major segment when -BumpKind Major is supplied' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'change' -Encoding UTF8
        Save-Work 'change' -NoPush -BumpVersion -BumpKind Major

        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:TempRepo 'TestModule.psd1')
        $manifest.ModuleVersion | Should Be '2.0.0'
    }

    It 'prefixes the saved-point message with the new version' {
        Set-Content -LiteralPath (Join-Path $script:TempRepo 'change.txt') -Value 'change' -Encoding UTF8
        Save-Work 'fix the thing' -NoPush -BumpVersion -BumpKind Minor

        $log = Invoke-TestGit -ArgumentList @('log', '-1', '--pretty=%s')
        ($log.Output -join '') | Should Match '^\[v1\.3\.0\] fix the thing$'
    }
}

Describe 'Set-Vault -WriteIgnoreList' {
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

    BeforeEach {
        $script:Stem     = [guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:TempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_WIL_$script:Stem")

        New-TestRepositoryWithCommit -Path $script:TempRepo
        Push-Location -LiteralPath $script:TempRepo
    }

    AfterEach {
        Pop-Location
        Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes a starter .gitignore when one does not exist' {
        Set-Vault -WriteIgnoreList | Out-Null

        $ignorePath = Join-Path $script:TempRepo '.gitignore'
        Test-Path -LiteralPath $ignorePath | Should Be $true

        $body = Get-Content -LiteralPath $ignorePath -Raw
        $body | Should Match '\*\.bak'
        $body | Should Match 'bin/'
        $body | Should Match 'obj/'
    }

    It 'preserves existing .gitignore content and only appends missing patterns' {
        $ignorePath = Join-Path $script:TempRepo '.gitignore'
        Set-Content -LiteralPath $ignorePath -Value 'my-custom-pattern' -Encoding UTF8

        Set-Vault -WriteIgnoreList | Out-Null

        $body = Get-Content -LiteralPath $ignorePath -Raw
        $body | Should Match 'my-custom-pattern'
        $body | Should Match '\*\.bak'
    }

    It 'reports how many patterns were added' {
        $result = Set-Vault -WriteIgnoreList

        $result.IgnoreList | Should Not BeNullOrEmpty
        ($result.IgnoreList.PSObject.Properties.Name -contains 'Added') | Should Be $true
    }
}
