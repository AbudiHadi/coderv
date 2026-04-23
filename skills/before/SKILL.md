---
name: before
description: Enforced pre-code checklist. Runs BEFORE editing any code — reads CLAUDE.md, maps the task via MASTER-INDEX, reads related docs, greps the repo for existing patterns, and checks KNOWN-ISSUES + DECISIONS for relevant context. Use whenever starting a task more complex than a one-line fix. Catches the "dive-in-and-regret" pattern.
user-invocable: true
argument-hint: "<task description, e.g. 'add rate limiting to /api/invite', 'fix the dark mode glitch on status banner'>"
---

# Before You Code — Read First

Stop the "skim and code" reflex. Do this checklist before touching any file.

## Step 1 — Sanity check

```bash
ls CLAUDE.md docs/MASTER-INDEX.md 2>/dev/null
```

If missing: run `/doc-init` first. Stop.

If no argument: ask the user "what's the task?" and stop until they answer.

## Step 2 — Read core docs

```
Read CLAUDE.md
Read docs/MASTER-INDEX.md
```

From CLAUDE.md, note: Code Principles, Never rules, Always rules, Integrations Registry.

## Step 3 — Map the task

Find the task type in MASTER-INDEX §"Task → Doc Map". Read the docs it lists **in order**.

If the task doesn't clearly match a row, use best judgment and say so explicitly in output.

## Step 4 — Look for prior art

Grep the repo for similar existing patterns:

```bash
# Find similar implementations
grep -rn "<key term from task>" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" | head -20

# Find related files
find . -path ./node_modules -prune -o -type f -name "*<keyword>*" -print 2>/dev/null | head -10
```

If similar code exists, **read it** before writing new code. Match the existing style.

## Step 5 — Check for relevant ADRs

```bash
grep -n "^## ADR" docs/DECISIONS.md 2>/dev/null
```

If any ADR relates to the task area, read it. Respect existing decisions unless you're consciously overturning one (which requires a new ADR via `/decision`).

## Step 6 — Check known issues

```bash
grep -i "<task keyword>" docs/KNOWN-ISSUES.md 2>/dev/null
```

If the task touches an area with past recurring bugs, note their Prevention rules. Don't re-introduce them.

## Step 7 — Check related gaps

```bash
ls docs/*-GAPS.md 2>/dev/null
```

If a gap doc covers this area, check whether the task closes a gap. If so, the user should run `/gap close <N>` after shipping.

## Step 8 — Check last session note

Read the last entry in `docs/SESSIONS.md`. It may contain "next session should probably…" hints or in-flight context.

## Step 9 — State the plan

Before writing code, output a plan:

```
## Pre-code orientation — <task>

**Read:**
- CLAUDE.md — <1 key rule that applies>
- <doc1> — <takeaway>
- <doc2> — <takeaway>

**Prior art:**
- <file:line> — <how existing code handles this>

**ADRs that apply:**
- ADR-NNN <title>

**Known issues in this area:**
- KI-NNN <title> — <prevention rule>

**Related gaps:**
- `<file>` §N — closes this? (<yes/no>)

**Plan:**
1. <step>
2. <step>
3. <step>

**Files I expect to touch:**
- <path>
- <path>

**Risks:**
- <anything surprising>

**After shipping, I'll run:** /ship
```

## Step 10 — Wait for confirmation

Do **not** start coding until the user confirms the plan (or corrects it). This is the whole point of `/before` — catching misalignment early.

If the plan was misaligned, iterate. Don't code until aligned.
