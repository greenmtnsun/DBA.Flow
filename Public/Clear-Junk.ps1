function Clear-Junk {
    <#
    .SYNOPSIS
    Remove obvious temporary or generated files before saving work.

    .DESCRIPTION
    Clear-Junk is the GitEasy cleanup command. When wired up, it will conservatively remove generated outputs, editor leftovers, and similar clutter so Find-CodeChange and Save-Work see a cleaner working area.

    Clear-Junk is part of the classic GitEasy public API but its V2 engine is not wired yet.

    .EXAMPLE
    Clear-Junk

    .EXAMPLE
    Clear-Junk; Find-CodeChange

    .NOTES
    When implemented, Clear-Junk will be conservative: never delete source files, always log what was removed, and always be safely re-runnable.

    .LINK
    Find-CodeChange

    .LINK
    Save-Work

    .LINK
    Undo-Changes
    #>
    [CmdletBinding()]
    param()
    throw 'Clear-Junk exists as part of the classic GitEasy public API, but its V2 engine implementation is not wired yet.'
}
