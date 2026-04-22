[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$ProjectPath,

    [Parameter(Mandatory)]
    [string]$Message,

    [string]$RemoteUrl = 'https://github.com/greenmtnsun/GitEasy.git',

    [string]$Branch = 'main',

    [switch]$SkipPull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host ''
    Write-Host "[$stamp] $Text" -ForegroundColor Cyan
}

function Assert-Folder {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Folder not found: $Path"
    }

    (Resolve-Path -LiteralPath $Path).Path
}

function ConvertTo-GitArgumentString {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $escaped = foreach ($arg in $Arguments) {
        if ($null -eq $arg) {
            '""'
        }
        elseif ($arg -match '[\s"]') {
            '"' + ($arg -replace '"', '\"') + '"'
        }
        else {
            $arg
        }
    }

    $escaped -join ' '
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string]$WorkingPath,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [switch]$IgnoreExitCode
    )

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()

    try {
        $argumentString = ConvertTo-GitArgumentString -Arguments $Arguments

        $process = Start-Process `
            -FilePath 'git' `
            -ArgumentList $argumentString `
            -WorkingDirectory $WorkingPath `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = @()
        $stderr = @()

        if (Test-Path -LiteralPath $stdoutFile) {
            $stdout = Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $stderrFile) {
            $stderr = Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue
        }

        $combined = @($stdout) + @($stderr)
        $combined = @($combined | Where-Object { $_ -ne '' })

        $result = [pscustomobject]@{
            Success    = ($process.ExitCode -eq 0)
            ExitCode   = $process.ExitCode
            StdOut     = @($stdout)
            StdErr     = @($stderr)
            Output     = @($combined)
            OutputText = (($combined | Out-String).Trim())
            Command    = 'git {0}' -f $argumentString
        }

        if (-not $result.Success -and -not $IgnoreExitCode) {
            if ($result.OutputText) {
                throw $result.OutputText
            }

            throw "Git command failed: $($result.Command)"
        }

        return $result
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-IsGitRepo {
    param(
        [Parameter(Mandatory)]
        [string]$WorkingPath
    )

    $result = Invoke-Git -WorkingPath $WorkingPath -Arguments @('rev-parse', '--show-toplevel') -IgnoreExitCode
    $result.Success
}

function Get-RepoInfo {
    param(
        [Parameter(Mandatory)]
        [string]$WorkingPath
    )

    $repoRootResult = Invoke-Git -WorkingPath $WorkingPath -Arguments @('rev-parse', '--show-toplevel') -IgnoreExitCode
    if (-not $repoRootResult.Success -or -not $repoRootResult.OutputText) {
        return [pscustomobject]@{
            IsGitRepo      = $false
            RepoRoot       = $null
            Branch         = $null
            RemoteUrl      = $null
            ConnectedTo    = $null
            Service        = 'None'
            ConnectionType = 'None'
        }
    }

    $repoRoot = ($repoRootResult.Output | Select-Object -First 1).Trim()

    $branchResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -IgnoreExitCode
    $branch = if ($branchResult.Success -and $branchResult.OutputText) {
        ($branchResult.Output | Select-Object -First 1).Trim()
    }
    else {
        $null
    }

    $remoteResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('remote', 'get-url', 'origin') -IgnoreExitCode
    $remoteUrl = if ($remoteResult.Success -and $remoteResult.OutputText) {
        ($remoteResult.Output | Select-Object -First 1).Trim()
    }
    else {
        $null
    }

    $service =
        if ($remoteUrl -match 'github\.com') { 'GitHub' }
        elseif ($remoteUrl -match 'gitlab') { 'GitLab' }
        elseif ($remoteUrl) { 'Other' }
        else { 'Not connected' }

    $connectionType =
        if ($remoteUrl -match '^https://') { 'HTTPS' }
        elseif ($remoteUrl -match '^[^@]+@[^:]+:') { 'SSH' }
        elseif ($remoteUrl) { 'Other' }
        else { 'None' }

    $connectedTo = $null
    if ($remoteUrl -and $remoteUrl -match '[:/]([^/]+)/([^/]+?)(?:\.git)?$') {
        $connectedTo = '{0}/{1}' -f $matches[1], $matches[2]
    }
    elseif ($remoteUrl) {
        $connectedTo = $remoteUrl
    }

    [pscustomobject]@{
        IsGitRepo      = $true
        RepoRoot       = $repoRoot
        Branch         = $branch
        RemoteUrl      = $remoteUrl
        ConnectedTo    = $connectedTo
        Service        = $service
        ConnectionType = $connectionType
    }
}

function Test-HasCommit {
    param(
        [Parameter(Mandatory)]
        [string]$WorkingPath
    )

    $result = Invoke-Git -WorkingPath $WorkingPath -Arguments @('rev-parse', '--verify', 'HEAD') -IgnoreExitCode
    ($result.Success -and $result.OutputText)
}

$ProjectPath = Assert-Folder -Path $ProjectPath

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is not installed or not available on PATH.'
}

if ($PSCmdlet.ShouldProcess($ProjectPath, 'Publish GitEasy to GitHub')) {
    if (-not (Test-IsGitRepo -WorkingPath $ProjectPath)) {
        throw "This folder is not a Git repository: $ProjectPath"
    }

    $repo = Get-RepoInfo -WorkingPath $ProjectPath
    $repoRoot = $repo.RepoRoot

    Write-Step 'Setting remote'
    $remoteList = Invoke-Git -WorkingPath $repoRoot -Arguments @('remote') -IgnoreExitCode
    $hasOrigin = @($remoteList.Output) -contains 'origin'

    if ($hasOrigin) {
        Invoke-Git -WorkingPath $repoRoot -Arguments @('remote', 'set-url', 'origin', $RemoteUrl) | Out-Null
    }
    else {
        Invoke-Git -WorkingPath $repoRoot -Arguments @('remote', 'add', 'origin', $RemoteUrl) | Out-Null
    }

    $repo = Get-RepoInfo -WorkingPath $repoRoot

    Write-Step 'Project check'
    Write-Host ("Project folder  : {0}" -f $repo.RepoRoot)
    Write-Host ("Connected to    : {0}" -f $repo.ConnectedTo)
    Write-Host ("Service         : {0}" -f $repo.Service)
    Write-Host ("Connection type : {0}" -f $repo.ConnectionType)
    Write-Host ("Branch          : {0}" -f $(if ($repo.Branch) { $repo.Branch } else { $Branch }))

    $stashCreated = $false
    $stashName = 'Publish-GitEasyToGitHub temporary stash'

    Write-Step 'Checking local changes'
    $preStatus = Invoke-Git -WorkingPath $repoRoot -Arguments @('status', '--porcelain')
    if ($preStatus.OutputText) {
        $preStatus.Output | ForEach-Object { Write-Host $_ }

        Write-Step 'Stashing local changes'
        $stashResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('stash', 'push', '-u', '-m', $stashName) -IgnoreExitCode
        if ($stashResult.OutputText) {
            $stashResult.Output | ForEach-Object { Write-Host $_ }
        }

        if ($stashResult.OutputText -notmatch 'No local changes to save') {
            $stashCreated = $stashResult.Success
        }
    }
    else {
        Write-Host 'No local changes detected.'
    }

    try {
        if (-not $SkipPull) {
            Write-Step 'Checking for peer updates'
            $pullResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('pull', 'origin', $Branch, '--rebase') -IgnoreExitCode
            if ($pullResult.OutputText) {
                $pullResult.Output | ForEach-Object { Write-Host $_ }
            }

            if (-not $pullResult.Success) {
                throw 'Pull failed. Rerun with -SkipPull only if you intentionally want to skip the pull step.'
            }
        }

        if ($stashCreated) {
            Write-Step 'Restoring stashed changes'
            $popResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('stash', 'pop') -IgnoreExitCode
            if ($popResult.OutputText) {
                $popResult.Output | ForEach-Object { Write-Host $_ }
            }

            if (-not $popResult.Success -and $popResult.OutputText -match 'CONFLICT') {
                throw 'Your local changes were restored, but there is a merge conflict. Resolve it, then run the publish script again.'
            }
        }

        Write-Step 'Staging files'
        Invoke-Git -WorkingPath $repoRoot -Arguments @('add', '-A') | Out-Null

        Write-Step 'Commit preview'
        $statusResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('status', '--short')
        if ($statusResult.OutputText) {
            $statusResult.Output | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-Host 'No staged changes found.'
        }

        $hasCommit = Test-HasCommit -WorkingPath $repoRoot
        $hasChanges = [bool]$statusResult.OutputText

        if (-not $hasCommit -and -not $hasChanges) {
            throw 'There is nothing to publish yet. Add files first.'
        }

        Write-Step 'Committing changes'
        if ($hasChanges) {
            $commitResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('commit', "-m=$Message")
            if ($commitResult.OutputText) {
                $commitResult.Output | ForEach-Object { Write-Host $_ }
            }
        }
        else {
            Write-Host 'No new changes to commit.'
        }

        $repo = Get-RepoInfo -WorkingPath $repoRoot
        $pushBranch = if ($repo.Branch) { $repo.Branch } else { $Branch }

        Write-Step 'Pushing changes'
        $pushResult = Invoke-Git -WorkingPath $repoRoot -Arguments @('push', '-u', 'origin', $pushBranch)
        if ($pushResult.OutputText) {
            $pushResult.Output | ForEach-Object { Write-Host $_ }
        }

        Write-Step 'Done'
        Write-Host 'GitEasy GitHub update complete.'
    }
    catch {
        throw
    }
}