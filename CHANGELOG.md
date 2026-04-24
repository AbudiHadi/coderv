# Changelog

All notable changes to the CoderLap Docs Toolkit.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [0.3.2] — 2026-04-24

### Added
- **Magic Triggers**: every skill's YAML description now includes `TRIGGER` and `SKIP` blocks listing natural-language phrases that should surface the skill without requiring the slash prefix. Claude Code's skill picker uses these to suggest the right tool when users describe their intent in plain English.
- **`coderlap:rule:suggest-followups`** rule in `templates/CLAUDE.md` rewritten as a phrase → skill → suggested-reply map. Reinforces the trigger pattern in every project that runs `/docify`.
- VERSION file + CHANGELOG at repo root.

### Changed
- Installer trailer message lists the current toolkit version.

## [0.3.0] — 2026-04-23

### Added
- **`/docify`** — scans any codebase and generates `CLAUDE.md` + 6 docs (overview, architecture, api, components, database, integrations). Every claim cited back to a source file. Drafts-first safety model. Preserves existing CLAUDE.md rules via `<!-- coderlap:rule:* -->` markers.
- Smart **`/ship`** — detects new routes / components / schema changes and offers to update the relevant doc itself (not just ask). Citation validator walks `docs/**.md` and flags stale `<!-- src: -->` markers on every commit.
- **`/before`** now suggests follow-up commands (`/decision`, `/ship`, `/session`) inline at the right moments, without auto-running.

### Changed
- `templates/CLAUDE.md` adds rule markers (`<!-- coderlap:rule:* -->`) so `/docify` can re-add missing rules without clobbering custom ones.

## [0.2.0] — 2026-04-23

### Changed
- **Trimmed from 10 commands to 4 focused commands**: `/before`, `/decision`, `/ship`, `/session`. Removed `/docs`, `/doc-init`, `/doc-new`, `/gap`, `/repeat`, `/trace` — their roles either absorbed into the 4 kept commands or moved to CLAUDE.md rules.
- `/before` auto-skips tiny edits (typos, one-liners, same-session undos) and auto-runs on bigger tasks (refactor, rename, first touch of a module).

## [0.1.1] — 2026-04-23

### Added
- One-line installer: `curl -fsSL https://coderv.dev/install.sh | bash`
- `--project` flag installs skills into `./.claude/skills/` instead of user-global.

## [0.1.0] — 2026-04-23

### Added
- Initial public release with 10 slash commands: `/doc-init`, `/docs`, `/before`, `/gap`, `/doc-new`, `/decision`, `/ship`, `/session`, `/repeat`, `/trace`.
- Installer (`install.sh`) + templates (`MASTER-INDEX.md`, `DECISIONS.md`, `KNOWN-ISSUES.md`, `SESSIONS.md`).
- CoderLap Source-Available Licence v1.0.
