$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath = Join-Path $ProjectRoot 'GitEasy.psd1'
$ExpectedPublicCommands = @(
    'Clear-Junk',
    'Find-CodeChange',
    'Get-VaultStatus',
    'New-WorkBranch',
    'Reset-Login',
    'Restore-File',
    'Save-Work',
    'Search-History',
    'Set-Ssh',
    'Set-Token',
    'Set-Vault',
    'Show-Diagnostic',
    'Show-History',
    'Show-Remote',
    'Switch-Work',
    'Test-Login',
    'Undo-Changes'
)

Describe 'GitEasy manifest and command surface' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    It 'imports the module' {
        @(Get-Module GitEasy).Count | Should Not Be 0
    }

    It 'exports exactly the classic public commands' {
        $actual = @(Get-Command -Module GitEasy -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $expected = @($ExpectedPublicCommands | Sort-Object)
        ($actual -join '|') | Should Be ($expected -join '|')
    }

    It 'manifest FunctionsToExport matches the classic public commands' {
        $manifest = Import-PowerShellDataFile -LiteralPath $ModulePath
        $actual = @($manifest.FunctionsToExport | Sort-Object)
        $expected = @($ExpectedPublicCommands | Sort-Object)
        ($actual -join '|') | Should Be ($expected -join '|')
    }

    It 'has no parse errors or here-strings in module files' {
        $files = @(
            Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.psm1' -File
            Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.psd1' -File
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Public') -Filter '*.ps1' -File
            Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Private') -Filter '*.ps1' -File
        )

        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
            @($parseErrors).Count | Should Be 0
            @($tokens | Where-Object { $_.Kind.ToString() -like '*HereString*' }).Count | Should Be 0
        }
    }

    It 'private functions use the GE noun prefix' {
        $privateFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Private') -Filter '*.ps1' -File)

        foreach ($file in $privateFiles) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            @($parseErrors).Count | Should Be 0

            $functions = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true))

            foreach ($function in $functions) {
                $function.Name | Should Match '^[A-Za-z]+-GE[A-Za-z0-9]+$'
            }
        }
    }

    It 'implemented commands are no longer stubs' {
        $implemented = @(
            'Save-Work',
            'Test-Login',
            'Set-Token',
            'Set-Vault',
            'Get-VaultStatus',
            'Show-Remote',
            'Show-History',
            'Find-CodeChange',
            'Set-Ssh',
            'Reset-Login',
            'Show-Diagnostic',
            'New-WorkBranch',
            'Switch-Work',
            'Restore-File',
            'Undo-Changes',
            'Clear-Junk',
            'Search-History'
        )

        foreach ($command in $implemented) {
            $path = Join-Path $ProjectRoot "Public\$command.ps1"
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should Not Match 'not wired yet'
        }
    }
}

