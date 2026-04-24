# Changelog

All notable changes to the CoderLap Docs Toolkit.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [0.3.7] — 2026-04-24

### Changed
- **/docify TRIGGER expanded to catch plain words "docs" / "doc" / "documentation" / "README".** Previous trigger list required phrases like "write docs"; single-word mentions were often missed. Also added phrases like "make a full docs", "docs are missing", "docs outdated". Added ambiguity guard: on short single-word mentions, the skill asks whether the user means generation or a single-file edit before running.

## [0.3.6] — 2026-04-24

### Changed
- "Used in production by" list updated: CareShifa link now points at the production site (`careshifa.com`). Yokisa entries expanded to name the individual products (Streak, Anime, TV, Hub, Billing, Achievements). Removed private internal tools from the public list.

## [0.3.5] — 2026-04-24

### Added
- **README badges** on both repos: latest release, GitHub stars, GitHub forks, licence, "built for Claude Code". Strangers visiting the repo immediately see it's alive, released, and has traction.
- **"Used in production by" section** in toolkit README listing real deployments. Trust signal beats raw download numbers.
- **"Star on GitHub" CTA** on the homepage replaces the plain "View on GitHub" button — yellow star icon, call-to-action framing, hover scales the icon.

### Changed
- Hero authority strip label: "Built by Abdullah Hadi" → **"Used in production by"** (sharper positioning — these are users, not just a bio).

## [0.3.4] — 2026-04-24

### Changed
- Contact email updated from `GGAbdulalah@gmail.com` to **`support@coderv.com`** across:
  - `LICENCE` (both repos) — §1 Definitions, §4 Requesting Permission, footer contact
  - Website footer, `/licence` page, hero email CTA, meta tags
  - `README.md` (both repos)
  - `src/config/site.ts` — single source of truth propagates to every page

## [0.3.3] — 2026-04-24

### Changed
- **Licence — warmer tone.** Section 3 ("Reserved Rights") now opens with a preamble clarifying that personal/evaluation use is already free, and that the restrictions exist to track commercial/redistribution use at scale. Section 4 ("Requesting Permission") now opens with "a short email is fine; do not overthink it". No change to the legal rights themselves.
- **Website licence page redesigned.** Previous layout was one dense legal wall after the at-a-glance card. New layout:
  - At-a-glance card split into two columns (free-no-permission vs email-first) alongside a prominent email CTA.
  - New "Frequently approved" FAQ block with 6 typical scenarios (day job, fork, blog, paid course, product bundling, SaaS clone) showing what usually gets a yes.
  - Full legal text restructured as 11 individual cards with a sticky sidebar table of contents on desktop. Section 2 gets emerald accent (permitted), Section 3 gets amber (reserved), Section 4 gets violet (contact). Each has a small icon badge.

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
