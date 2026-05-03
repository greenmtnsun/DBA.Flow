# GitEasy V2 Changelog

All notable changes to this module are recorded here. The format is loosely [Keep a Changelog](https://keepachangelog.com/), and this project follows semantic versioning.

## [1.0.0] - 2026-05-03

First feature-complete public surface. Every command is implemented, documented, and directly tested.

### Added

- **Stub-to-real implementations** of `New-WorkBranch`, `Switch-Work`, `Restore-File`, `Undo-Changes`, `Clear-Junk`. All five route through `Invoke-GEGit`, open per-invocation diagnostic log sessions, and throw plain-English errors with log-path callouts.
- **`Show-Diagnostic`** — public command for opening, listing, or browsing the diagnostic log folder.
- **Diagnostic logging architecture** — every public command writes one self-contained log file per invocation. Default location `%LOCALAPPDATA%\GitEasy\Logs`, overridable per call (`-LogPath`) or site-wide (`GITEASY_LOG_PATH`). Logs older than 30 days are pruned automatically.
- **Comment-based help on every function and script** — all 16 public commands, 19 private helpers, and 5 scripts now ship with `.SYNOPSIS`, `.DESCRIPTION`, per-`.PARAMETER`, `.EXAMPLE`, `.NOTES`, and `.LINK` blocks.
- **`Update-GitEasyCommandWiki.ps1`** — generates the public-command wiki pages from CBH source-of-truth, with drift detection, CBH audit, stale-claim flagging, source-hash watermarks, module-version watermark, machine/human section merge, orphan removal, and a `-DryRun` mode.
- **`tools/Audit-PublicJargon.ps1`** — scans the public surface for git-terminology leakage and reports HARD vs SOFT hits.
- **74 Pester 3 tests** covering every public command directly, plus the logging helpers. All pass on Windows PowerShell 5.1 and PowerShell 7+.

### Changed

- `Save-Work` reconciled — clean-but-ahead branches are now published; commit messages are written without UTF-8 BOM; native-Git stderr no longer triggers false failures; routes every Git call through `Invoke-GEGit`; produces plain-English errors with log paths.
- `Assert-GESafeSave` rewritten to use `Test-GERepositoryBusy` and `Get-GEConflictFiles`; throws plain-English on every failure mode.
- `Invoke-GEGit` now captures stdout and stderr separately, so warnings (LF/CRLF, etc.) cannot poison parsed output. Optional `-LogPath` plumbing.
- `Update-GitEasyPrivateWiki.ps1` reads CBH from inside function bodies (the standard PowerShell location). Pages whose helper has been deleted from source are now removed automatically.
- Per-page source-hash watermarks added to every public-command wiki page.
- Module-version watermark added to `Public-Commands.md`.
- Log filenames now include millisecond precision so rapid-fire invocations no longer collide.

### Removed

- Dead-code helpers `Get-GEStatus.ps1` and `Get-GEUpstreamBranch.ps1` (zero callers).
- Stub bodies on the five remaining commands.

### Fixed

- Pester 3 `Should Throw` is broken on PowerShell 7. Tests now use `try/catch` + `Should Not BeNullOrEmpty`, which works on both PS 5.1 and PS 7.
- HARD-jargon regression in `Save-Work` ("detached") and in `Switch-Work` ("stash"). Both translated to plain English.

## [0.9.0] - 2026-04-24

Initial V2 baseline. Public command surface defined; many commands stubbed; Pester harness and read-only commands wired.

### Added

- Module manifest with classic GitEasy public command names.
- Pester test harness, manifest sanity tests.
- Core helpers: `Get-GERepoRoot`, `Get-GEBranchName`, `Get-GECodeChange`, `Invoke-GEGit`.
- Initial `Save-Work` (later reconciled in 1.0.0).
- Read-only commands: `Find-CodeChange`, `Show-History`, `Show-Remote`.
- Authentication-setup commands: `Set-Token`, `Set-Ssh`, `Set-Vault`, `Get-VaultStatus`, `Test-Login`, `Reset-Login`.
- Initial wiki pages and architecture docs.
