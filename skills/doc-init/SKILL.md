---
name: doc-init
description: Bootstrap the Claude docs toolkit in a fresh project. Creates docs/MASTER-INDEX.md, docs/DECISIONS.md (ADR log), docs/KNOWN-ISSUES.md, docs/SESSIONS.md, and a CLAUDE.md section that teaches Claude the doc system rules. Idempotent — safe to run on an existing toolkit install (will detect and skip files). Use on day 1 of a project, or when introducing the toolkit to an existing codebase.
user-invocable: true
argument-hint: "(no args — detects project root from cwd)"
---

# Bootstrap the Docs Toolkit

You've been asked to set up the docs toolkit in this project. Follow these steps **in order**. Be idempotent — if a file already exists, don't overwrite; report and move on.

## Step 0 — Detect project root

```bash
pwd                    # if a git repo, use `git rev-parse --show-toplevel` instead
ls -la                 # sanity check
```

If not a git repo, ask the user to confirm the current directory is the intended project root before proceeding.

## Step 1 — Check what already exists

```bash
ls docs/ 2>/dev/null
ls CLAUDE.md 2>/dev/null
ls .claude/ 2>/dev/null
```

Report which of these already exist. You will not overwrite them.

## Step 2 — Create `docs/` folder structure

```bash
mkdir -p docs docs/plans
```

## Step 3 — Create MASTER-INDEX.md (if missing)

Write `docs/MASTER-INDEX.md` with this content (customise `<PROJECT NAME>`):

```markdown
# <PROJECT NAME> — Master Documentation Index

> **Purpose:** Single source of truth for all project documentation. Connects every doc, explains what each is for, and tells Claude (and humans) how to add, update, and retire docs without creating parallel truths.
>
> **Last Updated:** YYYY-MM-DD (today)
> **Maintained by:** Every contributor (Claude included) — if you touch a doc, update this index in the same commit.

---

## How to Use This Index

1. **Starting a task?** Use `/docs <task>` to map the task to the right docs.
2. **Adding a feature?** After shipping, `/ship` walks through the update checklist.
3. **Adding a new doc?** Use `/doc-new` — it registers the doc here automatically.
4. **Tracking gaps?** Use `/gap` for missing-feature tracking.
5. **Logging a decision?** Use `/decision` for ADRs.

### Slash Commands

| Command | When to use |
|---|---|
| `/docs [task]` | Any non-trivial task — loads this index and tells you what to read |
| `/before <task>` | Enforced read-before-code: runs doc checklist + greps repo for patterns |
| `/gap [area\|close N\|new area]` | List, drill, close, or create gap docs |
| `/doc-new <type> <title>` | Create a new doc + auto-register here |
| `/decision <title>` | Log an ADR in `docs/DECISIONS.md` |
| `/ship` | Pre-commit checklist: tests, docs, gap closures, changelog |
| `/session` | Write an end-of-session handoff note for the next session |
| `/repeat <symptom>` | Check `docs/KNOWN-ISSUES.md` before debugging |
| `/trace <symptom>` | Root-cause walk from symptom back through the code |

---

## Doc Registry

Status legend: `current` = live truth • `reference` = stable knowledge • `historical` = frozen snapshot • `plan` = not yet built • `archive` = superseded

### Core

| Doc | Purpose | Status |
|---|---|---|
| [`docs/MASTER-INDEX.md`](./MASTER-INDEX.md) | This file — doc registry | current |
| [`docs/DECISIONS.md`](./DECISIONS.md) | ADR log — why we chose X over Y | current |
| [`docs/KNOWN-ISSUES.md`](./KNOWN-ISSUES.md) | Recurring bugs + their fixes | current |
| [`docs/SESSIONS.md`](./SESSIONS.md) | End-of-session handoff notes | rolling log |

### Add more rows as the project grows

Examples:

| Doc | Read when you're touching… | Update when you… |
|---|---|---|
| `docs/architecture.md` | Service layer, request flow | Rename a service, change request flow |
| `docs/api.md` | Any API route | Add/change/remove an API route |
| `docs/database.md` | Schema, models | Run a migration |
| `docs/<AREA>-GAPS.md` | A domain with known missing features | Close or add a gap |

---

## Task → Doc Map

| Task | Read in this order |
|---|---|
| Add an API route | `docs/api.md` → similar existing route |
| UI component | `docs/components.md` → similar component |
| DB schema | `docs/database.md` → `prisma/schema.prisma` (or your ORM) |
| External API | `docs/integrations.md` → existing integration |
| Bug fix | `docs/KNOWN-ISSUES.md` → `docs/DECISIONS.md` |
| Design choice | `docs/DECISIONS.md` (add ADR if new) |

---

## Docs to Update on Feature Changes

| Change | Docs to update |
|---|---|
| New API route | `docs/api.md` |
| New component | `docs/components.md` |
| Schema migration | `docs/database.md` |
| External API added | `docs/integrations.md` + `CLAUDE.md` Integrations Registry |
| Shipped a gap | `docs/*-GAPS.md` — mark `shipped YYYY-MM-DD (commit: <hash>)` |
| New design decision | `docs/DECISIONS.md` — add ADR |
| Fixed a recurring bug | `docs/KNOWN-ISSUES.md` — add entry |

---

## Gap Tracking

Gap docs track what's missing. Format: `docs/<AREA>-GAPS.md`. Each entry has:

- **Status:** `missing` / `partial` / `broken` / `shipped YYYY-MM-DD` / `wontfix YYYY-MM-DD — <reason>`
- **Priority:** P0 (blocker) → P3 (polish)
- **Impact:** who suffers
- **Effort:** S / M / L
- **Dependencies:** what blocks it
- **Acceptance criteria:** how we know it's done

Closing a gap = change status to `shipped YYYY-MM-DD`, keep everything else for history. Never delete.

---

## Decision Log (ADRs)

See [`docs/DECISIONS.md`](./DECISIONS.md). Log every choice that will be second-guessed later: library picks, patterns, trade-offs, scope cuts. Use `/decision <title>` to add one.

---

## How to Add a New Doc

Use `/doc-new <type> <title>`. The skill creates the file with the required header and registers it here.

Required header for any new doc:

```markdown
# <Title>

> **Purpose:** one-line
> **Audience:** who reads this
> **Last Updated:** YYYY-MM-DD
> **Status:** current | reference | plan | historical
```

---

## Self-check (run before ending a task)

- [ ] New doc? → registered here
- [ ] Shipped a gap? → marked `shipped YYYY-MM-DD (commit: <hash>)`
- [ ] New design choice? → ADR in `DECISIONS.md`
- [ ] Found/fixed a recurring bug? → entry in `KNOWN-ISSUES.md`
- [ ] Phase/milestone done? → update project status wherever it lives
- [ ] User-facing strings changed? → both locale files (if i18n)
- [ ] Schema changed? → `docs/database.md` + all services reading changed fields
```

## Step 4 — Create DECISIONS.md (ADR log)

Write `docs/DECISIONS.md`:

```markdown
# Decision Log (ADRs)

> **Purpose:** Every architectural / library / pattern / scope decision that will be second-guessed later. Prevents "why did we do it this way?" re-litigation in future sessions.
>
> **Format:** One ADR per section. Newest at top. Never delete — if a decision is reversed, add a new ADR that supersedes the old one with a pointer.

---

## Template

```
## ADR-NNN: <Short title>

**Date:** YYYY-MM-DD
**Status:** accepted | superseded by ADR-MMM | deprecated
**Decider(s):** <name(s)>

### Context
What is the problem? What forces are at play?

### Decision
What did we decide?

### Alternatives considered
- **Option A** (chosen) — why
- **Option B** — why not
- **Option C** — why not

### Consequences
- Positive: …
- Negative / trade-off: …
- Unknown / revisit-if: …
```

---
```

## Step 5 — Create KNOWN-ISSUES.md

Write `docs/KNOWN-ISSUES.md`:

```markdown
# Known Issues & Recurring Bugs

> **Purpose:** Stop solving the same problem twice. Every time a non-obvious bug is fixed, log it here with symptom, root cause, and fix.
>
> **When to add:** After any bug fix where (a) the cause was non-obvious, (b) the same symptom could recur, or (c) the debugging took more than 15 minutes.

---

## Template

```
## KI-NNN: <Symptom in user's words>

**First seen:** YYYY-MM-DD
**Last seen:** YYYY-MM-DD
**Status:** open | fixed in commit <hash>

### Symptom
What the user/tester sees.

### Root cause
The actual bug — not a description of the fix.

### Fix
What was changed. File paths + line ranges.

### Prevention
What pattern or check would have caught this earlier? (Tests? Lint rule? Type? Review checklist?)

### Related
- ADR-NNN if relevant
- Other KI-NNN if part of a family
```

---
```

## Step 6 — Create SESSIONS.md

Write `docs/SESSIONS.md`:

```markdown
# Session Handoffs

> **Purpose:** End-of-session notes so the next Claude session (or human) picks up cleanly without re-discovering state.
>
> **When to add:** At the end of any session that left work in-flight, made non-trivial changes, or uncovered info the next session needs. Use `/session` to add one.

---

## Template

```
## YYYY-MM-DD — <Session title>

**What shipped:**
- <change> — <file:line or commit>

**In flight (not yet shipped):**
- <what> — <blocker or next step>

**Gotchas the next session should know:**
- <anything surprising>

**Next session should probably:**
- <suggested next step>
```

---
```

## Step 7 — Update or create CLAUDE.md

If `CLAUDE.md` does not exist, create it at project root with this:

```markdown
# Project AI Instructions

## First Action (EVERY session)

Before any code change, read `docs/MASTER-INDEX.md` and the docs it points to for your task type.

**Slash commands available:**
- `/docs [task]` — orient around the doc system
- `/before <task>` — pre-code checklist
- `/gap` — missing-features tracker
- `/doc-new` — create a registered doc
- `/decision` — log an ADR
- `/ship` — pre-commit checklist
- `/session` — end-of-session handoff
- `/repeat <symptom>` — check known issues first
- `/trace <symptom>` — root-cause walk

## Code Principles

- SR (Single Responsibility): one thing per function/component
- DRY: shared services, not copy-paste
- CC (Component Composition): small composable pieces
- SoC (Separation of Concerns): routes → services → DB

## Doc System Rules

1. Never create a doc without registering it in `docs/MASTER-INDEX.md` (same commit).
2. Never duplicate content across docs — link instead.
3. Dated snapshots are immutable — new date = new file.
4. Gap closures = `shipped YYYY-MM-DD (commit: <hash>)`, never delete.
5. Run the Self-check in `MASTER-INDEX.md` before ending a task.

## NEVER

- Skip reading docs before coding
- Add features/helpers/refactors not asked for
- Commit without running `/ship` checklist
- Delete a gap or ADR — mark status instead

## ALWAYS

- Read CLAUDE.md + MASTER-INDEX first
- Update docs that describe changed code, in the same commit
- Log new design decisions as ADRs
- Log non-obvious bug fixes in KNOWN-ISSUES.md
```

If `CLAUDE.md` already exists, **do not overwrite**. Instead, offer to append the "Slash commands available" block and "Doc System Rules" section. Ask the user before editing.

## Step 8 — Report

Print a summary:

```
## Docs toolkit initialised

**Created:**
- docs/MASTER-INDEX.md
- docs/DECISIONS.md
- docs/KNOWN-ISSUES.md
- docs/SESSIONS.md
- CLAUDE.md (or appended slash commands section)

**Already existed (untouched):**
- <list any>

**Next steps:**
1. Customise `<PROJECT NAME>` in MASTER-INDEX.md
2. Add project-specific docs (architecture, api, components, database, integrations) as needed
3. Try `/docs` to confirm the system works
4. Commit: `docs: initialise docs toolkit`
```
