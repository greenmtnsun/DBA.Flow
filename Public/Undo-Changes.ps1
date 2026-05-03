function Undo-Changes {
    <#
    .SYNOPSIS
    Throw away local changes and return the working area to a clean state.

    .DESCRIPTION
    Undo-Changes is the GitEasy-first way to abandon local edits. When wired up, it will run a state check, prompt for confirmation, and return the working area to the last saved state.

    Undo-Changes is part of the classic GitEasy public API but its V2 engine is not wired yet.

    .EXAMPLE
    Find-CodeChange; Undo-Changes; Find-CodeChange

    .NOTES
    When implemented, Undo-Changes will:
    - Run a state check first.
    - Refuse to run unless explicitly confirmed.
    - Suggest a Save-Work -NoPush checkpoint as a safer alternative.

    .LINK
    Find-CodeChange

    .LINK
    Restore-File

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param()
    throw 'Undo-Changes exists as part of the classic GitEasy public API, but its V2 engine implementation is not wired yet.'
}
