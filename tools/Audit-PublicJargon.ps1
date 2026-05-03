<#
.SYNOPSIS
Scan the GitEasy public surface for git-jargon leakage.

.DESCRIPTION
Audit-PublicJargon.ps1 walks every Public\*.ps1 file, extracts user-facing strings (Write-Host / Write-Warning / Write-Error / Write-Information / Write-Output / Write-Verbose call arguments and throw expressions) plus parameter names, and flags occurrences of git terminology categorized as HARD (almost certainly should be translated) or SOFT (sticky words like "branch" or "push" that often have no good plain-English replacement and should be reviewed in context).

The script does not modify any files; it produces a report.

.PARAMETER ProjectRoot
Absolute path to the GitEasy source repository. Defaults to C:\Sysadmin\Scripts\GitEasyV2.

.EXAMPLE
.\tools\Audit-PublicJargon.ps1

.NOTES
Companion to the GitEasy "no jargon for users" rule.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Sysadmin\Scripts\GitEasyV2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# STATE CHECK
Write-Host ''
Write-Host 'STATE CHECK: GitEasy public-surface jargon audit' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Missing project folder: $ProjectRoot"
}

$PublicPath = Join-Path $ProjectRoot 'Public'

if (-not (Test-Path -LiteralPath $PublicPath -PathType Container)) {
    throw "Missing Public folder: $PublicPath"
}

$PublicFiles = @(Get-ChildItem -LiteralPath $PublicPath -Filter '*.ps1' -File | Sort-Object Name)

if ($PublicFiles.Count -eq 0) {
    throw "No public command files found in $PublicPath."
}

Write-Host "Public files found: $($PublicFiles.Count)"
Write-Host ''

# Jargon vocabulary
# HARD = almost certainly bad in user-facing text. Translate.
# SOFT = sticky git words; flag for review, not auto-fail. May be acceptable in context.
$HardJargon = @(
    'upstream','downstream','HEAD','refspec','reflog',
    'rebase','rebased','rebasing',
    'fast-forward','fastforward',
    'staged','unstaged','staging',
    'working tree','working directory','working copy',
    'fetch','fetched','fetching',
    'SHA','blob','hunk','detached',
    'tracking branch',
    'cherry-pick','cherrypick',
    'stash','stashed',
    'porcelain'
)

$SoftJargon = @(
    'commit','commits','committed','committing',
    'push','pushed','pushing',
    'pull','pulled','pulling',
    'branch','branches',
    'merge','merged','merging','conflict','conflicts',
    'master','main','origin','remote','remotes',
    'diff','revert','reset','checkout',
    'ahead','behind','diverged'
)

$UserFacingCommands = @(
    'Write-Host','Write-Warning','Write-Error',
    'Write-Information','Write-Output','Write-Verbose'
)

function Test-JargonInText {
    param(
        [string]$Text,
        [string[]]$Terms
    )

    $hits = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $hits }

    foreach ($term in $Terms) {
        $pattern = '(?i)\b' + [regex]::Escape($term) + '\b'
        if ($Text -match $pattern) { $hits += $term }
    }
    return $hits
}

function Test-StringIsUserFacing {
    param([System.Management.Automation.Language.Ast]$Node)

    $parent = $Node.Parent
    while ($parent) {
        if ($parent -is [System.Management.Automation.Language.CommandAst]) {
            $cmdName = $parent.GetCommandName()
            if ($cmdName -and ($script:UserFacingCommands -contains $cmdName)) {
                return $true
            }
            return $false
        }
        if ($parent -is [System.Management.Automation.Language.ThrowStatementAst]) {
            return $true
        }
        $parent = $parent.Parent
    }
    return $false
}

$script:UserFacingCommands = $UserFacingCommands

$Findings = New-Object System.Collections.Generic.List[object]

foreach ($File in $PublicFiles) {
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $File.FullName, [ref]$Tokens, [ref]$ParseErrors
    )

    if ($ParseErrors -and $ParseErrors.Count -gt 0) {
        $Findings.Add([PSCustomObject]@{
            File     = $File.Name
            Severity = 'PARSE'
            Location = '-'
            Term     = '-'
            Text     = "$($ParseErrors.Count) parse error(s)"
        })
        continue
    }

    # 1) Parameter names
    $params = @($Ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.ParameterAst] },
        $true
    ))

    foreach ($p in $params) {
        $name = $p.Name.VariablePath.UserPath

        $hardHits = Test-JargonInText -Text $name -Terms $HardJargon
        foreach ($h in $hardHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'HARD'
                Location = "param -$name"
                Term     = $h
                Text     = "-$name"
            })
        }

        $softHits = Test-JargonInText -Text $name -Terms $SoftJargon
        foreach ($h in $softHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'SOFT'
                Location = "param -$name"
                Term     = $h
                Text     = "-$name"
            })
        }
    }

    # 2) User-facing string literals
    $stringNodes = @($Ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] },
        $true
    ))

    foreach ($sNode in $stringNodes) {
        $text = $sNode.Value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if (-not (Test-StringIsUserFacing -Node $sNode)) { continue }

        $line = $sNode.Extent.StartLineNumber

        $hardHits = Test-JargonInText -Text $text -Terms $HardJargon
        foreach ($h in $hardHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'HARD'
                Location = "line $line"
                Term     = $h
                Text     = $text
            })
        }

        $softHits = Test-JargonInText -Text $text -Terms $SoftJargon
        foreach ($h in $softHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'SOFT'
                Location = "line $line"
                Term     = $h
                Text     = $text
            })
        }
    }

    # 3) ExpandableString literals (double-quoted strings with interpolation) — match against the raw text
    $expandableNodes = @($Ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] },
        $true
    ))

    foreach ($eNode in $expandableNodes) {
        $text = $eNode.Value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if (-not (Test-StringIsUserFacing -Node $eNode)) { continue }

        $line = $eNode.Extent.StartLineNumber

        $hardHits = Test-JargonInText -Text $text -Terms $HardJargon
        foreach ($h in $hardHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'HARD'
                Location = "line $line"
                Term     = $h
                Text     = $text
            })
        }

        $softHits = Test-JargonInText -Text $text -Terms $SoftJargon
        foreach ($h in $softHits) {
            $Findings.Add([PSCustomObject]@{
                File     = $File.Name
                Severity = 'SOFT'
                Location = "line $line"
                Term     = $h
                Text     = $text
            })
        }
    }
}

if ($Findings.Count -eq 0) {
    Write-Host 'No jargon hits found in public surface.' -ForegroundColor Green
    return
}

$Hard  = @($Findings | Where-Object { $_.Severity -eq 'HARD' })
$Soft  = @($Findings | Where-Object { $_.Severity -eq 'SOFT' })
$Parse = @($Findings | Where-Object { $_.Severity -eq 'PARSE' })

if ($Hard.Count -gt 0) {
    Write-Host '--- HARD jargon (translate) ---' -ForegroundColor Red
    $Hard |
        Sort-Object File, Location |
        Format-Table -Property File, Location, Term, Text -AutoSize -Wrap |
        Out-Host
}

if ($Soft.Count -gt 0) {
    Write-Host '--- SOFT jargon (review) ---' -ForegroundColor Yellow
    $Soft |
        Sort-Object File, Location |
        Format-Table -Property File, Location, Term, Text -AutoSize -Wrap |
        Out-Host
}

if ($Parse.Count -gt 0) {
    Write-Host '--- PARSE errors ---' -ForegroundColor Magenta
    $Parse | Format-Table -AutoSize -Wrap | Out-Host
}

Write-Host ''
Write-Host 'Audit summary:' -ForegroundColor Cyan
Write-Host "  Public files audited: $($PublicFiles.Count)"
Write-Host "  HARD jargon hits:     $($Hard.Count)"
Write-Host "  SOFT jargon hits:     $($Soft.Count)"

if ($Parse.Count -gt 0) {
    Write-Host "  Files with parse errors: $($Parse.Count)" -ForegroundColor Magenta
}

if ($Hard.Count -gt 0) {
    Write-Warning 'HARD-jargon terms appear in user-facing strings or parameter names. Translate before shipping.'
}
