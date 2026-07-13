# CoderLap Docs Toolkit

[![Latest release](https://img.shields.io/github/v/release/AbudiHadi/coderv?color=8b5cf6&label=release)](https://github.com/AbudiHadi/coderv/releases)
[![GitHub stars](https://img.shields.io/github/stars/AbudiHadi/coderv?style=social)](https://github.com/AbudiHadi/coderv/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/AbudiHadi/coderv?style=social)](https://github.com/AbudiHadi/coderv/network/members)
[![License](https://img.shields.io/badge/license-CoderLap%20SA-8b5cf6)](./LICENCE)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-8b5cf6)](https://coderv.dev)

**A context-aware toolkit for Claude Code.** It watches how you naturally talk and suggests the right tool at the right moment — turning your real workflow into clean, honest docs.

🌐 **[coderv.dev](https://coderv.dev)** · ⭐ [Star on GitHub](https://github.com/AbudiHadi/coderv) · ✉️ [support@coderv.com](mailto:support@coderv.com)

---

## Used in production by

- **[CareShifa](https://careshifa.com)** — telemedicine platform (Next.js + Prisma)
- **Yokisa ecosystem** — SaaS suite including Yokisa Streak, Yokisa Anime, Yokisa TV, Yokisa Hub, Yokisa Billing, Yokisa Achievements
- **Library System** — internal operations

> *Running CoderLap in production? Email [support@coderv.com](mailto:support@coderv.com) — we'll add you to this list.*

---

## What it does

Six slash commands that help devs keep extremely clear docs — without getting tired or trying to remember.

> **The problem:** Claude without structure drifts. Re-asks settled questions. Re-introduces fixed bugs. Skips docs. Scope-creeps. The next session starts from zero. Docs rot within a week.
>
> **The answer:** six commands. One generates real docs from your code. Four keep them fresh. One audits them for lies. Markdown only. No framework. No dependency.

---

## The six commands

| Command | The tired moment it fixes |
|---|---|
| **`/docify`** | *"I need real docs but I don't want to write them."* — Scans your code, generates `CLAUDE.md` + 6 professional docs (architecture, api, components, database, integrations, overview) with source citations. Run once per project. |
| **`/before <task>`** | *"What should I even read first?"* — Claude reads the relevant docs, greps prior art, checks past decisions, states a plan, waits for your OK. Auto-skips tiny tasks. |
| **`/decision <title>`** | *"Write down why, so I never have to explain it again."* — Logs an ADR in 30 seconds while the choice is fresh. |
| **`/ship`** | *"Did I forget to update any docs before committing?"* — Reads the diff, **auto-updates api.md / components.md / database.md** from the code change, validates every citation in the docs is still accurate, drafts a why-focused commit message. |
| **`/session [last]`** | *"Pick up where I left off."* — End of session → leaves a handoff. Start of next → `/session last` reads it. Rotates old entries to an archive so the live file stays cheap. |
| **`/lint`** | *"Can I still trust these docs?"* — Audits `CLAUDE.md` + `docs/` for contradictions, stale claims, and dead references; reports findings with `file:line` and the reality they conflict with. Docs generate (`/docify`), stay fresh (`/ship`), and now get health-checked. |

## The loop

```
/docify                # once per project (generates CLAUDE.md + 6 docs)
                       # ↓ every task after that:
/session last          # what was I doing?
/before <task>         # Claude plans, waits for OK
<you approve, code>
/ship                  # auto-updates docs, validates citations, drafts commit
<commit>
/session               # handoff for next time
/lint                  # every ~5 sessions: docs health check (rot, contradictions)
```

`/docify` once. Four commands daily, `/lint` weekly. Docs stay clean + honest as a side effect of doing your work.

---

## Install

**One command (Claude Code, default):**

```bash
curl -fsSL https://coderv.dev/install.sh | bash
```

Skills land in `~/.claude/skills/` and two hooks are wired into `~/.claude/settings.json`: `coderv-router` (surfaces the right command at the right moment) and `project-context` (every new session starts already knowing where each project left off) — without you having to remember or ask.

**Manual path:**

```bash
git clone https://github.com/AbudiHadi/coderv
cd coderv
./install.sh
```

**Other CLIs (skills only — no hook):**

The 6 skills also work in [Codex CLI](https://github.com/openai/codex) and [Gemini CLI](https://github.com/google-gemini/gemini-cli) — both adopted the same SKILL.md format.

```bash
./install.sh --codex            # ~/.codex/skills/
./install.sh --gemini           # ~/.gemini/skills/
./install.sh --all              # all three hosts
```

The `coderv-router` hook is Claude-Code-specific (the others don't have an equivalent hook event). On Codex / Gemini, the toolkit relies on the in-skill TRIGGER blocks alone — auto-suggest works but is less aggressive than on Claude Code.

**Update:**

```bash
curl -fsSL https://coderv.dev/install.sh | bash -s -- --force
```

**Uninstall:**

```bash
cd coderv && ./install.sh --uninstall          # remove from Claude Code
cd coderv && ./install.sh --uninstall --all    # remove from all three
```

---

## The coderv-router hook (Claude Code)

The skill descriptions tell Claude *when* to use a command — but they're guidelines for the model and can be missed mid-task. The `coderv-router` hook is the safety net: a `UserPromptSubmit` hook that scans every message you send and injects a one-line reminder into Claude's context when it spots a match.

| You type | Router fires | Claude offers |
|---|---|---|
| *"can we make it MCP?"* | HIGH /decision | `/decision` (it's a tech trade-off worth logging) |
| *"add a login page"* | HIGH /before | `/before` (non-trivial change — plan first) |
| *"ok lets commit this"* | HIGH /ship | `/ship` (run pre-commit checklist) |
| *"done for today"* | HIGH /session | `/session` (write a handoff) |
| *"what's next?"* | LOW /session | `/session last` (with a quick "did you mean…?" check) |

Two confidence tiers:
- **HIGH** — clear intent, Claude offers the skill firmly.
- **LOW** — phrasing is ambiguous, Claude briefly checks intent before running.

The router is installed automatically when you install for Claude Code. To skip it (skills only), install for Codex / Gemini.

---

## The project-context hook (Claude Code)

The other half of "never explain where you left off again": a `SessionStart` hook that scans your projects folder for `docs/SESSIONS.md` files and injects a live map into every new session — each project's newest session entry, sorted by recent activity, plus a standing rule telling Claude to read the real docs before touching anything.

Memory can go stale or get skipped; this runs in the harness on every session start and reads the actual files at that moment. Point it at your projects root with `CODERV_PROJECTS_DIR` (defaults to `/home/appuser/apps`, then `~/apps`). On machines with no documented projects it injects nothing.

---

## The three living files

Once you run `/before` in a fresh project, it scaffolds these:

| File | Role |
|---|---|
| `docs/DECISIONS.md` | ADRs — every design choice with context, alternatives, consequences. Newest first. Never deleted. |
| `docs/KNOWN-ISSUES.md` | Recurring bugs with symptom, root cause, fix, and the **prevention rule** that stops recurrence. |
| `docs/SESSIONS.md` | Rolling log of end-of-session handoffs. |

Plus `CLAUDE.md` at project root that tells Claude how to use them.

---

## Design principles

- **Markdown only.** No database. No framework. No runtime dependency. If the toolkit disappeared tomorrow, the files still tell you what's going on.
- **Idempotent.** Every command is safe to re-run.
- **Never delete history.** Closed items become `shipped YYYY-MM-DD`, superseded items stay with a pointer. You can always trace why.
- **Adaptive.** `/ship` only asks about docs your changes actually touched. `/before` auto-skips tiny tasks.
- **Project-agnostic.** No hardcoded paths. No language assumptions. Works in any repo.

---

## FAQ

**Does this replace `CLAUDE.md`?**
No. `/before` will offer to create `CLAUDE.md` if it's missing, using a standard template. Your project-specific rules stay.

**My project already has `docs/` with other files. Will this clobber them?**
No. Nothing overwrites. `/before` only creates the four files if they're missing.

**What if I don't want to log ADRs?**
Don't run `/decision`. Every command is optional. The toolkit is lighter than any framework — use what helps.

**Why not just hooks / automation?**
The 6 commands are visible — you invoke them, they do their job visibly, no silent failure. That's the core. The `coderv-router` hook (Claude Code) is a thin layer on top of that: it doesn't *do* the work, it just makes sure Claude *offers* the right command when your phrasing matches. The work itself is still in the visible, markdown-only commands.

**Does the toolkit work with Codex CLI and Gemini CLI?**
Yes. Both CLIs adopted the same SKILL.md format. Install with `--codex`, `--gemini`, or `--all`. The `coderv-router` hook is Claude-Code-specific, so on those hosts the toolkit relies on each skill's TRIGGER block — auto-suggest works but is less aggressive than on Claude Code.

---

## Licence

CoderLap Source-Available Licence v1.0 — see [LICENCE](./LICENCE).

Free to read. Free for personal evaluation. **All other use — commercial, redistribution, hosting, incorporation, modification-then-sharing — requires written permission from Abdullah Hadi (support@coderv.com).**

Full licence: https://coderv.dev/licence
