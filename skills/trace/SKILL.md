---
name: trace
description: Given a symptom (a bug, an error, an unexpected behaviour), walk backward through the code to find the root cause. Structured debugging method: reproduce → localise → identify → minimally fix. Keeps the investigation honest, avoids "fix the first thing that looks wrong". Also logs the finding to KNOWN-ISSUES if non-obvious. Use when you don't already know the cause.
user-invocable: true
argument-hint: "<symptom: error message, unexpected behaviour, failing test>"
---

# Root-Cause Trace

Structured debugging. No cargo-cult fixes.

## Step 0 — Sanity check

If no argument: ask "what's the symptom?" and stop.

## Step 1 — Check for known issues first

Run `/repeat <symptom>` mentally: grep `docs/KNOWN-ISSUES.md` for the symptom. If there's a match, stop and apply the known prevention. Don't re-investigate what's already solved.

```bash
grep -i "<symptom keyword>" docs/KNOWN-ISSUES.md 2>/dev/null
```

## Step 2 — Reproduce

Can you reliably reproduce the symptom?

- If **no**: ask the user for exact steps. If they can't repro either, flag it as "unreproducible — too little info" and stop. Don't fix what you can't see.
- If **yes**: state the reproduction steps verbatim so we know we're solving the right thing.

## Step 3 — Localise

Trace from the symptom surface inward:

1. **Error message** → grep for the literal string in the codebase. Find where it's thrown.
2. **API response** → find the route handler, then the service, then the data source.
3. **UI glitch** → find the component, then the props/state, then the data flow.
4. **Failing test** → read the test, understand the assertion, run it with `--verbose` or equivalent.

Report what you find at each layer. Don't skip layers. Don't guess.

```bash
# examples
grep -rn "Room not active" --include="*.ts"
grep -rn "<error message>" .
git log -S "<error message>" --oneline | head -5   # who introduced it
git log -p --follow <file> | head -100             # how it evolved
```

## Step 4 — Identify

State the root cause in 1–2 sentences. Distinguish:

- **Logic bug** — code does what it says, but what it says is wrong
- **Missing guard** — edge case not handled
- **Integration drift** — external contract changed
- **Config** — env var / flag / setting wrong for this environment
- **Data** — bad data in the DB/cache, code is fine
- **Race** — concurrent execution exposes unsafe order

If you can't confidently name one of these, keep investigating. **"I don't know yet" is a valid answer** — don't pick a cause you don't believe.

## Step 5 — Propose minimal fix

State the smallest change that addresses the root cause, not the symptom. Before coding:

- Does the fix belong here, or does the bug indicate a missing abstraction? (usually: don't refactor, just fix)
- Are there other callers of the broken function that share the same bug? Fix all or flag them.
- Will the fix re-introduce itself next time someone edits this code? Add a guard, not a comment.

## Step 6 — Verify

After the fix:

- Run the reproduction steps. Confirm the symptom is gone.
- Run adjacent tests. Confirm nothing else broke.
- Grep for the anti-pattern that caused it — is it repeated elsewhere?

## Step 7 — Log if non-obvious

If the bug took >15 min to root-cause, or the cause was non-obvious, log it via `/repeat add`. The Prevention field is the most valuable part — write a rule that would catch this class of bug.

## Output format

```
## Trace: <symptom>

**Reproduced:** yes (steps: …) | no (insufficient info)
**Known issue match:** KI-NNN | none

**Layers traced:**
1. <surface> — <finding>
2. <middle> — <finding>
3. <root> — <finding>

**Root cause:** <1–2 sentences, labelled by category>

**Fix plan:** <minimal change, file:line>

**Side effects / other callers:** <list or "none found">

**Prevention (if fix lands):** <rule/test/type/check>

**Log as KI?** yes (>15 min to root-cause) | no
```

Wait for user confirmation before writing the fix.
