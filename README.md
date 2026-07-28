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

Seven slash commands + four always-on gates that help devs keep extremely clear docs and honest agents — without getting tired or trying to remember.

> **The problem:** Claude without structure drifts. Re-asks settled questions. Re-introduces fixed bugs. Skips docs. Scope-creeps. The next session starts from zero. Docs rot within a week.
>
> **The answer:** seven commands. One is the front door that drives the rest. One generates real docs from your code. Four keep them fresh. One audits them for lies. Plus four always-on gates (Claude Code) that make "read the docs first", "no commit lands unreviewed", and "never work in the dumb zone" physics instead of advice. Markdown + bash only. No framework. No dependency.

---

## The seven commands

| Command | The tired moment it fixes |
|---|---|
| **`/coderv <request>`** | *"I don't want to remember which command comes next."* — The front door. Say what you want in your own words; it classifies the request, checks project state, assembles the pipeline (`/lint` if docs are stale → `/before` → work → `/ship`), and drives it on one yes. You're only stopped to approve the plan and the 100% scorecard. <br>**🏛 Architecture / system audit shape** *(say "audit the system", "check all integrations", "is anything left running")* — a read-only scout, then a parallel fan-out over 7 dimensions (layering, coupling/cohesion, duplication, boundaries, dead code, **integration wiring**, **service liveness — "a server left alone"**), each finding **adversarially verified by Codex** before it reaches a scored P0–P3 report **and a draw.io-style interactive system map** — a pan/zoom canvas with 🟢 live / 🌐 external / ⏸ parked node markers and 🔴 P0–P1 / 🟡 P2–P3 gap markers, where clicking a node traces its gap and spotlights the matching finding. Advises, never auto-fixes; findings are woven into every other command so a problem found once stays in view until it's fixed. Still 7 commands — it's a shape, not an eighth. |
| **`/docify`** | *"I need real docs but I don't want to write them."* — Scans your code, generates `CLAUDE.md` + 6 professional docs (architecture, api, components, database, integrations, overview) with source citations. Run once per project. |
| **`/before <task>`** | *"What should I even read first?"* — Claude reads the relevant docs, greps prior art, checks past decisions, states a plan, waits for your OK. Auto-skips tiny tasks. |
| **`/decision <title>`** | *"Write down why, so I never have to explain it again."* — Logs an ADR in 30 seconds while the choice is fresh. |
| **`/ship`** | *"Did I forget to update any docs before committing? And can I trust that it's really done?"* — Reads the diff, **auto-updates api.md / components.md / database.md**, validates every citation, spawns a fresh-context reviewer that audits the diff against the written spec, and prints a **verification scorecard** — gates passed/total with real command output pasted per gate. You approve at 100%; below that, the failing line says exactly why. |
| **`/session [last]`** | *"Pick up where I left off."* — End of session → leaves a handoff. Start of next → `/session last` reads it. Rotates old entries to an archive so the live file stays cheap. |
| **`/lint`** | *"Can I still trust these docs?"* — Audits `CLAUDE.md` + `docs/` for contradictions, stale claims, and dead references; reports findings with `file:line` and the reality they conflict with. Docs generate (`/docify`), stay fresh (`/ship`), and now get health-checked. |

## The loop

```
/docify                # once per project (generates CLAUDE.md + 7 docs incl. CONTEXT.md vocabulary)
                       # ↓ every task after that:
/coderv <request>      # the front door — assembles and drives the rest:
  → /session last      #   what was I doing?
  → /lint              #   only when docs are stale — refresh the anchors
  → /before <task>     #   Claude plans, writes the spec — you approve
  → <code>             #   gates guard grounding + context silently
  → /ship              #   reviewer + scorecard — you approve at 100%
/session               # handoff for next time (state as pasted evidence)
```

`/docify` once. `/coderv` daily — it drives the others so you don't have to remember them. Docs stay clean + honest as a side effect of doing your work.

---

## Install

**One command (Claude Code, default):**

```bash
curl -fsSL https://coderv.dev/install.sh | bash
```

Skills land in `~/.claude/skills/` and six hooks are wired into `~/.claude/settings.json`: `coderv-router` (surfaces the right command at the right moment), `project-context` (every new session starts already knowing where each project left off), and the four anti-dumb-zone gates — `grounding-gate` (the first code edit is blocked until `/before` actually read the docs), `codex-review-gate` (every outgoing commit diff gets an adversarial review from a second model before it lands; needs [Codex CLI](https://github.com/openai/codex), fails loud-but-open without it), `compact-rehydrate` (after compaction, a live git snapshot outranks the summary), `context-gate` (warns and then hard-stops new work at an absolute dumb-zone token budget, ~180k — the dumb zone is an absolute occupancy floor, not a fraction of a huge window). Kill switch: `CODERV_GATES_OFF=1`.

**Manual path:**

```bash
git clone https://github.com/AbudiHadi/coderv
cd coderv
./install.sh
```

**Other CLIs (skills only — no hook):**

The 7 skills also work in [Codex CLI](https://github.com/openai/codex) and [Gemini CLI](https://github.com/google-gemini/gemini-cli) — both adopted the same SKILL.md format.

```bash
./install.sh --codex            # ~/.codex/skills/
./install.sh --gemini           # ~/.gemini/skills/
./install.sh --all              # all three hosts
```

All six hooks (`coderv-router`, `project-context`, and the four anti-dumb-zone gates) are Claude-Code-specific — the other CLIs don't have an equivalent hook system. On Codex / Gemini, the toolkit relies on the in-skill TRIGGER blocks alone — auto-suggest works but is less aggressive, and the gates don't apply.

**Update:**

```bash
curl -fsSL https://coderv.dev/install.sh | bash -s -- --force
```

The hooks are **copied** into `~/.claude/hooks/` at install time, so a `git pull`
alone does not change how your gate behaves — you must re-run `install.sh` (or the
one-liner above) for a new hook version to take effect. Behaviour changes to the
commit gate (e.g. the ADR-019 convergence ceiling in 0.13.0) are only live on your
machine after that reinstall.

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

## Watch the two brains work (coderv-loop)

The `codex-review-gate` runs the whole Claude↔Codex exchange in the background — you only see the final deny or LGTM. **coderv-loop** is an optional companion dashboard that makes that exchange visible live.

The gate appends one JSON line per beat to `~/.claude/coderlap/loop-events.jsonl` — the writer's commit attempt, the reviewer starting, its verdict, each finding, and the terminal outcome. It's a pure side-effect: the log never influences the gate's allow/deny decision, never errors the hook, and stays silent when `jq` is absent. Point the log elsewhere with `CODERV_LOOP_LOG`, or turn it off entirely with `CODERV_LOG_OFF=1`.

Every review closes with a terminal `outcome` event — a denied review, a passed one, a cache-hit retry, even a reviewer that timed out (marked `unreviewed:true`) — so a dashboard tailing the stream never hangs waiting for a beat that isn't coming.

coderv-loop is not part of the seven-command toolkit — it's a separate local app you run only if you want to watch. The toolkit works exactly the same without it.

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
The 7 commands are visible — you invoke them, they do their job visibly, no silent failure. That's the core. The `coderv-router` hook (Claude Code) is a thin layer on top of that: it doesn't *do* the work, it just makes sure Claude *offers* the right command when your phrasing matches. The work itself is still in the visible, markdown-only commands.

**Does the toolkit work with Codex CLI and Gemini CLI?**
Yes. Both CLIs adopted the same SKILL.md format. Install with `--codex`, `--gemini`, or `--all`. All six hooks (router, project map, and the four gates) are Claude-Code-specific, so on those hosts the toolkit relies on each skill's TRIGGER block — auto-suggest works but is less aggressive, and the anti-dumb-zone gates don't apply.

---

## Licence

CoderLap Source-Available Licence v1.0 — see [LICENCE](./LICENCE).

Free to read. Free for personal evaluation. **All other use — commercial, redistribution, hosting, incorporation, modification-then-sharing — requires written permission from Abdullah Hadi (support@coderv.com).**

Full licence: https://coderv.dev/licence
