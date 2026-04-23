---
name: decision
description: Log an architectural decision (ADR) in docs/DECISIONS.md. Use when the user makes a non-trivial choice — a library pick, a pattern, a trade-off, a scope cut — that future sessions or teammates will second-guess. Also use to retrieve why past decisions were made (`/decision list` or `/decision <topic>`). Prevents "why did we do it this way?" re-litigation.
user-invocable: true
argument-hint: "[title to log new ADR | 'list' | topic to search past ADRs]"
---

# Log or Query a Decision (ADR)

Architectural Decision Records preserve *why* a choice was made. Future sessions without this context will drift.

## Step 1 — Sanity check

```bash
ls docs/DECISIONS.md 2>/dev/null
```

If missing: tell user to run `/doc-init` first. Stop.

## Step 2 — Interpret the argument

### Argument = `list` → show the ADR index

Read `docs/DECISIONS.md`, extract the title line of every `## ADR-NNN:` section. Output:

```
## ADR log (N total)

**Accepted:**
- ADR-001: <title> — YYYY-MM-DD
- ADR-003: <title> — YYYY-MM-DD

**Superseded:**
- ADR-002: <title> — superseded by ADR-005

**Deprecated:**
- (none)
```

### Argument = a topic (e.g. "auth", "database", "video") → search

Grep `docs/DECISIONS.md` for the term. Return matching ADRs with their Decision + Consequences sections summarised.

### Argument = a title → log a new ADR

1. Read `docs/DECISIONS.md` and find the highest existing ADR number (e.g. if ADR-007 is the last, the new one is ADR-008).
2. Ask the user to answer these (one by one or as a block):
   - **Context:** What's the problem / forces at play?
   - **Decision:** What are we choosing?
   - **Alternatives considered:** What else did we look at? Why did we reject them? (at least 2 alternatives)
   - **Consequences:** What's the trade-off? What might we revisit later?
   - **Decider(s):** Who made the call?
3. Write the new ADR at the top of the file (newest at top), using the template in DECISIONS.md:

```markdown
## ADR-NNN: <Title>

**Date:** YYYY-MM-DD (today)
**Status:** accepted
**Decider(s):** <name(s)>

### Context
<from user>

### Decision
<from user>

### Alternatives considered
- **<Option A>** (chosen) — <reason>
- **<Option B>** — <reason rejected>
- **<Option C>** — <reason rejected>

### Consequences
- Positive: <…>
- Negative / trade-off: <…>
- Revisit if: <condition that would make us reconsider>
```

4. Do **not** delete or modify existing ADRs. If this decision supersedes an older one:
   - Add "Supersedes ADR-MMM" to the new ADR.
   - In the old ADR, change `**Status:** accepted` to `**Status:** superseded by ADR-NNN (YYYY-MM-DD)`.

## Step 3 — Prompt for follow-ups

After logging, ask:
- Does this decision create a gap (something not yet built)? → `/gap new <area>` or add to existing.
- Does this decision invalidate a doc? → update it or mark archived via `/doc-new`.
- Does this decision need communicating? → write a `/session` note.

## Output format

For logging:
```
## Logged: ADR-NNN <title>

**Status:** accepted
**Location:** docs/DECISIONS.md

**Follow-ups suggested:**
- <list any>
```

For list/search: the ADR index or matching sections.
