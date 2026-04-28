function Assert-GESafeSave {
    [CmdletBinding()]
    param([switch]$NoPush, [switch]$SetUpstream)
    $root = Get-GERepoRoot
    $branch = Get-GEBranchName -Path $root
    $busy = Test-GERepositoryBusy -Path $root
    if ($busy.IsBusy) {
        throw "Git operation in progress: $($busy.Operations -join ', '). Finish or abort it before Save-Work."
    }
    $conflicts = @(Get-GEConflictFiles -Path $root)
    if ($conflicts.Count -gt 0) {
        throw "Unresolved conflicts found. Fix these before Save-Work: $($conflicts -join ', ')"
    }
    $status = Get-GEStatus -Path $root
    $upstream = Get-GEUpstreamBranch -Path $root
    if ((-not $NoPush) -and [string]::IsNullOrWhiteSpace($upstream) -and (-not $SetUpstream)) {
        throw 'No upstream branch. Use Save-Work -SetUpstream or Save-Work -NoPush.'
    }
    [PSCustomObject]@{ Root = $root; Branch = $branch; Status = $status; Upstream = $upstream }
}
