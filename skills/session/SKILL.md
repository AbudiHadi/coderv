---
name: session
description: |
  Write a session handoff note so the next session (you or a teammate) picks up cleanly — no more "what was I doing again?" on Monday morning. Use at end of session. Use `/session last` at the start of a session to read the previous handoff.

  TRIGGER (end-of-session) — suggest this skill (even without /session prefix) when the user says: "I'm done for today", "done for the day", "wrap up", "wrapping up", "see you tomorrow", "see you next week", "stopping here", "pausing here", "leaving it here", "continue later", "tomorrow-me", "taking a break", "lunch break", "end of day", "EOD".

  TRIGGER (start-of-session) — suggest `/session last` when the user says: "where did I leave off?", "what was I doing?", "pick up where I left off", "what's next?", "status?", "what was last?", "continue from yesterday", "remind me what we were doing".

  SKIP — in the middle of active work with no break in sight.
user-invocable: true
argument-hint: "[short title | 'last' to read most recent]"
---

# Session Handoff

Capture what happened so the next session doesn't start from zero.

## Step 1 — Check the file exists

```bash
ls docs/SESSIONS.md 2>/dev/null
```

If missing, create it with this header:

```markdown
# Session Handoffs

> End-of-session notes so the next session picks up cleanly. Newest at top.

---
```

## Step 2 — Read the argument

### Argument = `last`

Read the file, return the topmost `## YYYY-MM-DD — ...` section verbatim. That's the last handoff.

### Otherwise (new handoff)

Gather context before asking the user:

```bash
git log --since="6 hours ago" --oneline
git status
git diff --stat
```

Then ask the user (one compact prompt):

```
End-of-session handoff. Fill in:
- Title (or leave blank, I'll use the branch/commit hint):
- What shipped (from git log, confirm/edit):
- In flight (not yet shipped):
- Gotchas the next session should know:
- Next session should probably:
```

Prepend a new entry to the **top** of `docs/SESSIONS.md`:

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

Use today's date. If multiple sessions in one day, add a time suffix: `YYYY-MM-DD 14:30 — Title`.

## Step 3 — Prompt for related follow-ups (briefly, one line each)

If the session:
- Made a non-obvious design choice → "Consider logging an ADR with `/decision`."
- Fixed a non-obvious bug → "Add an entry to `docs/KNOWN-ISSUES.md` while it's fresh."
- Hit a milestone → "Update project status in `CLAUDE.md`."

## Output

```
Session logged: <title>
Location: docs/SESSIONS.md

Next session: start with /session last
```
