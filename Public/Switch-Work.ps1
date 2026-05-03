function Switch-Work {
    <#
    .SYNOPSIS
    Switch to another existing working area.

    .DESCRIPTION
    Switch-Work is the GitEasy-first way to move between working areas. When wired up, it will switch safely - refusing to leave unsaved work behind unless you explicitly allow it.

    Switch-Work is part of the classic GitEasy public API but its V2 engine is not wired yet.

    .EXAMPLE
    Switch-Work -Name main

    .EXAMPLE
    Find-CodeChange; Switch-Work -Name giteasy-v2-refresh

    .NOTES
    When implemented, Switch-Work will run a state check, refuse to switch with unsaved conflicting changes, and report the result in plain English.

    .LINK
    New-WorkBranch

    .LINK
    Find-CodeChange

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param()
    throw 'Switch-Work exists as part of the classic GitEasy public API, but its V2 engine implementation is not wired yet.'
}
