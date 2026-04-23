---
name: gap
description: Track missing, thin, or broken features in the current project. Without args lists all open gaps across every `docs/*-GAPS.md`. With an area arg, drills into that domain. Use `/gap close <N>` to mark a gap as shipped (preserves history). Use `/gap new <area>` to create a new gap doc. Works in any project initialised with /doc-init.
user-invocable: true
argument-hint: "[area | close <N> | new <area> | empty for full list]"
---

# Gap Tracker

Work with the project's gap docs. Gap docs live at `docs/*-GAPS.md` and track what's missing, thin, or broken. Each gap has: Status, Priority (P0–P3), Impact, Effort (S/M/L), Dependencies, Acceptance criteria.

## Step 1 — Discover gap docs

```bash
ls docs/*-GAPS.md 2>/dev/null
```

If none exist, check `docs/MASTER-INDEX.md` §"Gap Tracking" and tell the user "no gap docs yet — use `/gap new <area>` to start tracking".

## Step 2 — Interpret the argument

### No argument → full open-gaps report

Read every `docs/*-GAPS.md`. Extract any section whose Status is **not** `shipped` or `wontfix`. Group by priority.

```
## Open gaps — all areas

**Total open:** N (P0: X, P1: Y, P2: Z, P3: W)
**Shipped in last 30 days:** N

### P0 (blockers)
- [<area>] #<num> <title> — <one-line impact>

### P1 (important)
- ...

### P2, P3 (nice-to-have)
- ...

**Recommended next 3:** <from each gap doc's recommended-order section, top-weighted>

**Gap docs read:** <list>
```

### Argument = area name (e.g. `partner`, `billing`)

1. Find `docs/<AREA-UPPERCASE>-GAPS.md`. If missing, offer to `/gap new <area>`.
2. Read it fully.
3. Produce the same prioritised output scoped to that area.

### Argument = `close <N>` or `close <area> <N>`

1. Locate section `## <N>.` in the relevant gap doc.
2. Read the full section — especially Acceptance criteria.
3. Ask the user: "The acceptance criteria are: [list]. Are all met? (y/n)"
4. If yes:
   - Run `git rev-parse --short HEAD` to get the current commit hash.
   - Edit the gap doc: change `**Status:** <old>` to `**Status:** shipped YYYY-MM-DD (commit: <hash>)` using today's date.
   - Keep Priority, Impact, Effort, Dependencies, Acceptance criteria intact — they become history.
5. Suggest the user also:
   - Update any phase/milestone doc if this unblocks one
   - Consider adding an ADR via `/decision` if the implementation made a non-obvious choice
   - Add to `docs/KNOWN-ISSUES.md` if the gap existed because of a recurring bug

### Argument = `new <area>` (e.g. `new billing`)

1. Create `docs/<AREA-UPPERCASE>-GAPS.md` using this template:

```markdown
# <Area> — Gap Analysis

> **Purpose:** Track features that are missing, thin, or broken in the <area> of this project.
> **Audience:** Engineering + product. Claude reads this before touching any <area> code.
> **Last Updated:** YYYY-MM-DD
> **Status:** current (active gap doc)

---

## Current State — What Exists Today

<brief description of what's already built in this area, with file paths>

---

## Priority Legend

- **P0** — blocks real operations
- **P1** — users will complain within weeks of real use
- **P2** — expected by mature customers
- **P3** — polish

**Effort:** S = <1 day • M = 1–3 days • L = 1+ week

---

## 1. <Gap title>

**Status:** missing | partial | broken
**Priority:** P0 | P1 | P2 | P3
**Impact:** who suffers, in what scenario
**Effort:** S | M | L
**Dependencies:** what blocks this
**Acceptance criteria:**
- criterion 1
- criterion 2

---

## How to Close a Gap

1. Ship the feature.
2. In this file, change `**Status:**` to `shipped YYYY-MM-DD (commit: <hash>)`.
3. Keep all other fields intact — they become history.
4. If invalidated, change to `wontfix YYYY-MM-DD — <reason>`. Do not delete.

---

## Recommended Order

If we had to pick, ship in this order:
1. P0 items first
2. P1 quick wins (small effort)
3. P1 larger
4. P2, P3 as time permits
```

2. **Register in MASTER-INDEX** — add a row under §"Gap Tracking" → "Current gap docs". Non-negotiable.

## Step 3 — Enforce the contract

Before finishing:
- Closed a gap? Confirm section still has all original fields (never deleted).
- Created a gap doc? Confirm it's registered in `docs/MASTER-INDEX.md`.
- Gap closure unblocks a phase? Prompt to update the phase doc.

Keep output compact. No preamble.
