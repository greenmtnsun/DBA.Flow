function Find-CodeChange {
    <#
    .SYNOPSIS
    Show a friendly summary of what has changed in your project folder.

    .DESCRIPTION
    Find-CodeChange is the GitEasy-first replacement for raw git status. It returns a structured object describing the project location, the active working area, whether the folder is clean, and counts of changes broken down by staged, unstaged, and untracked.

    Run it before Save-Work when you want to see what is about to be saved, or any time you want a readable summary of the current state.

    .EXAMPLE
    Find-CodeChange

    .EXAMPLE
    Set-Location C:\Sysadmin\Scripts\GitEasyV2; Find-CodeChange

    .NOTES
    A clean working area does not always mean everything has been published. If Find-CodeChange shows IsClean=True but Save-Work still finds work to publish, that is correct - it means there are saved points that have not been published yet.

    .LINK
    Save-Work

    .LINK
    Show-History

    .LINK
    Show-Remote
    #>
    [CmdletBinding()]
    param()

    return Get-GECodeChange
}
