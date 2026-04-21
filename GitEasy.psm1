## --- 1. CONNECTIVITY & SETUP ---

function Set-Vault {
    <#
    .SYNOPSIS
        Connects a folder to GitLab. Standardizes the .gitignore for DBA ecosystems.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GitLabUrl,
        [string]$UserEmail,
        [string]$UserName
    )

    if (-not (Test-Path ".git")) {
        Write-Host "Initializing new Vault..." -ForegroundColor Cyan
        git init
        git remote add origin $GitLabUrl

        # Comprehensive ignore list for SQL/SSIS/RDL/PS
        $ignore = @(
            "*.user", "*.suo", "*.tmp", "*.log", "*.bak", # User/Temp noise
            "bin/", "obj/", "TestResults/",               # Build artifacts
            ".vs/", ".idea/", ".vscode/",                 # IDE noise
            "*.pfx", "secrets.json", "*.rdl.data"         # Security/Cache
        )
        $ignore | Out-File ".gitignore" -Encoding utf8 -Force
    }

    # Set local identity if provided (prevents "Who am I?" errors)
    if ($UserEmail) { git config user.email $UserEmail }
    if ($UserName)  { git config user.name $UserName }

    git branch -M main
    Write-Host "Vault linked to: $GitLabUrl" -ForegroundColor Green
}

function Show-Remote {
    <#
    .SYNOPSIS
        Shows where this Vault points online.
    #>
    [CmdletBinding()]
    param()

    git remote -v
}

function Set-Token {
    <#
    .SYNOPSIS
        Sets the online address and clears old saved login so Git can ask for a token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WebAddress
    )

    git remote set-url origin $WebAddress
    Reset-Login

    Write-Host "Web address set for origin." -ForegroundColor Green
    Write-Host "Next time Git asks for a password, paste your token instead." -ForegroundColor Cyan
}

function Set-Ssh {
    <#
    .SYNOPSIS
        Switches the online address to SSH style.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SshAddress
    )

    git remote set-url origin $SshAddress
    Write-Host "SSH address set for origin." -ForegroundColor Green
}

function Reset-Login {
    <#
    .SYNOPSIS
        Clears saved login for the current online host.
    #>
    [CmdletBinding()]
    param(
        [string]$HostName
    )

    if (-not $HostName) {
        $remote = git remote get-url origin 2>$null
        if (-not $remote) {
            Write-Warning "No online address found for origin."
            return
        }

        if ($remote -match 'https?://([^/]+)') {
            $HostName = $Matches[1]
        }
        elseif ($remote -match '@([^:]+):') {
            $HostName = $Matches[1]
        }
        else {
            Write-Warning "Could not figure out the host name from the current online address."
            return
        }
    }

    Write-Host "Clearing saved login for $HostName ..." -ForegroundColor Yellow

    $deletedSomething = $false

    if (Get-Command cmdkey.exe -ErrorAction SilentlyContinue) {
        $targets = @(
            "git:$HostName",
            "git:https://$HostName",
            "LegacyGeneric:target=git:https://$HostName",
            "LegacyGeneric:target=git:$HostName"
        )

        foreach ($target in $targets) {
            cmdkey.exe /delete:$target *> $null
        }

        $deletedSomething = $true
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $helper = git config --global credential.helper 2>$null
            if ($helper -match 'manager') {
                $credentialInput = "protocol=https`nhost=$HostName`n"
                $credentialInput | git credential-manager erase *> $null
                $deletedSomething = $true
            }
        }
        catch {
            # Ignore helper cleanup failures. cmdkey cleanup is still useful.
        }
    }

    if ($deletedSomething) {
        Write-Host "Saved login cleanup attempted for $HostName." -ForegroundColor Green
    }
    else {
        Write-Warning "Could not find a supported saved-login tool on this machine."
    }
}

function Test-Login {
    <#
    .SYNOPSIS
        Safely checks whether this Vault can talk to the online remote.
    #>
    [CmdletBinding()]
    param()

    $output = git ls-remote origin 2>&1
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        Write-Host "Login works. Git can reach the online remote." -ForegroundColor Green
        return $true
    }

    Write-Warning "Git could not reach the online remote with the current login."
    $output | ForEach-Object { Write-Host $_ }
    Write-Host "Try Set-Token, Set-Ssh, or Reset-Login." -ForegroundColor Yellow
    return $false
}

## --- 2. THE SYNC ENGINE ---
function Save-Work {
    <#
    .SYNOPSIS
        Snapshots every file and pushes to GitHub or GitLab.
        Handles module versioning and shows clearer errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Note,
        [switch]$NewVersion,
        [ValidateSet('Major', 'Minor', 'Build', 'Revision')]
        [string]$BumpType = 'Revision'
    )

    function Invoke-GitEasyGit {
        param(
            [Parameter(Mandatory = $true)][string]$Step,
            [Parameter(Mandatory = $true)][string[]]$Arguments
        )

        Write-Host ""
        Write-Host "[$Step]" -ForegroundColor Cyan
        Write-Host ("git " + ($Arguments -join ' ')) -ForegroundColor DarkGray

        $output = & git @Arguments 2>&1
        $exitCode = $LASTEXITCODE

        if ($output) {
            $output | ForEach-Object { Write-Host $_ }
        }

        if ($exitCode -ne 0) {
            throw "Git step failed: $Step (exit code $exitCode)"
        }

        [pscustomobject]@{
            Output   = $output
            ExitCode = $exitCode
        }
    }

    if ($NewVersion) {
        $manifest = Get-ChildItem *.psd1 | Select-Object -First 1
        if ($manifest) {
            $manifestData = Import-PowerShellDataFile $manifest.FullName
            $v = [version]$manifestData.ModuleVersion

            switch ($BumpType) {
                'Major'    { $newV = New-Object System.Version ($v.Major + 1), 0, 0, 0 }
                'Minor'    { $newV = New-Object System.Version $v.Major, ($v.Minor + 1), 0, 0 }
                'Build'    { $newV = New-Object System.Version $v.Major, $v.Minor, ($v.Build + 1), 0 }
                'Revision' { $newV = New-Object System.Version $v.Major, $v.Minor, $v.Build, ($v.Revision + 1) }
            }

            $pattern = "ModuleVersion\s*=\s*'[^']+'"
            $replacement = "ModuleVersion     = '$newV'"
            (Get-Content $manifest.FullName -Raw) -replace $pattern, $replacement | Set-Content $manifest.FullName

            $Note = "[v$newV] $Note"
            Write-Host "Bumped $BumpType to $newV" -ForegroundColor Green
        }
    }

    $statusBefore = git status --porcelain
    if (-not $statusBefore) {
        Write-Warning "No changes found to save."
        return
    }

    Write-Host ""
    Write-Host "[Pre-check]" -ForegroundColor Cyan
    $statusBefore | ForEach-Object { Write-Host $_ }

    $stashed = $false

    try {
        Write-Host ""
        Write-Host "[Stash local changes]" -ForegroundColor Cyan
        $stashResult = & git stash push -u -m "GitEasy temporary save before Save-Work" 2>&1
        $stashExit = $LASTEXITCODE
        $stashResult | ForEach-Object { Write-Host $_ }

        if ($stashExit -ne 0) {
            throw "Could not stash local changes before pull."
        }

        $stashed = $true

        Invoke-GitEasyGit -Step "Check for peer updates" -Arguments @("pull", "origin", "main", "--rebase")

        if ($stashed) {
            Write-Host ""
            Write-Host "[Restore stashed changes]" -ForegroundColor Cyan
            $popResult = & git stash pop 2>&1
            $popExit = $LASTEXITCODE
            $popResult | ForEach-Object { Write-Host $_ }

            if ($popExit -ne 0) {
                throw "Stash pop failed. Resolve the stash state before running Save-Work again."
            }

            $stashed = $false
        }

        Invoke-GitEasyGit -Step "Stage files" -Arguments @("add", ".")

        $statusAfterAdd = git status --porcelain
        if (-not $statusAfterAdd) {
            Write-Warning "No changes found to commit after staging."
            return
        }

        Write-Host ""
        Write-Host "[Commit preview]" -ForegroundColor Cyan
        $statusAfterAdd | ForEach-Object { Write-Host $_ }

        Invoke-GitEasyGit -Step "Commit changes" -Arguments @("commit", "-m", $Note)
        Invoke-GitEasyGit -Step "Push changes" -Arguments @("push", "origin", "main")

        Write-Host ""
        Write-Host "Work synced and secured." -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Warning $_.Exception.Message
        Write-Host "Your work is still local." -ForegroundColor Yellow
        throw
    }
}

function Show-History {
    <# .SYNOPSIS See a visual timeline of changes. #>
    [CmdletBinding()]
    param()

    git log --oneline -n 15 --graph --decorate
}

function Find-CodeChange {
    <# .SYNOPSIS Search all history for a string (for example, a dropped table name). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SearchString
    )

    git log -S "$SearchString" --patch
}

function Restore-File {
    <# .SYNOPSIS Revert a single file to its last-saved state. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FileName
    )

    git checkout -- "$FileName"
    Write-Host "Restored $FileName." -ForegroundColor Cyan
}

function Clear-Junk {
    <# .SYNOPSIS Clean out bin/obj and untracked temp files from ecosystems. #>
    [CmdletBinding()]
    param()

    git clean -fdX
    Write-Host "Temp files and build artifacts cleared." -ForegroundColor Yellow
}

function Undo-Changes {
    <# .SYNOPSIS Wipe local mess and start fresh from GitLab. #>
    [CmdletBinding()]
    param()

    if ((Read-Host "Wipe all unsaved work? (Y/N)") -eq 'Y') {
        git reset --hard HEAD
        git clean -fd
        Write-Host "Local state reset to GitLab truth." -ForegroundColor Red
    }
}

function New-WorkBranch {
    <# .SYNOPSIS Create a sandbox for experimental work. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    git checkout -b "$Name"
}

function Switch-Work {
    <# .SYNOPSIS Switch between main and a sandbox branch. #>
    [CmdletBinding()]
    param(
        [string]$Name = "main"
    )

    git checkout "$Name"
}

function Get-VaultStatus {
    <# .SYNOPSIS Check what is changed but not yet saved. #>
    [CmdletBinding()]
    param()

    git status -s
}

Export-ModuleMember -Function Set-Vault, Show-Remote, Set-Token, Set-Ssh, Reset-Login, Test-Login, Save-Work, Show-History, Find-CodeChange, Restore-File, Clear-Junk, Undo-Changes, New-WorkBranch, Switch-Work, Get-VaultStatus

