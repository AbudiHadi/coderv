---
name: before
description: Pre-code checklist that reads the relevant docs, greps prior art, checks past decisions, states a plan, and waits for approval. Runs automatically before any non-trivial code change so the dev never has to remember what to read. Skips itself for tiny / exploratory edits. This is the core discipline skill — it prevents Claude from diving in without context.
user-invocable: true
argument-hint: "<task description, e.g. 'add rate limiting to /api/invite'>"
---

# Before You Code

You've been asked to plan a task before writing any code. **Stop, read, plan, wait for approval.** Never skip to writing code.

## Step 1 — Decide if this skill should run at all

**Skip this skill (go straight to the task) when:**
- The task is a one-line change, typo fix, or documentation-only edit.
- The user said "quick fix", "small change", "just", or "simple".
- The task is undoing or tweaking code from earlier in THIS session (you already have the context).
- The task is an interactive debugging pivot and a plan would go stale fast.

**Always run this skill when:**
- First time touching a module / directory this session.
- Task description contains "add", "refactor", "rename", "rewrite", "integrate", "migrate".
- The change will touch 3+ files or rename something used widely.
- User said "take your time", "think about this", or "be careful".
- After a long gap — first task of the day, or first time in this repo this week.

If you skip, tell the user: `skipping /before — task is <reason>`. Then do the task directly.

## Step 2 — First run in this project?

Check if the doc system is set up:

```bash
ls CLAUDE.md docs/DECISIONS.md docs/KNOWN-ISSUES.md docs/SESSIONS.md 2>/dev/null
```

If **any of the 4 are missing** (and this is the first time `/before` runs in this project), offer to create them:

> "This looks like a fresh project. Want me to scaffold the 4 doc files + `CLAUDE.md`? (y/n)"

If yes: create the missing files using these minimal templates:

- `CLAUDE.md` — standard template (see https://coderv.dev/docs for content).
- `docs/DECISIONS.md` — single header line + "newest at top" note.
- `docs/KNOWN-ISSUES.md` — header + format template.
- `docs/SESSIONS.md` — header + newest-at-top note.

Never overwrite existing files.

If the user says no, continue with the task using just what you can learn from the code.

## Step 3 — Read the docs you need

Read in this order:

1. `CLAUDE.md` — rules, patterns, principles.
2. `docs/MASTER-INDEX.md` if it exists — find the rows in "Task → Doc Map" that match.
3. Any docs named in that map, in order.
4. If `docs/DECISIONS.md` exists — grep it for terms related to the task. If any ADR applies, read it.
5. If `docs/KNOWN-ISSUES.md` exists — grep it. If there's a prior bug in this area, note the prevention rule.
6. If `docs/SESSIONS.md` exists — read the last entry. It may have "next session should probably…" hints or in-flight context.

## Step 4 — Find prior art in the code

Grep the repo for terms from the task:

```bash
grep -rn "<key term>" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" | head -20
find . -path ./node_modules -prune -o -type f -name "*<keyword>*" -print 2>/dev/null | head -10
```

If similar code exists — **read it** before writing new code. Match the existing style. Don't reinvent what already exists.

## Step 5 — State the plan

Before writing any code, output a plan in this exact shape. Keep it tight.

```
## Plan — <task>

Read:
- CLAUDE.md: <one key rule that applies>
- <doc>: <takeaway>

Prior art:
- <file:line> — <how existing code handles this>

Decisions that apply:
- ADR-NNN <title>     (or "none found")

Known issues in this area:
- KI-NNN <title> — prevention: <rule>    (or "none")

Plan:
1. <step>
2. <step>
3. <step>

Files I expect to touch:
- <path>
- <path>

Risks / things I'm unsure about:
- <anything surprising, or "none")
```

## Step 6 — Wait for approval

Do **not** start coding until the user confirms the plan (or corrects it). This is the whole point — catch misalignment before, not after.

If the user corrects the plan, update it and re-state it. Don't code until aligned.

## Step 7 — Watch for follow-ups (during the task, not just after)

As you code, suggest the right next command **at the right moment**. Don't wait for the end.

- **Design choice made with trade-offs?** Say once, inline: *"This is a real trade-off between X and Y — worth logging with `/decision`?"*
- **Non-obvious bug found and fixed?** (>15 min to root-cause, or subtle cause) Say: *"Worth adding to `KNOWN-ISSUES` via `/ship`? The prevention rule would be: <draft rule>."*
- **Closes a gap** listed in `docs/*-GAPS.md`? Say: *"This closes gap #N — `/ship` will offer to mark it shipped."*
- **Session running long** (you've coded for 1+ hours without a commit or the user is pausing)? Say: *"Want me to write a `/session` handoff, or `/ship` the current state?"*

**Never auto-run skills.** Always suggest. User approves or ignores.

## Step 8 — Remind before commit

When the task is done: *"Ready to commit? Run `/ship` — it'll walk doc updates and draft a commit message."*
