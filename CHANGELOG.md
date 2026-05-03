# GitEasy Changelog

All notable changes to this module are recorded here. The format is loosely [Keep a Changelog](https://keepachangelog.com/), and this project follows semantic versioning.

## [1.1.0] - 2026-05-03

The two parallel GitEasy lines (the V1 daily-driver and the V2 from-scratch reboot) merge into a single module. **There is no longer a V1 or V2 — just GitEasy.** This release absorbs the V2 engine wholesale, plus the seven V1 features that were better or more complete than V2.

### Identity

- Module GUID continues V1's `2e113abf-c0e7-4dfb-9cb1-69476d7541f6` (the previously V1-exclusive line is now the only line).
- Module version is **1.1.0** (continuation of V1's 1.0.1.1, treating the V2 engine adoption as a major upgrade).

### Added (harvested from V1)

- **`Save-Work -BumpVersion -BumpKind <Major|Minor|Build|Revision>`** — auto-bumps the active project's `.psd1` ModuleVersion before saving, and prefixes the saved-point note with the new version.
- **`Save-Work` pre-pull with rebase** — before publishing, Save-Work pulls peer updates and replays your saved point on top, so a teammate's recent push does not block yours. Local changes are bracketed with stash/pop.
- **`Reset-Login` deeper credential clearing** — in addition to `git credential reject`, Reset-Login now also calls `git credential-manager erase` (when the manager helper is configured) and `cmdkey.exe /delete` for several Windows credential targets. Clears the saved login from every place Git might be reading it.
- **`Set-Vault -WriteIgnoreList`** — optional switch that writes a starter `.gitignore` for PowerShell / .NET / SQL projects (build artifacts, IDE leftovers, log files, secret files). Preserves any existing patterns; only appends what is missing.
- **`Search-History -Pattern <text>`** — new public command. Finds every saved point that added or removed a piece of text. Useful for forensic questions ("when did `DROP TABLE` first appear?"). Returns structured objects; `-Patch` includes the change text.
- **`Show-History -Graph`** — optional switch that prints a visual ASCII graph of saved points with branching and merging shown, instead of returning structured objects.
- **`Clear-Junk` switched to `git clean -fdX` engine** — removes files matching your `.gitignore` instead of a hardcoded extension list. With `-Force -Aggressive`, also removes untracked files not matched by `.gitignore`. Tracked files are never touched.

### Changed

- Public-surface count is now **17** (added `Search-History`).
- `Save-Work` flow now includes the pre-pull-with-rebase step before push when an upstream is configured. Failures during the pull abort cleanly and leave your saved work intact.
- Wiki module-version watermark moves from `1.0.0` to `1.1.0`.

### Tests

- **99 Pester 3 tests** passing on Windows PowerShell 5.1 and PowerShell 7+ (was 86 in 1.0.0).
- 12 new tests covering Search-History, Show-History -Graph, Save-Work -BumpVersion, and Set-Vault -WriteIgnoreList.
- Clear-Junk tests rewritten to exercise the gitignore-aware engine (and the `-Aggressive` switch).

### Notes

- The V1 line previously known as `1.0.1.1` is preserved at the `v1-archive` branch on GitHub for historical reference.
- The V2 development branch `giteasy-v2-refresh` is retired; its tip is now `main`.

## [1.0.0] - 2026-05-03

First feature-complete public surface of the V2 design. Every command is implemented, documented, and directly tested.

### Added

- **Stub-to-real implementations** of `New-WorkBranch`, `Switch-Work`, `Restore-File`, `Undo-Changes`, `Clear-Junk`. All five route through `Invoke-GEGit`, open per-invocation diagnostic log sessions, and throw plain-English errors with log-path callouts.
- **`Show-Diagnostic`** — public command for opening, listing, or browsing the diagnostic log folder.
- **Diagnostic logging architecture** — every public command writes one self-contained log file per invocation. Default location `%LOCALAPPDATA%\GitEasy\Logs`, overridable per call (`-LogPath`) or site-wide (`GITEASY_LOG_PATH`). Logs older than 30 days are pruned automatically.
- **Comment-based help on every function and script** — all 16 public commands, 19 private helpers, and 5 scripts now ship with `.SYNOPSIS`, `.DESCRIPTION`, per-`.PARAMETER`, `.EXAMPLE`, `.NOTES`, and `.LINK` blocks.
- **`Update-GitEasyCommandWiki.ps1`** — generates the public-command wiki pages from CBH source-of-truth, with drift detection, CBH audit, stale-claim flagging, source-hash watermarks, module-version watermark, machine/human section merge, orphan removal, and a `-DryRun` mode.
- **`tools/Audit-PublicJargon.ps1`** — scans the public surface for git-terminology leakage and reports HARD vs SOFT hits.
- **MPL-2.0 LICENSE**, README.md, CONTRIBUTING.md, GitHub Actions CI workflow, issue and PR templates.
- **86 Pester 3 tests** covering every public command directly, plus the logging helpers. All pass on Windows PowerShell 5.1 and PowerShell 7+.

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
