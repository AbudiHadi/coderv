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
2. Ask the user — one friendly prompt, not five:

```markdown
**Logging a new decision 📋**

This will become **ADR-NNN: <your title>**, saved at the top of `docs/DECISIONS.md`. Future-you (or a teammate) reads this in 6 months to remember *why* — so the more honest the better.

**Tell me, in your own words:**

| Field | What to fill in |
|---|---|
| 🎯 The problem | What forced this decision? What were the constraints? |
| ✅ What you picked | The choice itself, in one sentence. |
| 🤔 What else you considered | At least 2 other options + why they lost. |
| ⚖️ The trade-off | What does this cost? What would make you reverse it? |
| 🙋 Who decided | Names. |
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

```markdown
**Decision logged 📋**

| What | Where |
|---|---|
| 📜 ADR-NNN | <title> |
| 📂 File | docs/DECISIONS.md (top of file) |
| ⏱️ Status | accepted |

👉 **My recommendation: keep going with the work — the decision is captured.** If this decision touches code you haven't written yet, run `/before <task>` next so the plan reflects it.
```
