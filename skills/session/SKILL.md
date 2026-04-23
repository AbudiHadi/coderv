---
name: session
description: Write an end-of-session handoff note in docs/SESSIONS.md so the next session (or teammate) picks up cleanly without re-discovering state. Use at the end of any session that left work in flight, made non-trivial changes, or uncovered info the next session needs. Also use `/session last` to read the most recent handoff.
user-invocable: true
argument-hint: "[short title for the session | 'last' to read most recent]"
---

# Session Handoff

Capture what happened so the next session doesn't start from zero.

## Step 1 — Sanity check

```bash
ls docs/SESSIONS.md 2>/dev/null
```

If missing: tell user to run `/doc-init`. Stop.

## Step 2 — If argument is `last`

Read `docs/SESSIONS.md` and return the most recent entry (the topmost `## YYYY-MM-DD — ...` section). Include the full content so the user sees exactly what the prior session left.

## Step 3 — Otherwise: write a new handoff

Gather info. Ask the user if they don't proactively say:

1. **Title** (from argument, or ask)
2. **What shipped** — changes merged/committed this session, with file paths or commit hashes
3. **In flight** — work-in-progress, not yet committed or not yet working
4. **Gotchas** — anything surprising the next session should know (e.g. "prod DB schema differs from staging", "feature flag is off by default", "100ms webhook takes 30s in staging")
5. **Next session should probably** — 1–3 suggested next steps

Also pull context programmatically to jog memory:

```bash
git log --since="6 hours ago" --oneline
git status
git diff --stat
```

## Step 4 — Write to SESSIONS.md

Prepend to the file (newest at top) — do not append to the bottom:

```markdown
## YYYY-MM-DD — <Title>

**What shipped:**
- <change> — <file:line or commit hash>

**In flight (not yet shipped):**
- <what> — <blocker or next step>

**Gotchas the next session should know:**
- <anything surprising>

**Next session should probably:**
- <suggested next step>

---
```

Use today's date. If there are multiple sessions in a day, include a time suffix: `YYYY-MM-DD 14:30 — Title`.

## Step 5 — Prompt for related updates

If the session:
- Made a design choice → suggest `/decision`
- Fixed a non-obvious bug → suggest adding to `docs/KNOWN-ISSUES.md`
- Shipped a gap → suggest `/gap close <N>`
- Hit a milestone → suggest updating CLAUDE.md status

## Step 6 — Output

```
## Session logged: <title>

**Written to:** docs/SESSIONS.md
**In flight:** N items
**Suggested follow-ups:** <list any>

Next session: start with `/session last` + `/docs`.
```
