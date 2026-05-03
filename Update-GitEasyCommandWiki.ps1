<#
.SYNOPSIS
Refresh the GitEasy public-command wiki pages from the current source.

.DESCRIPTION
Update-GitEasyCommandWiki.ps1 keeps the Public-*.md wiki pages in sync with the GitEasy module source. Machine-derivable sections (Syntax, Parameters, Source File, Source) are regenerated from the AST and comment-based help (CBH). Human-authored sections (Summary, Description, When to Use, Examples, Safety Notes, Related Commands) are preserved verbatim from the existing page; new pages get clearly marked TODO stubs.

The script also runs three audits:

  1. Drift report - which machine sections differ from current source.
  2. CBH audit    - which public commands are missing required help blocks.
  3. Stale-claim  - human sections that contain phrases like TODO, "known enhancement", "should be", and other markers that suggest the prose may now be wrong.

It tracks two version stamps in the wiki:

  - Per-page source hash, embedded as <!-- ge-source-sha256: ... -->. Lets dry runs detect drift without re-rendering.
  - Module version watermark, embedded in Public-Commands.md as <!-- ge-module-version: ... -->. Warns when the manifest has bumped since the last refresh.

.PARAMETER ProjectRoot
Absolute path to the GitEasy source repository. Defaults to C:\Sysadmin\Scripts\GitEasyV2.

.PARAMETER WikiRoot
Absolute path to the local clone of the GitEasy GitHub Wiki repo. Defaults to C:\Sysadmin\Scripts\GitEasyV2-GitHubWiki.

.PARAMETER DryRun
Report what would change without writing any files. Reports cover drift, CBH gaps, stale claims, orphan pages, and module-version drift.

.EXAMPLE
.\Update-GitEasyCommandWiki.ps1

Refresh all public-command wiki pages, remove orphans, and audit the result. Fails if any required heading is missing on any page.

.EXAMPLE
.\Update-GitEasyCommandWiki.ps1 -DryRun

Print drift, CBH, stale-claim, orphan, and version reports. Write nothing.

.NOTES
Pairs with Update-GitEasyPrivateWiki.ps1 (same shape, simpler schema for internal docs).
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Sysadmin\Scripts\GitEasyV2',
    [string]$WikiRoot    = 'C:\Sysadmin\Scripts\GitEasyV2-GitHubWiki',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# STATE CHECK
# ----------------------------------------------------------------------------
Write-Host ''
$mode = if ($DryRun) { 'DRY RUN' } else { 'WRITE' }
Write-Host "STATE CHECK: Update GitEasy public-command wiki pages ($mode)" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ProjectRoot -PathType Container)) {
    throw "Missing project root: $ProjectRoot"
}

$PublicRoot = Join-Path $ProjectRoot 'Public'
$ManifestPath = Join-Path $ProjectRoot 'GitEasy.psd1'

if (-not (Test-Path -LiteralPath $PublicRoot -PathType Container)) {
    throw "Missing Public folder: $PublicRoot"
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Missing manifest: $ManifestPath"
}

if (-not (Test-Path -LiteralPath $WikiRoot -PathType Container)) {
    throw "Missing wiki repo: $WikiRoot"
}

if (-not (Test-Path -LiteralPath (Join-Path $WikiRoot '.git') -PathType Container)) {
    throw "Wiki repo is missing its .git folder: $WikiRoot"
}

$PublicFiles = @(Get-ChildItem -LiteralPath $PublicRoot -Filter '*.ps1' -File | Sort-Object Name)

if ($PublicFiles.Count -eq 0) {
    throw 'No public command files to document.'
}

$Manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
$ModuleVersion = [string]$Manifest.ModuleVersion

Write-Host "Public command files: $($PublicFiles.Count)"
Write-Host "Module version:       $ModuleVersion"
Write-Host "Wiki output:          $WikiRoot"
Write-Host ''

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

function Get-CommandHelp {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.Language.FunctionDefinitionAst]$Function,
        [Parameter(Mandatory)] [string]$FullText
    )

    $help = [PSCustomObject]@{
        Synopsis    = ''
        Description = ''
        Examples    = @()
        Notes       = ''
        Links       = @()
        Parameters  = @{}
        Raw         = ''
    }

    # CBH can live either right before the function (outside) or inside the function body
    # before [CmdletBinding] / param. Prefer the inside one when both exist.
    $body = ''

    $bodyStart = $Function.Body.Extent.StartOffset
    $bodyEnd   = $Function.Body.Extent.EndOffset
    if ($bodyEnd -gt $bodyStart -and $bodyStart -ge 0) {
        $bodyText = $FullText.Substring($bodyStart, $bodyEnd - $bodyStart)
        $insideMatch = [regex]::Match($bodyText, '(?s)<#(.*?)#>')
        if ($insideMatch.Success) {
            $body = $insideMatch.Groups[1].Value
        }
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        $priorText = $FullText.Substring(0, $Function.Extent.StartOffset)
        $priorBlocks = [regex]::Matches($priorText, '(?s)<#(.*?)#>')
        if ($priorBlocks.Count -gt 0) {
            $body = $priorBlocks[$priorBlocks.Count - 1].Groups[1].Value
        }
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        return $help
    }

    $help.Raw = $body

    $synMatch = [regex]::Match($body, '(?is)\.SYNOPSIS\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    if ($synMatch.Success) {
        $help.Synopsis = ($synMatch.Groups[1].Value).Trim()
    }

    $descMatch = [regex]::Match($body, '(?is)\.DESCRIPTION\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    if ($descMatch.Success) {
        $help.Description = ($descMatch.Groups[1].Value).Trim()
    }

    $notesMatch = [regex]::Match($body, '(?is)\.NOTES\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    if ($notesMatch.Success) {
        $help.Notes = ($notesMatch.Groups[1].Value).Trim()
    }

    $exampleMatches = [regex]::Matches($body, '(?is)\.EXAMPLE\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    foreach ($m in $exampleMatches) {
        $help.Examples += ($m.Groups[1].Value).Trim()
    }

    $linkMatches = [regex]::Matches($body, '(?is)\.LINK\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    foreach ($m in $linkMatches) {
        $help.Links += ($m.Groups[1].Value).Trim()
    }

    $paramMatches = [regex]::Matches($body, '(?is)\.PARAMETER\s+(\S+)\s+(.*?)(?=\r?\n\s*\.[A-Z]+|\z)')
    foreach ($m in $paramMatches) {
        $name = $m.Groups[1].Value.Trim()
        $text = $m.Groups[2].Value.Trim()
        $help.Parameters[$name] = $text
    }

    return $help
}

function Get-PublicCommandRecord {
    param(
        [Parameter(Mandatory)] [System.IO.FileInfo]$File,
        [Parameter(Mandatory)] [string]$ProjectRoot
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "Parse error in $($File.FullName): $($parseErrors[0].Message)"
    }

    $relativePath = $File.FullName.Substring($ProjectRoot.Length).TrimStart('\','/')
    $rawText = Get-Content -LiteralPath $File.FullName -Raw

    $function = @($ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    )) | Select-Object -First 1

    if (-not $function) {
        throw "No function definition in $($File.FullName)"
    }

    $help = Get-CommandHelp -Function $function -FullText $rawText

    $params = @()
    if ($function.Body.ParamBlock -and $function.Body.ParamBlock.Parameters) {
        foreach ($p in $function.Body.ParamBlock.Parameters) {
            $pName = $p.Name.VariablePath.UserPath
            $pType = ''
            if ($p.StaticType) { $pType = $p.StaticType.Name }

            $isMandatory = $false
            $hasDefault = ($null -ne $p.DefaultValue)

            foreach ($attr in $p.Attributes) {
                if ($attr -is [System.Management.Automation.Language.AttributeAst] -and $attr.TypeName.Name -eq 'Parameter') {
                    foreach ($na in $attr.NamedArguments) {
                        if ($na.ArgumentName -eq 'Mandatory') {
                            $isMandatory = $true
                        }
                    }
                }
            }

            $params += [PSCustomObject]@{
                Name        = $pName
                Type        = $pType
                Mandatory   = $isMandatory
                HasDefault  = $hasDefault
                IsSwitch    = ($pType -eq 'SwitchParameter')
                Description = if ($help.Parameters.ContainsKey($pName)) { $help.Parameters[$pName] } else { '' }
            }
        }
    }

    $supportsShouldProcess = $false
    if ($function.Body.ParamBlock -and $function.Body.ParamBlock.Attributes) {
        foreach ($attr in $function.Body.ParamBlock.Attributes) {
            if ($attr -is [System.Management.Automation.Language.AttributeAst] -and $attr.TypeName.Name -eq 'CmdletBinding') {
                foreach ($na in $attr.NamedArguments) {
                    if ($na.ArgumentName -eq 'SupportsShouldProcess') {
                        $supportsShouldProcess = $true
                    }
                }
            }
        }
    }

    $sourceText = $function.Extent.Text

    $sha = New-Object System.Security.Cryptography.SHA256Managed
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sourceText))
    $sourceHash = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })

    return [PSCustomObject]@{
        Name                  = $function.Name
        File                  = $File.FullName
        RelativePath          = $relativePath
        StartLine             = $function.Extent.StartLineNumber
        EndLine               = $function.Extent.EndLineNumber
        Source                = $sourceText
        SourceHash            = $sourceHash
        Help                  = $help
        Parameters            = $params
        SupportsShouldProcess = $supportsShouldProcess
    }
}

function Build-SyntaxLine {
    param([Parameter(Mandatory)][object]$Record)

    $parts = @($Record.Name)

    foreach ($p in $Record.Parameters) {
        if ($p.IsSwitch) {
            $parts += "[-$($p.Name)]"
        }
        else {
            $bracket = if ($p.Mandatory) { '<>' } else { '[]' }
            $typeText = if ($p.Type) { "<$($p.Type)>" } else { '' }
            if ($p.Mandatory) {
                $parts += "-$($p.Name) $typeText"
            }
            else {
                $parts += "[-$($p.Name) $typeText]"
            }
        }
    }

    if ($Record.SupportsShouldProcess) {
        $parts += '[-WhatIf]'
        $parts += '[-Confirm]'
    }

    return ($parts -join ' ').Trim()
}

function Build-MachineSection-Syntax {
    param([Parameter(Mandatory)][object]$Record)

    return @(
        '## Syntax',
        '',
        '```powershell',
        (Build-SyntaxLine -Record $Record),
        '```',
        ''
    )
}

function Build-MachineSection-Parameters {
    param([Parameter(Mandatory)][object]$Record)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## Parameters')
    $lines.Add('')

    if ($Record.Parameters.Count -eq 0) {
        $lines.Add('This command declares no parameters.')
        $lines.Add('')
        return $lines.ToArray()
    }

    $lines.Add('| Parameter | Type | Required | Description |')
    $lines.Add('| --- | --- | --- | --- |')

    foreach ($p in $Record.Parameters) {
        $required = if ($p.Mandatory) { 'yes' } else { 'no' }
        $type = if ([string]::IsNullOrWhiteSpace($p.Type)) { '' } else { $p.Type }
        $desc = if ([string]::IsNullOrWhiteSpace($p.Description)) { '_(no .PARAMETER help)_' } else { ($p.Description -replace '\|','\|' -replace "`r?`n", ' ') }
        $lines.Add("| ``$($p.Name)`` | ``$type`` | $required | $desc |")
    }

    $lines.Add('')
    return $lines.ToArray()
}

function Build-MachineSection-SourceFile {
    param([Parameter(Mandatory)][object]$Record)

    return @(
        '## Source File',
        '',
        "``$($Record.RelativePath)`` (lines $($Record.StartLine)-$($Record.EndLine))",
        ''
    )
}

function Build-MachineSection-Source {
    param([Parameter(Mandatory)][object]$Record)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## Source')
    $lines.Add('')
    $lines.Add('```powershell')
    foreach ($srcLine in ($Record.Source -split "`r?`n")) {
        $lines.Add($srcLine)
    }
    $lines.Add('```')
    $lines.Add('')
    return $lines.ToArray()
}

function Build-MachineSection-RelatedPages {
    return @(
        '## Related Pages',
        '',
        '- [[Home]]',
        '- [[Public Commands|Public-Commands]]',
        '- [[Private Helpers|Private-Helpers]]',
        '- [[Troubleshooting]]',
        '- [[Known Bugs and Fixes|Known-Bugs-and-Fixes]]',
        ''
    )
}

function Get-PageSections {
    param([string]$PageBody)

    if ([string]::IsNullOrWhiteSpace($PageBody)) {
        return @{}
    }

    $result = [ordered]@{}
    $current = $null
    $buf = New-Object System.Collections.Generic.List[string]

    foreach ($line in ($PageBody -split "`r?`n")) {
        if ($line -match '^##\s+(.+?)\s*$') {
            if ($current) {
                $result[$current] = ($buf.ToArray() -join "`n").TrimEnd()
            }
            $current = $Matches[1].Trim()
            $buf = New-Object System.Collections.Generic.List[string]
        }
        else {
            if ($current) {
                $buf.Add($line)
            }
        }
    }

    if ($current) {
        $result[$current] = ($buf.ToArray() -join "`n").TrimEnd()
    }

    return $result
}

function Build-NewPageBody {
    param(
        [Parameter(Mandatory)][object]$Record,
        [hashtable]$ExistingSections,
        [string]$ModuleVersion
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $($Record.Name)")
    $lines.Add('')

    # Summary
    $lines.Add('## Summary')
    $lines.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Record.Help.Synopsis)) {
        $lines.Add($Record.Help.Synopsis)
    }
    elseif ($ExistingSections -and $ExistingSections.Contains('Summary') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['Summary'])) {
        $lines.Add($ExistingSections['Summary'].Trim())
    }
    else {
        $lines.Add('(TODO: one-line plain-English summary - add .SYNOPSIS to the source.)')
    }
    $lines.Add('')

    # Description
    $lines.Add('## Description')
    $lines.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Record.Help.Description)) {
        $lines.Add($Record.Help.Description)
    }
    elseif ($ExistingSections -and $ExistingSections.Contains('Description') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['Description'])) {
        $lines.Add($ExistingSections['Description'].Trim())
    }
    else {
        $lines.Add('(TODO: multi-paragraph description - add .DESCRIPTION to the source.)')
    }
    $lines.Add('')

    # When to Use - human-only
    $lines.Add('## When to Use')
    $lines.Add('')
    if ($ExistingSections -and $ExistingSections.Contains('When to Use') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['When to Use'])) {
        $lines.Add($ExistingSections['When to Use'].Trim())
    }
    else {
        $lines.Add('(TODO: bulleted list of scenarios where this command is the right tool.)')
    }
    $lines.Add('')

    # Syntax - machine
    foreach ($l in (Build-MachineSection-Syntax -Record $Record)) { $lines.Add($l) }

    # Parameters - machine
    foreach ($l in (Build-MachineSection-Parameters -Record $Record)) { $lines.Add($l) }

    # Examples - prefer CBH .EXAMPLE; fall back to existing wiki; else stub
    $lines.Add('## Examples')
    $lines.Add('')
    if ($Record.Help.Examples -and $Record.Help.Examples.Count -gt 0) {
        $i = 0
        foreach ($ex in $Record.Help.Examples) {
            $i++
            $lines.Add("### Example $i")
            $lines.Add('')
            $lines.Add('```powershell')
            foreach ($exLine in ($ex -split "`r?`n")) {
                $lines.Add($exLine.TrimEnd())
            }
            $lines.Add('```')
            $lines.Add('')
        }
    }
    elseif ($ExistingSections -and $ExistingSections.Contains('Examples') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['Examples'])) {
        $lines.Add($ExistingSections['Examples'].Trim())
        $lines.Add('')
    }
    else {
        $lines.Add('(TODO: one or more example blocks - add .EXAMPLE to the source.)')
        $lines.Add('')
    }

    # Safety Notes - prefer .NOTES; fall back to existing wiki
    $lines.Add('## Safety Notes')
    $lines.Add('')
    if (-not [string]::IsNullOrWhiteSpace($Record.Help.Notes)) {
        $lines.Add($Record.Help.Notes)
    }
    elseif ($ExistingSections -and $ExistingSections.Contains('Safety Notes') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['Safety Notes'])) {
        $lines.Add($ExistingSections['Safety Notes'].Trim())
    }
    else {
        $lines.Add('(TODO: caveats, edge cases, and what the user should know - add .NOTES to the source.)')
    }
    $lines.Add('')

    # Related Commands - prefer CBH .LINK; fall back to existing wiki
    $lines.Add('## Related Commands')
    $lines.Add('')
    if ($Record.Help.Links -and $Record.Help.Links.Count -gt 0) {
        foreach ($link in $Record.Help.Links) {
            $lines.Add("- [[$link|Public-$link]]")
        }
    }
    elseif ($ExistingSections -and $ExistingSections.Contains('Related Commands') -and -not [string]::IsNullOrWhiteSpace($ExistingSections['Related Commands'])) {
        $lines.Add($ExistingSections['Related Commands'].Trim())
    }
    else {
        $lines.Add('(TODO: links to related GitEasy commands - add .LINK to the source.)')
    }
    $lines.Add('')

    # Source File - machine
    foreach ($l in (Build-MachineSection-SourceFile -Record $Record)) { $lines.Add($l) }

    # Source - machine
    foreach ($l in (Build-MachineSection-Source -Record $Record)) { $lines.Add($l) }

    # Related Pages - machine
    foreach ($l in (Build-MachineSection-RelatedPages)) { $lines.Add($l) }

    # Watermarks - machine, hidden
    $lines.Add("<!-- ge-source-sha256: $($Record.SourceHash) -->")
    $lines.Add("<!-- ge-module-version: $ModuleVersion -->")

    return ($lines.ToArray() -join "`r`n")
}

function Get-CBHGaps {
    param([Parameter(Mandatory)][object]$Record)

    $gaps = @()
    if ([string]::IsNullOrWhiteSpace($Record.Help.Synopsis))    { $gaps += '.SYNOPSIS' }
    if ([string]::IsNullOrWhiteSpace($Record.Help.Description)) { $gaps += '.DESCRIPTION' }

    foreach ($p in $Record.Parameters) {
        if (-not $Record.Help.Parameters.ContainsKey($p.Name) -or [string]::IsNullOrWhiteSpace($Record.Help.Parameters[$p.Name])) {
            $gaps += ".PARAMETER $($p.Name)"
        }
    }

    if ($Record.Help.Examples.Count -eq 0) { $gaps += '.EXAMPLE' }

    return $gaps
}

$StaleClaimPatterns = @(
    'TODO','TBD','FIXME','XXX','HACK',
    'not yet','not yet wired','known enhancement','known bug','known issue',
    'should be','will be','pending','planned','in progress','coming soon','out of date'
)

function Get-StaleClaimHits {
    param([string]$PageBody)

    $hits = @()
    if ([string]::IsNullOrWhiteSpace($PageBody)) { return $hits }

    $lineNum = 0
    foreach ($line in ($PageBody -split "`r?`n")) {
        $lineNum++
        foreach ($pat in $StaleClaimPatterns) {
            $regex = '(?i)\b' + [regex]::Escape($pat) + '\b'
            if ($line -match $regex) {
                $hits += [PSCustomObject]@{
                    Line  = $lineNum
                    Term  = $pat
                    Text  = $line.Trim()
                }
            }
        }
    }

    return $hits
}

function Get-DriftReport {
    param(
        [Parameter(Mandatory)][object]$Record,
        [string]$ExistingPageBody
    )

    $drift = [ordered]@{
        Syntax        = 'clean'
        Parameters    = 'clean'
        SourceFile    = 'clean'
        Source        = 'clean'
        RelatedPages  = 'clean'
        SourceHash    = 'clean'
    }

    if ([string]::IsNullOrWhiteSpace($ExistingPageBody)) {
        $drift.Syntax       = 'NEW'
        $drift.Parameters   = 'NEW'
        $drift.SourceFile   = 'NEW'
        $drift.Source       = 'NEW'
        $drift.RelatedPages = 'NEW'
        $drift.SourceHash   = 'NEW'
        return $drift
    }

    $sections = Get-PageSections -PageBody $ExistingPageBody

    $expectedSyntax = (Build-SyntaxLine -Record $Record)
    if ($sections.Contains('Syntax')) {
        $existingSyntax = $sections['Syntax']
        if ($existingSyntax -notmatch [regex]::Escape($expectedSyntax)) {
            $drift.Syntax = 'DRIFT'
        }
    }
    else {
        $drift.Syntax = 'MISSING'
    }

    $existingParamSection = if ($sections.Contains('Parameters')) { $sections['Parameters'] } else { '' }
    $missingParams = @()
    foreach ($p in $Record.Parameters) {
        if ($existingParamSection -notmatch ('\b' + [regex]::Escape($p.Name) + '\b')) {
            $missingParams += $p.Name
        }
    }
    if (-not $sections.Contains('Parameters')) {
        $drift.Parameters = 'MISSING'
    }
    elseif ($missingParams.Count -gt 0) {
        $drift.Parameters = "DRIFT (missing rows: $($missingParams -join ', '))"
    }

    if ($sections.Contains('Source File')) {
        if ($sections['Source File'] -notmatch [regex]::Escape($Record.RelativePath)) {
            $drift.SourceFile = 'DRIFT (path)'
        }
        elseif ($sections['Source File'] -notmatch "lines $($Record.StartLine)-$($Record.EndLine)") {
            $drift.SourceFile = 'DRIFT (line range)'
        }
    }
    else {
        $drift.SourceFile = 'MISSING'
    }

    $hashMatch = [regex]::Match($ExistingPageBody, '<!--\s*ge-source-sha256:\s*([0-9a-f]+)\s*-->')
    if ($hashMatch.Success) {
        if ($hashMatch.Groups[1].Value -ne $Record.SourceHash) {
            $drift.SourceHash = 'DRIFT (hash)'
            if ($drift.Source -eq 'clean') { $drift.Source = 'DRIFT (per hash)' }
        }
    }
    else {
        $drift.SourceHash = 'MISSING'
    }

    if ($sections.Contains('Source')) {
        $existingSource = $sections['Source']
        $expectedSourceFirstLine = ($Record.Source -split "`r?`n")[0]
        if ($existingSource -notmatch [regex]::Escape($expectedSourceFirstLine)) {
            $drift.Source = 'DRIFT (signature differs)'
        }
    }
    else {
        $drift.Source = 'MISSING'
    }

    return $drift
}

# ----------------------------------------------------------------------------
# Phase 1 - Parse all public commands
# ----------------------------------------------------------------------------

$records = @()
foreach ($file in $PublicFiles) {
    $records += Get-PublicCommandRecord -File $file -ProjectRoot $ProjectRoot
}

# ----------------------------------------------------------------------------
# Phase 2 - Collect drift, CBH, stale-claim reports per command
# ----------------------------------------------------------------------------

$reports = @()
foreach ($rec in $records) {
    $pagePath = Join-Path $WikiRoot ("Public-" + $rec.Name + ".md")
    $existingBody = ''
    if (Test-Path -LiteralPath $pagePath -PathType Leaf) {
        $existingBody = Get-Content -LiteralPath $pagePath -Raw
    }

    $drift = Get-DriftReport -Record $rec -ExistingPageBody $existingBody
    $cbhGaps = Get-CBHGaps -Record $rec
    $staleHits = Get-StaleClaimHits -PageBody $existingBody

    $reports += [PSCustomObject]@{
        Name         = $rec.Name
        PagePath     = $pagePath
        ExistingBody = $existingBody
        Drift        = $drift
        CBHGaps      = @($cbhGaps)
        StaleHits    = @($staleHits)
        Record       = $rec
    }
}

# ----------------------------------------------------------------------------
# Phase 3 - Module-version watermark check
# ----------------------------------------------------------------------------

$indexPath = Join-Path $WikiRoot 'Public-Commands.md'
$lastTrackedVersion = ''
if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
    $indexBody = Get-Content -LiteralPath $indexPath -Raw
    $vMatch = [regex]::Match($indexBody, '<!--\s*ge-module-version:\s*([0-9.]+)\s*-->')
    if ($vMatch.Success) {
        $lastTrackedVersion = $vMatch.Groups[1].Value
    }
}

$versionDrift = ($lastTrackedVersion -and $lastTrackedVersion -ne $ModuleVersion)

# ----------------------------------------------------------------------------
# Phase 4 - Print reports
# ----------------------------------------------------------------------------

Write-Host '=== Drift report (machine sections vs current source) ===' -ForegroundColor Cyan
foreach ($r in $reports) {
    $hasDrift = @($r.Drift.Values | Where-Object { $_ -ne 'clean' }).Count -gt 0
    if (-not $hasDrift) { continue }

    Write-Host ''
    Write-Host "  $($r.Name)" -ForegroundColor Yellow
    foreach ($k in $r.Drift.Keys) {
        $v = $r.Drift[$k]
        if ($v -ne 'clean') {
            Write-Host "    $k`: $v"
        }
    }
}

$cleanCount = @($reports | Where-Object { @($_.Drift.Values | Where-Object { $_ -ne 'clean' }).Count -eq 0 }).Count
Write-Host ''
Write-Host "  Clean pages: $cleanCount / $($reports.Count)"

Write-Host ''
Write-Host '=== Comment-based help audit ===' -ForegroundColor Cyan
$cbhClean = 0
foreach ($r in $reports) {
    $gapCount = @($r.CBHGaps).Count
    if ($gapCount -eq 0) {
        $cbhClean++
        continue
    }
    Write-Host ''
    Write-Host "  $($r.Name) - CBH gaps:" -ForegroundColor Yellow
    foreach ($g in $r.CBHGaps) {
        Write-Host "    - missing $g"
    }
}
Write-Host ''
Write-Host "  Commands with full CBH: $cbhClean / $($reports.Count)"

Write-Host ''
Write-Host '=== Stale-claim report (human sections of existing pages) ===' -ForegroundColor Cyan
$staleClean = 0
foreach ($r in $reports) {
    $hitCount = @($r.StaleHits).Count
    if ($hitCount -eq 0) {
        $staleClean++
        continue
    }
    Write-Host ''
    Write-Host "  $($r.Name)" -ForegroundColor Yellow
    foreach ($h in $r.StaleHits) {
        $textShort = if ($h.Text.Length -gt 100) { $h.Text.Substring(0, 97) + '...' } else { $h.Text }
        Write-Host "    line $($h.Line) [$($h.Term)]: $textShort"
    }
}
Write-Host ''
Write-Host "  Pages without stale-claim hits: $staleClean / $($reports.Count)"

Write-Host ''
Write-Host '=== Module-version watermark ===' -ForegroundColor Cyan
if (-not $lastTrackedVersion) {
    Write-Host "  No prior watermark in Public-Commands.md (first refresh)."
}
elseif ($versionDrift) {
    Write-Host "  DRIFT: wiki was last refreshed at $lastTrackedVersion; current manifest is $ModuleVersion." -ForegroundColor Yellow
}
else {
    Write-Host "  Clean. Wiki and manifest both at $ModuleVersion."
}

# ----------------------------------------------------------------------------
# Phase 5 - Orphan removal (dry-run reports only; write deletes)
# ----------------------------------------------------------------------------

$validNames = @($records | Select-Object -ExpandProperty Name -Unique)
$existingPages = @(Get-ChildItem -LiteralPath $WikiRoot -Filter 'Public-*.md' -File | Where-Object { $_.Name -ne 'Public-Commands.md' })
$orphans = @()
foreach ($page in $existingPages) {
    $stem = $page.BaseName -replace '^Public-',''
    if (-not ($validNames -contains $stem)) {
        $orphans += $page
    }
}

if ($orphans.Count -gt 0) {
    Write-Host ''
    Write-Host '=== Orphan pages (helper deleted from source) ===' -ForegroundColor Cyan
    foreach ($o in $orphans) {
        Write-Host "  $($o.Name)"
    }
}

# ----------------------------------------------------------------------------
# Phase 6 - DryRun stops here
# ----------------------------------------------------------------------------

if ($DryRun) {
    Write-Host ''
    Write-Host 'DRY RUN: no files written.' -ForegroundColor Cyan
    return
}

# ----------------------------------------------------------------------------
# Phase 7 - Write pages
# ----------------------------------------------------------------------------

Write-Host ''
Write-Host '=== Writing pages ===' -ForegroundColor Cyan
$written = 0
foreach ($r in $reports) {
    $sections = Get-PageSections -PageBody $r.ExistingBody
    $body = Build-NewPageBody -Record $r.Record -ExistingSections $sections -ModuleVersion $ModuleVersion

    [System.IO.File]::WriteAllText(
        $r.PagePath,
        $body + "`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $written++
}
Write-Host "  Wrote $written public-command pages."

if ($orphans.Count -gt 0) {
    Write-Host ''
    Write-Host '=== Removing orphans ===' -ForegroundColor Cyan
    foreach ($o in $orphans) {
        Remove-Item -LiteralPath $o.FullName -Force
        Write-Host "  Removed $($o.Name)"
    }
}

# Public-Commands.md index
$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('# Public Commands')
$indexLines.Add('')
$indexLines.Add('These pages document the supported GitEasy command surface. Prefer GitEasy commands before raw Git commands.')
$indexLines.Add('')
$indexLines.Add('| Command | Source file | Synopsis |')
$indexLines.Add('| --- | --- | --- |')
foreach ($rec in ($records | Sort-Object Name)) {
    $syn = if ([string]::IsNullOrWhiteSpace($rec.Help.Synopsis)) { '_(no .SYNOPSIS)_' } else { ($rec.Help.Synopsis -replace '\|','\|' -replace "`r?`n", ' ') }
    $indexLines.Add("| [[$($rec.Name)|Public-$($rec.Name)]] | ``$($rec.RelativePath)`` | $syn |")
}
$indexLines.Add('')
$indexLines.Add('## Related Pages')
$indexLines.Add('')
$indexLines.Add('- [[Home]]')
$indexLines.Add('- [[Private Helpers|Private-Helpers]]')
$indexLines.Add('- [[Architecture]]')
$indexLines.Add('- [[Troubleshooting]]')
$indexLines.Add('')
$indexLines.Add("<!-- ge-module-version: $ModuleVersion -->")

[System.IO.File]::WriteAllText(
    $indexPath,
    (($indexLines.ToArray() -join "`r`n") + "`r`n"),
    [System.Text.UTF8Encoding]::new($false)
)

# ----------------------------------------------------------------------------
# Phase 8 - Final audit
# ----------------------------------------------------------------------------

$RequiredHeadings = @(
    '## Summary',
    '## Description',
    '## When to Use',
    '## Syntax',
    '## Parameters',
    '## Examples',
    '## Safety Notes',
    '## Related Commands',
    '## Source File',
    '## Source',
    '## Related Pages'
)

$auditFindings = @()
$pages = @(Get-ChildItem -LiteralPath $WikiRoot -Filter 'Public-*.md' -File | Where-Object { $_.Name -ne 'Public-Commands.md' })
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
Write-Host '=== Final audit ===' -ForegroundColor Cyan
Write-Host "  Pages checked: $($pages.Count)"
Write-Host "  Complete:      $($pages.Count - $incomplete.Count)"
Write-Host "  Incomplete:    $($incomplete.Count)"
if ($incomplete.Count -gt 0) {
    Write-Warning 'Pages still missing required sections:'
    $incomplete | Format-Table -AutoSize
    throw 'Audit failed.'
}

Write-Host ''
Write-Host 'All public-command wiki pages have the required sections.' -ForegroundColor Green
