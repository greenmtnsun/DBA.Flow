function Update-GitEasyProject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$RemoteUrl,

        [string]$Branch = 'main',

        [switch]$CreateFolder,

        [switch]$SkipPull,

        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        if ($CreateFolder) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
        else {
            throw "The folder does not exist. Create it first or use -CreateFolder."
        }
    }

    $safety = Test-GitEasyPathSafety -Path $Path
    if (-not $safety.Safe) {
        throw $safety.Problem
    }

    $resolvedPath = $safety.Path

    Push-Location $resolvedPath
    try {
        $repoRoot = & git rev-parse --show-toplevel 2>$null
        $isGitProject = ($LASTEXITCODE -eq 0 -and $repoRoot)

        if (-not $isGitProject) {
            Write-Host ''
            Write-Host '[Create project]'
            & git init | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw 'GitEasy could not create a Git project in this folder.'
            }

            & git branch -M $Branch 2>$null | Out-Null
        }

        if ($RemoteUrl) {
            Write-Host ''
            Write-Host '[Set online connection]'
            $remoteNames = & git remote 2>$null
            $hasOrigin = @($remoteNames) -contains 'origin'

            if ($hasOrigin) {
                & git remote set-url origin $RemoteUrl | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    throw 'GitEasy could not update the online connection.'
                }
            }
            else {
                & git remote add origin $RemoteUrl | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    throw 'GitEasy could not add the online connection.'
                }
            }
        }

        $project = Resolve-GitEasyProject -Path $resolvedPath
        $connection = Test-GitEasyConnection -Path $resolvedPath

        Write-Host ''
        Write-Host '[Project check]'
        Write-Host ("Project name    : {0}" -f $project.ProjectName)
        Write-Host ("Project folder  : {0}" -f $project.ProjectFolder)
        Write-Host ("Connected to    : {0}" -f $project.ConnectedTo)
        Write-Host ("Service         : {0}" -f $project.Service)
        Write-Host ("Connection type : {0}" -f $project.ConnectionType)
        Write-Host ("Branch          : {0}" -f $project.Branch)
        Write-Host ("Status          : {0}" -f $connection.Status)

        if ($connection.Problem) {
            Write-Host ("Problem         : {0}" -f $connection.Problem)
        }

        if ($connection.Ready -ne 'Yes') {
            throw ($connection.Problem ? $connection.Problem : 'This project is not ready to update.')
        }

        if ($PSCmdlet.ShouldProcess($project.ProjectFolder, "Update project at $($project.ConnectedTo)")) {
            if (-not $SkipPull) {
                Write-Host ''
                Write-Host '[Check for peer updates]'
                $pullResult = Invoke-GitEasyGit -WorkingPath $project.ProjectFolder -Arguments @('pull', 'origin', $project.Branch, '--rebase') -IgnoreExitCode
                $pullResult.Output | ForEach-Object { Write-Host $_ }

                if (-not $pullResult.Success -and -not $Force) {
                    throw 'Pull failed. Fix the problem or rerun with -SkipPull if you intentionally want to skip the pull step.'
                }
            }

            Write-Host ''
            Write-Host '[Stage files]'
            $addResult = Invoke-GitEasyGit -WorkingPath $project.ProjectFolder -Arguments @('add', '-A')
            $addResult.Output | ForEach-Object { Write-Host $_ }

            Write-Host ''
            Write-Host '[Commit preview]'
            $statusResult = Invoke-GitEasyGit -WorkingPath $project.ProjectFolder -Arguments @('status', '--short')
            $statusResult.Output | ForEach-Object { Write-Host $_ }

            $hasCommit = $true
            $headCheck = & git rev-parse --verify HEAD 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $headCheck) {
                $hasCommit = $false
            }

            if (-not $hasCommit -and -not $statusResult.OutputText) {
                throw 'There is nothing to publish yet. Add files to the project folder first.'
            }

            if ($statusResult.OutputText) {
                Write-Host ''
                Write-Host '[Commit changes]'
                $commitResult = Invoke-GitEasyGit -WorkingPath $project.ProjectFolder -Arguments @('commit', '-m', $Message)
                $commitResult.Output | ForEach-Object { Write-Host $_ }
            }
            else {
                Write-Host ''
                Write-Host '[Commit changes]'
                Write-Host 'No new changes to commit.'
            }

            Write-Host ''
            Write-Host '[Push changes]'
            $pushResult = Invoke-GitEasyGit -WorkingPath $project.ProjectFolder -Arguments @('push', '-u', 'origin', $project.Branch)
            $pushResult.Output | ForEach-Object { Write-Host $_ }

            Write-Host ''
            Write-Host 'Project updated.'
        }
    }
    finally {
        Pop-Location
    }
}