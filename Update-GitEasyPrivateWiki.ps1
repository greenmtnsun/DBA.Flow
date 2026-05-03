<#
.SYNOPSIS
Regenerate the GitEasy private-helper wiki pages from the current source.

.DESCRIPTION
Update-GitEasyPrivateWiki.ps1 keeps the Private-*.md wiki pages in sync with the helpers under Private\. It AST-parses every helper, builds the cross-reference of who calls whom from Public\ and Private\, and writes a per-helper page with summary, description (from .DESCRIPTION CBH if present, else verb-based boilerplate), parameters, internal usage, internal examples, safety notes, source file, source, and related pages.

Pages whose helper has been deleted from source are removed automatically.

.PARAMETER ProjectRoot
Absolute path to the GitEasy source repository. Defaults to C:\Sysadmin\Scripts\GitEasyV2.

.PARAMETER WikiRoot
Absolute path to the local clone of the GitEasy GitHub Wiki repo. Defaults to C:\Sysadmin\Scripts\GitEasyV2-GitHubWiki.

.EXAMPLE
.\Update-GitEasyPrivateWiki.ps1

.NOTES
Pairs with Update-GitEasyCommandWiki.ps1 (richer schema for the user-facing public surface).
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Sysadmin\Scripts\GitEasyV2',
    [string]$WikiRoot    = 'C:\Sysadmin\Scripts\GitEasyV2-GitHubWiki'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# STATE CHECK
# ----------------------------------------------------------------------------
Write-Host ''
Write-Host 'STATE CHECK: Update GitEasy private helper wiki pages' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Missing project root: $ProjectRoot"
}

$PrivateRoot = Join-Path $ProjectRoot 'Private'
$PublicRoot  = Join-Path $ProjectRoot 'Public'

if (-not (Test-Path -LiteralPath $PrivateRoot -PathType Container)) {
    throw "Missing Private folder: $PrivateRoot"
}

if (-not (Test-Path -LiteralPath $PublicRoot -PathType Container)) {
    throw "Missing Public folder: $PublicRoot"
}

if (-not (Test-Path -LiteralPath $WikiRoot -PathType Container)) {
    throw "Missing wiki repo: $WikiRoot"
}

if (-not (Test-Path -LiteralPath (Join-Path $WikiRoot '.git') -PathType Container)) {
    throw "Wiki repo is missing its .git folder: $WikiRoot"
}

$PrivateFiles = @(Get-ChildItem -LiteralPath $PrivateRoot -Filter '*.ps1' -File | Sort-Object Name)
$PublicFiles  = @(Get-ChildItem -LiteralPath $PublicRoot  -Filter '*.ps1' -File | Sort-Object Name)

if ($PrivateFiles.Count -eq 0) {
    throw 'No private helper files to document.'
}

Write-Host "Private helper files: $($PrivateFiles.Count)"
Write-Host "Public command files: $($PublicFiles.Count)"
Write-Host "Wiki output:          $WikiRoot"
Write-Host ''

# ----------------------------------------------------------------------------
# Phase 1 - Parse all source files; build function index and call-site index
# ----------------------------------------------------------------------------

function Get-FunctionRecords {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$Area,
        [Parameter(Mandatory)] [string]$ProjectRoot
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "Parse error in $($File.FullName): $($parseErrors[0].Message)"
    }

    $relativePath = $File.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')

    $functions = @($ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    ))

    $records = @()

    foreach ($fn in $functions) {
        $description = ''
        $synopsis    = ''

        $rawText = $ast.Extent.Text
        $help = ''

        $bodyStart = $fn.Body.Extent.StartOffset
        $bodyEnd   = $fn.Body.Extent.EndOffset
        if ($bodyEnd -gt $bodyStart -and $bodyStart -ge 0) {
            $bodyText = $rawText.Substring($bodyStart, $bodyEnd - $bodyStart)
            $insideMatch = [regex]::Match($bodyText, '(?s)<#(.*?)#>')
            if ($insideMatch.Success) {
                $help = $insideMatch.Groups[1].Value
            }
        }

        if ([string]::IsNullOrWhiteSpace($help)) {
            $priorText = $rawText.Substring(0, $fn.Extent.StartOffset)
            $priorBlocks = [regex]::Matches($priorText, '(?s)<#(.*?)#>')
            if ($priorBlocks.Count -gt 0) {
                $help = $priorBlocks[$priorBlocks.Count - 1].Groups[1].Value
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($help)) {
            $synMatch = [regex]::Match($help, '(?is)\.SYNOPSIS\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
            if ($synMatch.Success) {
                $synopsis = ($synMatch.Groups[1].Value -replace '\s+', ' ').Trim()
            }

            $descMatch = [regex]::Match($help, '(?is)\.DESCRIPTION\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
            if ($descMatch.Success) {
                $description = ($descMatch.Groups[1].Value -replace '\s+', ' ').Trim()
            }
        }

        $params = @()
        if ($fn.Body.ParamBlock -and $fn.Body.ParamBlock.Parameters) {
            foreach ($p in $fn.Body.ParamBlock.Parameters) {
                $pName = $p.Name.VariablePath.UserPath
                $pType = ''

                if ($p.StaticType) {
                    $pType = $p.StaticType.Name
                }

                $isMandatory = $false
                $isSwitch    = $false

                foreach ($attr in $p.Attributes) {
                    if ($attr -is [System.Management.Automation.Language.AttributeAst]) {
                        if ($attr.TypeName.Name -eq 'Parameter') {
                            foreach ($na in $attr.NamedArguments) {
                                if ($na.ArgumentName -eq 'Mandatory') {
                                    $isMandatory = $true
                                }
                            }
                        }
                    }
                }

                if ($pType -eq 'SwitchParameter') {
                    $isSwitch = $true
                }

                $params += [PSCustomObject]@{
                    Name      = $pName
                    Type      = $pType
                    Mandatory = $isMandatory
                    Switch    = $isSwitch
                }
            }
        }

        $records += [PSCustomObject]@{
            Name         = $fn.Name
            Area         = $Area
            File         = $File.FullName
            RelativePath = $relativePath
            StartLine    = $fn.Extent.StartLineNumber
            EndLine      = $fn.Extent.EndLineNumber
            Source       = $fn.Extent.Text
            Synopsis     = $synopsis
            Description  = $description
            Parameters   = $params
            Ast          = $fn
            FullAst      = $ast
        }
    }

    return $records
}

$privateRecords = @()
foreach ($file in $PrivateFiles) {
    $privateRecords += Get-FunctionRecords -File $file -Area 'Private' -ProjectRoot $ProjectRoot
}

$publicRecords = @()
foreach ($file in $PublicFiles) {
    $publicRecords += Get-FunctionRecords -File $file -Area 'Public' -ProjectRoot $ProjectRoot
}

$privateNames = @($privateRecords | Select-Object -ExpandProperty Name -Unique)

# Build call-site index: function-name -> @( @{ Caller; CallerArea; File; RelativePath; Line; Snippet } )
$callIndex = @{}
foreach ($name in $privateNames) {
    $callIndex[$name] = @()
}

function Find-EnclosingFunctionName {
    param([System.Management.Automation.Language.Ast]$Node)

    $cur = $Node.Parent
    while ($cur) {
        if ($cur -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            return $cur.Name
        }
        $cur = $cur.Parent
    }
    return ''
}

$allRecords = @()
$allRecords += $privateRecords
$allRecords += $publicRecords

# Walk every file's AST once, collecting CommandAst hits against the private name list.
$seenFiles = @{}
foreach ($rec in $allRecords) {
    if ($seenFiles.ContainsKey($rec.File)) { continue }
    $seenFiles[$rec.File] = $true

    $cmds = @($rec.FullAst.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.CommandAst] },
        $true
    ))

    foreach ($cmdAst in $cmds) {
        $cmdName = $cmdAst.GetCommandName()
        if (-not $cmdName) { continue }
        if (-not ($privateNames -contains $cmdName)) { continue }

        $caller = Find-EnclosingFunctionName -Node $cmdAst

        $snippet = $cmdAst.Extent.Text
        if ($snippet.Length -gt 120) {
            $snippet = $snippet.Substring(0, 117) + '...'
        }

        $callIndex[$cmdName] += [PSCustomObject]@{
            Caller       = $caller
            CallerArea   = $rec.Area
            File         = $rec.File
            RelativePath = $rec.RelativePath
            Line         = $cmdAst.Extent.StartLineNumber
            Snippet      = $snippet
        }
    }
}

# ----------------------------------------------------------------------------
# Phase 2 - Generate per-helper pages
# ----------------------------------------------------------------------------

function Get-DescriptionFallback {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '^([A-Za-z]+)-GE') {
        $verb = $Matches[1]
    }
    else {
        $verb = ''
    }

    $rest = $Name -replace '^[A-Za-z]+-GE',''

    switch ($verb) {
        'Get'      { return "Returns $rest from the active repository." }
        'Test'     { return "Reports whether $rest applies to the active repository." }
        'Assert'   { return "Throws if the safe-save precondition for $rest is not met." }
        'Set'      { return "Configures $rest in the active repository." }
        'Invoke'   { return "Runs $rest and returns the structured result." }
        'Convert'  { return "Converts a $rest representation to another form." }
        'Add'      { return "Appends $rest to an open diagnostic log." }
        'Start'    { return "Opens a diagnostic log session." }
        'Complete' { return "Finalizes a diagnostic log session and writes the outcome." }
        'Remove'   { return "Deletes $rest entries that are past the retention threshold." }
        default    { return "Internal GitEasy helper supporting $rest." }
    }
}

function Get-SafetyNotes {
    param([Parameter(Mandatory)][string]$Name)

    if ($Name -match '^([A-Za-z]+)-GE') {
        $verb = $Matches[1]
    }
    else {
        $verb = ''
    }

    switch ($verb) {
        'Get'      { return @('- Read-only.', '- Does not modify the repository.') }
        'Test'     { return @('- Read-only check.', '- Returns a boolean or structured object; does not modify the repository.') }
        'Assert'   { return @('- Throws a plain-English message when the precondition is not met.', '- Does not modify the repository.') }
        'Set'      { return @('- Modifies repository or environment state.', '- Caller is responsible for confirming the change is intended.') }
        'Invoke'   { return @('- Runs Git directly.', '- Captures stdout and stderr separately so warnings do not poison parsed output.', '- Optional -LogPath appends each step to a diagnostic log.') }
        'Convert'  { return @('- Pure transformation; no I/O.', '- Safe to call repeatedly.') }
        'Add'      { return @('- Appends to an existing log file; does not create one.', '- No-op when the log file is missing.') }
        'Start'    { return @('- Creates the log directory on first use.', '- Prunes logs older than the retention threshold before writing.') }
        'Complete' { return @('- Appends a final outcome marker to the log.', '- No-op when the log file is missing.') }
        'Remove'   { return @('- Only deletes files matching `*.log`.', '- Files newer than the retention threshold are never touched.') }
        default    { return @('- Internal helper. Not part of the supported public surface.') }
    }
}

function New-PrivateWikiPage {
    param(
        [Parameter(Mandatory)][object]$Record,
        [Parameter(Mandatory)][hashtable]$CallIndex
    )

    $name        = $Record.Name
    $description = $Record.Description
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = Get-DescriptionFallback -Name $name
    }

    $callers = @()
    if ($CallIndex.ContainsKey($name)) {
        $callers = $CallIndex[$name]
    }

    $publicCallers  = @($callers | Where-Object { $_.CallerArea -eq 'Public' } | Sort-Object Caller -Unique)
    $privateCallers = @($callers | Where-Object { $_.CallerArea -eq 'Private' -and $_.Caller -ne $name } | Sort-Object Caller -Unique)

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("# Private-$name")
    $lines.Add('')

    # Summary
    $lines.Add('## Summary')
    $lines.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Record.Synopsis)) {
        $lines.Add($Record.Synopsis)
    }
    else {
        $lines.Add("``$name`` is an internal GitEasy helper.")
    }
    $lines.Add('')

    # Description
    $lines.Add('## Description')
    $lines.Add('')
    $lines.Add($description)
    $lines.Add('')

    # Internal Usage
    $lines.Add('## Internal Usage')
    $lines.Add('')

    if ($callers.Count -eq 0) {
        $lines.Add('No other GitEasy code calls this helper directly. It may be called from tests or interactively only.')
    }
    else {
        $lines.Add('Called by:')
        $lines.Add('')

        if ($publicCallers.Count -gt 0) {
            $lines.Add('Public commands:')
            foreach ($c in $publicCallers) {
                if ([string]::IsNullOrWhiteSpace($c.Caller)) {
                    $lines.Add("- ``$($c.RelativePath)`` (top-level)")
                }
                else {
                    $lines.Add("- ``$($c.Caller)`` in ``$($c.RelativePath)``")
                }
            }
            $lines.Add('')
        }

        if ($privateCallers.Count -gt 0) {
            $lines.Add('Private helpers:')
            foreach ($c in $privateCallers) {
                $lines.Add("- ``$($c.Caller)`` in ``$($c.RelativePath)``")
            }
            $lines.Add('')
        }
    }

    # Parameters
    $lines.Add('## Parameters')
    $lines.Add('')
    if ($Record.Parameters.Count -eq 0) {
        $lines.Add('This helper declares no parameters.')
    }
    else {
        $lines.Add('| Name | Type | Required |')
        $lines.Add('| --- | --- | --- |')
        foreach ($p in $Record.Parameters) {
            $required = if ($p.Mandatory) { 'yes' } else { 'no' }
            $type     = if ([string]::IsNullOrWhiteSpace($p.Type)) { '' } else { $p.Type }
            $lines.Add("| ``$($p.Name)`` | ``$type`` | $required |")
        }
    }
    $lines.Add('')

    # Internal Examples
    $lines.Add('## Internal Examples')
    $lines.Add('')

    if ($callers.Count -eq 0) {
        $lines.Add('No live call sites in the current source tree.')
    }
    else {
        $lines.Add('Real call sites in the current source tree:')
        $lines.Add('')
        $lines.Add('```powershell')
        foreach ($c in ($callers | Select-Object -First 5)) {
            $lines.Add($c.Snippet)
        }
        $lines.Add('```')
    }
    $lines.Add('')

    # Safety Notes
    $lines.Add('## Safety Notes')
    $lines.Add('')
    foreach ($note in (Get-SafetyNotes -Name $name)) {
        $lines.Add($note)
    }
    $lines.Add('')

    # Related Public Commands
    $lines.Add('## Related Public Commands')
    $lines.Add('')
    if ($publicCallers.Count -eq 0) {
        $lines.Add('No public command calls this helper directly. It is reached through other helpers.')
    }
    else {
        foreach ($c in $publicCallers) {
            if (-not [string]::IsNullOrWhiteSpace($c.Caller)) {
                $lines.Add("- [[$($c.Caller)|Public-$($c.Caller)]]")
            }
        }
    }
    $lines.Add('')

    # Source File
    $lines.Add('## Source File')
    $lines.Add('')
    $lines.Add("``$($Record.RelativePath)`` (lines $($Record.StartLine)-$($Record.EndLine))")
    $lines.Add('')

    # Source
    $lines.Add('## Source')
    $lines.Add('')
    $lines.Add('```powershell')
    foreach ($srcLine in ($Record.Source -split "`r?`n")) {
        $lines.Add($srcLine)
    }
    $lines.Add('```')
    $lines.Add('')

    # Related Pages
    $lines.Add('## Related Pages')
    $lines.Add('')
    $lines.Add('- [[Home]]')
    $lines.Add('- [[Public Commands|Public-Commands]]')
    $lines.Add('- [[Private Helpers|Private-Helpers]]')
    $lines.Add('- [[Architecture]]')

    $body = ($lines.ToArray() -join "`r`n")
    return $body
}

function Write-WikiFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][string]$Body
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Body + "`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )
}

$generated = New-Object System.Collections.Generic.List[object]

foreach ($rec in ($privateRecords | Sort-Object Name)) {
    $pageBody = New-PrivateWikiPage -Record $rec -CallIndex $callIndex
    $pagePath = Join-Path $WikiRoot ("Private-" + $rec.Name + ".md")
    Write-WikiFile -Path $pagePath -Body $pageBody

    $lineCount = ($pageBody -split "`r?`n").Count

    $generated.Add([PSCustomObject]@{
        Name  = $rec.Name
        Path  = $pagePath
        Lines = $lineCount
    })
}

# ----------------------------------------------------------------------------
# Phase 3 - Regenerate the Private-Helpers index page
# ----------------------------------------------------------------------------

$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('# Private Helpers')
$indexLines.Add('')
$indexLines.Add('These pages document internal GitEasy helpers. They are not part of the public command surface and may change without notice.')
$indexLines.Add('')
$indexLines.Add('| Helper | Source file | Direct callers |')
$indexLines.Add('| --- | --- | --- |')

foreach ($rec in ($privateRecords | Sort-Object Name)) {
    $callerCount = 0
    if ($callIndex.ContainsKey($rec.Name)) {
        $callerCount = ($callIndex[$rec.Name]).Count
    }
    $indexLines.Add("| [[$($rec.Name)|Private-$($rec.Name)]] | ``$($rec.RelativePath)`` | $callerCount |")
}

$indexLines.Add('')
$indexLines.Add('## Related Pages')
$indexLines.Add('')
$indexLines.Add('- [[Home]]')
$indexLines.Add('- [[Public Commands|Public-Commands]]')
$indexLines.Add('- [[Architecture]]')
$indexLines.Add('- [[Troubleshooting]]')

Write-WikiFile -Path (Join-Path $WikiRoot 'Private-Helpers.md') -Body ($indexLines.ToArray() -join "`r`n")

# ----------------------------------------------------------------------------
# Phase 3.5 - Remove orphaned Private-*.md pages (helper deleted from source)
# ----------------------------------------------------------------------------

$validNames = @($privateRecords | Select-Object -ExpandProperty Name -Unique)
$existingPages = @(Get-ChildItem -LiteralPath $WikiRoot -Filter 'Private-*.md' -File | Where-Object { $_.Name -ne 'Private-Helpers.md' })

$removed = @()
foreach ($page in $existingPages) {
    $stem = $page.BaseName -replace '^Private-',''
    if (-not ($validNames -contains $stem)) {
        Remove-Item -LiteralPath $page.FullName -Force
        $removed += $page.Name
    }
}

if ($removed.Count -gt 0) {
    Write-Host ''
    Write-Host 'Removed orphaned wiki pages (helpers no longer exist in source):' -ForegroundColor Yellow
    foreach ($r in $removed) { Write-Host "  $r" }
}

# ----------------------------------------------------------------------------
# Phase 4 - Audit
# ----------------------------------------------------------------------------

$RequiredHeadings = @(
    '## Summary',
    '## Description',
    '## Internal Usage',
    '## Parameters',
    '## Internal Examples',
    '## Safety Notes',
    '## Related Public Commands',
    '## Source File',
    '## Source',
    '## Related Pages'
)

$auditFindings = @()
$pages = @(Get-ChildItem -LiteralPath $WikiRoot -Filter 'Private-*.md' -File | Where-Object { $_.Name -ne 'Private-Helpers.md' })

foreach ($page in $pages) {
    $text = Get-Content -LiteralPath $page.FullName -Raw
    $missing = @()

    foreach ($h in $RequiredHeadings) {
        if ($text -notmatch [regex]::Escape($h)) {
            $missing += $h
        }
    }

    $auditFindings += [PSCustomObject]@{
        Page    = $page.Name
        OK      = ($missing.Count -eq 0)
        Missing = ($missing -join ', ')
    }
}

$incomplete = @($auditFindings | Where-Object { -not $_.OK })

Write-Host ''
Write-Host 'Generated pages:' -ForegroundColor Cyan
foreach ($g in $generated) {
    Write-Host "  $($g.Name) ($($g.Lines) lines)"
}
Write-Host ''
Write-Host "Index page: Private-Helpers.md"
Write-Host ''
Write-Host 'Audit:' -ForegroundColor Cyan
Write-Host "  Pages checked: $($pages.Count)"
Write-Host "  Complete:      $($pages.Count - $incomplete.Count)"
Write-Host "  Incomplete:    $($incomplete.Count)"

if ($incomplete.Count -gt 0) {
    Write-Host ''
    Write-Warning 'Pages still missing required sections:'
    $incomplete | Format-Table -AutoSize
    throw 'Audit failed.'
}

Write-Host ''
Write-Host 'All private helper pages have the required documentation sections.' -ForegroundColor Green
