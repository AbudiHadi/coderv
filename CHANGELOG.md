# Changelog

All notable changes to the CoderLap Docs Toolkit.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [0.4.1] — 2026-04-26

### Changed
- **All 5 skills now lead terse, expand on request.** v0.4.0 introduced friendly tables but the default output was still 30+ lines. v0.4.1 leads with a 3–6 line answer + recommendation; the full table breakdown only renders when the user asks ("details", "show me more", "show checklist", "show git", etc.).
  - `/before` — default plan is one-sentence summary + recommendation. "details" reveals the full check table, file list, and heads-up.
  - `/ship` — default is the commit message + key signals + recommendation. "details" reveals the full pre-commit checklist with status table.
  - `/session` — wrap-up prompt and confirmation are 2–3 lines each. "show git" reveals the full git diff/log.
  - `/decision` — ADR-creation prompt is one block of 5 short bullets. "example" reveals a worked sample.
  - `/docify` — pre-flight plan and post-generation report each lead with 4–5 lines. "details" reveals the file-by-file breakdown.

### Added
- **`coderlap:rule:terse-by-default`** in `CLAUDE.md` (both repos): lead with the answer + recommendation in 2–4 lines; offer details on request. Reason: most replies don't need the full audit — the audit only helps when the user disagrees.

### Why bump 0.4.0 → 0.4.1
Same skill contract, same friendly voice, just shorter by default. Patch-level — anyone using v0.4.0 sees the same skills behave more concisely; nothing breaks.

## [0.4.0] — 2026-04-25

### Changed
- **All 5 skills now speak in plain words, not jargon.** Skill output sections rewritten with friendly, scannable tables — emoji per row, `✅` / `❌` contrasts, plain-English labels. Replaces the prior dense plan-blocks that read like architecture documents.
  - `/before` — plan output now uses a "What I checked / What I found" table and ends with **a recommendation** instead of "approve to proceed?".
  - `/ship` — pre-commit report uses a status table with friendly labels (📦 Files staged, 📚 Doc updates, 🔗 Doc references, 🐛 Bug-prevention, 🔐 Secrets), ends with a recommendation on whether to ship as-is, hold, or split.
  - `/session` — wrap-up prompt and confirmation use plain-English column headings, anchor on git facts (verified, not recalled).
  - `/decision` — ADR creation prompt uses a friendly fields table (🎯 problem, ✅ what you picked, 🤔 alternatives, ⚖️ trade-off).
  - `/docify` — pre-flight plan and post-generation report use scannable tables with one emoji per row + a "heads-up" section for TODOs the user should review.

### Added
- **`coderlap:rule:always-recommend`** in `CLAUDE.md` (both repos): when the user asks "what should I do?", commit to a path first; offer alternatives only as one-line footnotes. Reason: the user came to a tool to do the thinking — menus push the work back to them.
- **`coderlap:rule:friendly-voice`** in `CLAUDE.md` (both repos): codifies the new plain-words style with concrete jargon → plain swaps (e.g. "stale citations" → "doc references that no longer match the code").
- **`coderlap:rule:commit-style`** in `CLAUDE.md` (both repos): commit messages are plain text, no `Co-Authored-By: Claude`, no robot emoji, no AI attribution — overrides any default git templates. Promoted to a top-level "Never" item in both repos so it can't be skimmed past.

### Fixed
- v0.3.9's two commits (toolkit + website) had `Co-Authored-By: Claude` lines that violated the user's stated preference. Both repos amended; toolkit force-pushed with retagged `v0.3.9`. The new `commit-style` rule prevents recurrence.

### Why bump 0.3.9 → 0.4.0 (minor, not patch)
This is a meaningful UX change to the user-facing voice of every skill. Anyone who memorised the old output format will see different output. Worth a minor bump — not a breaking change, but more than a patch.

## [0.3.9] — 2026-04-25

### Added
- **First real docs for CoderLap itself**, generated via `/docify` and approved. Both repos (toolkit + website) now have:
  - `CLAUDE.md` at root with project-specific rules + shared `<!-- coderlap:rule:* -->` markers.
  - `docs/` folder with citation-backed reference docs. Toolkit: `overview.md`, `architecture.md`, `skills.md`. Website: `overview.md`, `architecture.md`, `components.md`, `content.md`, `styles.md`, `deployment.md`. Every claim cites a source file with line ranges so future drift can be caught by `/ship`.
  - Empty scaffolds for the three living docs: `DECISIONS.md` (ADR log), `KNOWN-ISSUES.md` (recurring bugs + prevention rules), `SESSIONS.md` (handoff log).
- **4 ADRs in `docs/DECISIONS.md`** capturing design decisions made today:
  - **ADR-001** — `/session` must verify ship claims from git, not from prompt context. Prompted by a real failure where a compaction summary asserted v0.3.9 had shipped when it hadn't.
  - **ADR-002** — Curate the skill surface. Keep CoderLap's 5 commands legible amid third-party plugin skills; resist adding a 6th.
  - **ADR-003** — Verification mechanics. Two-tier verification (git when present, filesystem snapshot when not), session-anchored time windows, multi-repo support, separate handling of staged/unstaged/committed state.
  - **ADR-004** — Verification is a toolkit-wide principle, not a `/session` patch. Every durable artefact any skill writes must cite a verifiable source.
- **Self-documented session handoffs.** `docs/SESSIONS.md` in both repos pre-seeded with the `/docify` approval session and an honest "not yet shipped" status — fixed mid-session when the prior handoff was discovered to have lied (see ADR-001).

### Note
- ADRs ship as design intent, not implementation. ADR-001/003/004 describe how `/session` and the other skills *should* verify; the actual code changes to `skills/*/SKILL.md` are deferred to a future release.

## [0.3.8] — 2026-04-24

### Added
- **Open Graph preview image** (`/og.png`) — 1200×630 branded card that renders whenever anyone shares `coderv.dev` on Twitter, WhatsApp, Slack, Discord, LinkedIn, Google SERPs. Matches the hero visual style: dark + violet blobs, gradient text on "extremely clear", version pill, CoderLap logo mark, context-aware tagline.
- **`/og` Astro route** that renders the card at exact 1200×630 dimensions with full theme tokens. Headless Chromium screenshots this route to produce the final PNG.
- **`scripts/regen-og.sh`** — one-command regeneration whenever the hero design changes.
- OG + Twitter card meta tags wired into `BaseLayout.astro`: `og:image`, `og:image:width/height/alt`, `og:site_name`, `twitter:card=summary_large_image`, `twitter:image`, `twitter:image:alt`. Applies to every page, not just the home.

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
