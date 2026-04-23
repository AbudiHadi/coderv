---
name: docs
description: Orient around the current project's documentation. Reads docs/MASTER-INDEX.md, maps a task to the docs you should read first, and cites the rules that apply. Use at the start of any non-trivial task, when unsure where to find info, or when the user says "check the docs" / "what should I read for X". Works in any project that has been initialised with /doc-init.
user-invocable: true
argument-hint: "[task or area, e.g. 'new API route', 'partner earnings', 'billing webhook']"
---

# Docs Orientation

Orient around the current project's docs. **Do not skip steps.**

## Step 1 — Sanity check

```bash
ls docs/MASTER-INDEX.md 2>/dev/null
```

If `docs/MASTER-INDEX.md` does not exist: tell the user this project hasn't been initialised and suggest `/doc-init`. Stop.

## Step 2 — Read the master index

```
Read docs/MASTER-INDEX.md
```

After reading you should know:
- Which doc covers which area (Doc Registry)
- What to read before touching a given code type (Task → Doc Map)
- What to update after a change (Docs to Update on Feature Changes)
- How gap docs, ADRs, known-issues, and sessions work
- The Self-check to run at end-of-task

## Step 3 — If the user passed an argument

Interpret it as a task or area (`new API route`, `auth flow`, `billing webhook`, `dark mode`). Then:

1. Find the matching row in MASTER-INDEX §"Task → Doc Map".
2. Read those docs **in order**.
3. Also read any file paths mentioned in those docs (similar existing code, schema file, etc.).
4. Grep the repo for patterns mentioned in the docs so you know how they're used today.
5. Check `docs/DECISIONS.md` for any ADR that affects this area.
6. Check `docs/KNOWN-ISSUES.md` for recurring bugs in this area.
7. Check `docs/*-GAPS.md` for related missing work.

## Step 4 — If no argument

Summarise the project's doc structure in 5–8 lines and prompt:

```
Tell me the task and I'll map it via Task → Doc Map.

Useful commands:
- /before <task>  — enforced pre-code checklist
- /gap             — see what's missing
- /decision        — log an architectural choice
- /ship            — pre-commit checklist
```

## Step 5 — Reminder for the rest of the session

After this skill runs, for the rest of the session:
- Before editing anything, re-check "Before ANY Change — READ First" in CLAUDE.md.
- Before committing, run `/ship`.
- If you make a design choice with trade-offs, run `/decision`.
- If you fix a non-obvious bug, add to `docs/KNOWN-ISSUES.md`.

## Output format

```
## Doc orientation — <task or "general">

**Read:**
- <doc 1> — <one-line takeaway relevant to task>
- <doc 2> — <one-line takeaway>

**Rules that apply:**
- <rule> — cited from <file:line>

**Relevant ADRs:**
- <ADR-NNN title or "none">

**Known issues in this area:**
- <KI-NNN title or "none">

**Related gaps:**
- `docs/<AREA>-GAPS.md` §N <title> — <status>

**Next step:**
- <what the user should do now>
```

Keep it tight. No filler.
