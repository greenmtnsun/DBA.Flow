# GitEasy

GitEasy is a PowerShell module that gives DBAs and infrastructure teams a clean, task-focused Git workflow without requiring them to live in raw Git syntax all day.

It wraps the most common repository actions into memorable commands for setup, save/sync, history review, code forensics, cleanup, rollback, branch work, and status checks.

## What GitEasy does

- Initializes or connects a working folder to a Git remote
- Standardizes a DBA-friendly `.gitignore`
- Saves work with a single command that stages, commits, and pushes
- Supports optional manifest version bumping during release work
- Helps find when code appeared or disappeared in history
- Restores individual files without blowing away the entire folder
- Cleans ignored build and temp artifacts
- Creates and switches work branches
- Shows concise repository status and history

## Exported commands

- `Set-Vault`
- `Save-Work`
- `Show-History`
- `Find-CodeChange`
- `Restore-File`
- `Clear-Junk`
- `Undo-Changes`
- `New-WorkBranch`
- `Switch-Work`
- `Get-VaultStatus`

## Quick start

```powershell
Import-Module .\GitEasy.psd1 -Force

Set-Vault -GitRepoUrl "https://github.com/your-org/your-repo.git" -UserName "Keith Ramsey" -UserEmail "you@example.com"

Save-Work -Note "Initial import of DBA scripts"
```

## Example release save

```powershell
Save-Work -Note "Added restore helper for report files" -NewVersion -BumpType Minor
```

## Notes

- `Save-Work` assumes the main branch is `main`
- `Undo-Changes` is destructive by design
- `Clear-Junk` removes ignored junk and build artifacts
- `Find-CodeChange` is useful when tracking down when a server name, index, table, or code block entered history
