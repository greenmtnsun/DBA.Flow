function Restore-File {
    <#
    .SYNOPSIS
    Restore a single file to its last saved state without touching anything else.

    .DESCRIPTION
    Restore-File is the targeted GitEasy restore. When wired up, it will reset one file to its last saved version while leaving every other local change alone.

    Restore-File is part of the classic GitEasy public API but its V2 engine is not wired yet.

    .EXAMPLE
    Restore-File -Path README.md

    .EXAMPLE
    Find-CodeChange; Restore-File -Path Public\Save-Work.ps1; Find-CodeChange

    .NOTES
    When implemented, Restore-File will run a state check, will refuse to discard work without confirmation, and will report what was changed.

    .LINK
    Find-CodeChange

    .LINK
    Undo-Changes

    .LINK
    Save-Work
    #>
    [CmdletBinding()]
    param()
    throw 'Restore-File exists as part of the classic GitEasy public API, but its V2 engine implementation is not wired yet.'
}
