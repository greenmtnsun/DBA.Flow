function New-WorkBranch {
    <#
    .SYNOPSIS
    Start a new working area for an isolated task, fix, or doc change.

    .DESCRIPTION
    New-WorkBranch is the GitEasy-first way to start a new working area without learning raw branch creation commands. When wired up, it will create the working area and switch to it in one step.

    New-WorkBranch is part of the classic GitEasy public API but its V2 engine is not wired yet.

    .EXAMPLE
    New-WorkBranch -Name fix-readme

    .EXAMPLE
    Find-CodeChange; New-WorkBranch -Name docs-refresh

    .NOTES
    When implemented, New-WorkBranch will run a Find-CodeChange-style state check first, refuse to switch away from unsaved work, and use plain-English error messages.

    .LINK
    Switch-Work

    .LINK
    Find-CodeChange

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param()
    throw 'New-WorkBranch exists as part of the classic GitEasy public API, but its V2 engine implementation is not wired yet.'
}
