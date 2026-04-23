---
name: repeat
description: Check whether a bug symptom has been seen before. Searches docs/KNOWN-ISSUES.md for matching symptoms, root causes, and prevention notes. Use when debugging — before spending time tracing, check if the team has already solved this exact thing. Also use `/repeat add` to log a newly-found recurring bug.
user-invocable: true
argument-hint: "<symptom in user's words | 'add' to log a new recurring bug>"
---

# Recurring Bug Check

Stop solving the same problem twice.

## Step 1 — Sanity check

```bash
ls docs/KNOWN-ISSUES.md 2>/dev/null
```

If missing: tell user to run `/doc-init`. Stop.

If no argument: ask for the symptom or intent (`add` a new one, or describe the symptom to search).

## Step 2 — If argument = `add`

Walk the user through adding a new entry. Ask:

1. **Symptom** — in the user's/tester's words (e.g. "100ms video says 'room not active'")
2. **First seen** — when (commit, session date)
3. **Root cause** — the actual bug (not a description of the fix)
4. **Fix** — what changed, file paths + line ranges
5. **Prevention** — what would have caught this earlier? (a test? a type? a lint rule? a review checklist item?)
6. **Related** — ADR-NNN or other KI-NNN if part of a family

Find the highest existing KI number and increment. Write to `docs/KNOWN-ISSUES.md` after the template section (newest first among real entries):

```markdown
## KI-NNN: <Symptom>

**First seen:** YYYY-MM-DD
**Last seen:** YYYY-MM-DD
**Status:** fixed in commit <hash> | open

### Symptom
<from user>

### Root cause
<from user — should be 1–3 sentences, the actual mechanism>

### Fix
<what was changed, with file paths and line ranges if possible>

### Prevention
<rule/test/check that would catch this earlier>

### Related
- <ADR-NNN / KI-NNN if any>
```

## Step 3 — If argument = symptom to search

Grep `docs/KNOWN-ISSUES.md` for the symptom and related keywords. If a matching KI exists, output:

```
## Match found: KI-NNN <title>

**Symptom:** <matched text>
**Root cause:** <one-sentence summary>
**Fix location:** <file:line>
**Prevention:** <rule>

**Action:** check if this is the same bug. If yes, apply the prevention rule; if different, log as a new KI via `/repeat add`.
```

If nothing matches, say so and prompt the user to proceed with normal debugging. Remind them: if the bug turns out to be non-obvious (>15 min to root-cause), log it afterwards via `/repeat add`.

## Step 4 — Update `Last seen`

If a match was found and the symptom recurred in reality, edit the matching entry to update `**Last seen:** YYYY-MM-DD` to today. This tells the team the prevention rule isn't working — it should be revisited.

## Output format

For matches:
```
## Match: KI-NNN — <title>
- Symptom: <brief>
- Root cause: <one-liner>
- Fix: <file:line>
- Prevention: <rule>

**Updated:** Last seen → today (if applicable)
```

For new entries:
```
## Logged: KI-NNN — <title>
- Written to docs/KNOWN-ISSUES.md
- Prevention rule: <the rule>

**Follow-up:** consider adding a test/lint/check that enforces the prevention rule.
```
