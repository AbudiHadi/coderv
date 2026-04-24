---
name: decision
description: |
  Log an architectural decision (ADR) so the reasoning survives across sessions. Use right after you pick a library, a pattern, or a trade-off. Takes 30 seconds while it's fresh. Prevents "why did we do it this way?" re-debates months later. Also retrieves past decisions with `/decision list` or `/decision <topic>`.

  TRIGGER — suggest this skill (even without /decision prefix) when the user: picks between options ("X or Y?", "should we use A vs B", "choosing between"), asks "why did we pick X?", "why are we using Y?", "why did we choose", wants to document a trade-off, mentions "architectural decision", "ADR", "tech choice", or accepts a trade-off ("going with X despite the downside of Y").

  SKIP — for trivial picks with no trade-off (e.g. picking a variable name).
user-invocable: true
argument-hint: "[title to log new ADR | 'list' | topic to search]"
---

# Log or Retrieve a Decision

ADRs preserve *why* you chose X over Y. Without them, the next session (or the next person) re-debates it from scratch.

## Step 1 — Check the file exists

```bash
ls docs/DECISIONS.md 2>/dev/null
```

If missing: create it with this template:

```markdown
# Decision Log (ADRs)

> Every architectural / library / pattern / scope decision that will be second-guessed later.
> Newest at top. Never delete — if a decision is reversed, add a new ADR that supersedes the old one.

---
```

## Step 2 — Read the argument

### Argument = `list`

Read `docs/DECISIONS.md`. Extract every `## ADR-NNN:` heading. Output:

```
ADR log (N total)

Accepted:
- ADR-001: <title> — YYYY-MM-DD
- ADR-003: <title> — YYYY-MM-DD

Superseded:
- ADR-002: <title> — superseded by ADR-005
```

### Argument = a topic (e.g. "auth", "database")

Grep `docs/DECISIONS.md` for the term. Return matching ADRs with their Decision + Consequences summarised.

### Argument = a title (log a new one)

1. Find the highest existing ADR number. New one is `ADR-(N+1)`.
2. Ask the user (compact — one message, not 5):

```
Logging a new ADR. Tell me:
- Context: what's the problem?
- Decision: what are we choosing?
- Alternatives considered (at least 2, each with why rejected):
- Consequences (trade-off, what to revisit if):
- Decider(s):
```

3. Write the ADR at the **top** of `docs/DECISIONS.md` (newest first):

```markdown
## ADR-NNN: <Title>

**Date:** YYYY-MM-DD
**Status:** accepted
**Decider(s):** <name(s)>

### Context
<from user>

### Decision
<from user>

### Alternatives considered
- **<Option A>** (chosen) — <reason>
- **<Option B>** — <why rejected>
- **<Option C>** — <why rejected>

### Consequences
- Positive: <…>
- Trade-off: <…>
- Revisit if: <condition that would make us reconsider>
```

4. If this decision supersedes an older one:
   - Add "Supersedes ADR-MMM" to the new ADR.
   - Edit the old ADR: change `Status: accepted` → `Status: superseded by ADR-NNN (YYYY-MM-DD)`.
   - **Never delete** the old ADR.

## Output

```
Logged ADR-NNN: <title>
Location: docs/DECISIONS.md (line N)
```

One line. Done.
