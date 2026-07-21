# Docs map — claude-docs-toolkit

> Entry point for the toolkit's documentation. One line per area — follow the link for the real content, don't expect it duplicated here.
> Newest-at-top ordering applies within the append-only logs (`SESSIONS`, `DECISIONS`).

## Working state — read these first

| File | What it holds |
|---|---|
| [`SESSIONS.md`](SESSIONS.md) | End-of-session handoffs. The last entry is where the next session picks up. |
| [`DECISIONS.md`](DECISIONS.md) | Architecture Decision Records (ADRs) — *why* a choice was made, so it isn't re-debated. |
| [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md) | Open bugs and gotchas with their prevention rules. |
| [`SESSIONS-ARCHIVE.md`](SESSIONS-ARCHIVE.md) | Rotated-out older session handoffs. Append-only history — never edited. |

These four are read and written by the skills (`/session`, `/decision`, `/before`, `/ship`, `/lint`) and the project-context hook, so their paths are stable.

## Reference — what the toolkit is

| File | What it holds |
|---|---|
| [`overview.md`](overview.md) | High-level tour of the toolkit — what it is and how the pieces fit. `/docify`-maintained. |
| [`architecture.md`](architecture.md) | How the skills, hooks, installer, and gate are wired together. `/docify`-maintained. |
| [`skills.md`](skills.md) | Per-skill reference — what each of the skills does. `/docify`-maintained. |
| [`reference/`](reference/) | Standalone reference material — e.g. [`coderv-brief.md`](reference/coderv-brief.md), the honest technical brief written for outside reviewers. |

## Planning — how the workflow was designed

| Folder | What it holds |
|---|---|
| [`planning/`](planning/) | Design docs for the two-brain (Claude writer + Codex reviewer) workflow — the [convergence mechanism](planning/two-brain-convergence.md) and the [workflow plan](planning/two-brain-workflow-plan.md). |

---

*Not in git: `GAP-SCAN-*.json` scan output is kept local-only (gitignored) — internal evidence, not for a repo strangers clone.*
