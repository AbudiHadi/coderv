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

Then ask the user — terse, one prompt:

```markdown
👋 Wrapping up. Git shows: <N commits this session> · <M files in flight> · branch `<name>`.

**Fill in (just what applies):**
- **Title:** (or leave blank — I'll use a commit hint)
- **Gotchas for next-you:** (anything weird?)
- **Next session should probably:** (one suggestion)

*Want to see the full git log + diff stats first? Say "show git".*
```

Prepend a new entry to the **top** of `docs/SESSIONS.md`:

````markdown
## YYYY-MM-DD — <Title>

**What shipped:**
- <change> — <file:line or commit hash>

**In flight (not yet shipped):**
- <what> — <blocker or next step>

**State evidence (verbatim, from Step 2's commands):**
```
$ git log --oneline -3
<raw output pasted — not retyped, not summarized>
$ git status --short
<raw output>
<version file contents if the project has them>
```

**Gotchas the next session should know:**
- <anything surprising>

**Next session should probably:**
- <suggested next step>

---
````

Use today's date. If multiple sessions in one day, add a time suffix: `YYYY-MM-DD 14:30 — Title`.

**The evidence block is the load-bearing part.** A handoff is often written
late in a session — exactly when recollection is least reliable (and past the
context gate, it's mandatory). The rule (per ADR-004): **state claims are
pasted command output, never prose.** "Committed and pushed" without the `git
log` line underneath is not a valid handoff claim — a degraded session can
misremember; it can't mis-paste. The next session trusts the block, re-verifies
anything outside it.

## Step 3 — Rotate when the file gets heavy

SESSIONS.md is read at every session start (by you, `/before`, and the project-context hook) — it must stay cheap. After saving the new entry:

```bash
grep -c '^## ' docs/SESSIONS.md
```

If there are **more than 20 entries** (or the file exceeds ~500 lines): move every entry beyond the newest 10 to `docs/SESSIONS-ARCHIVE.md` — appended under its existing dates, newest at top, content byte-identical. Create the archive with a one-line header if missing, and leave a pointer at the bottom of SESSIONS.md:

```markdown
> Older sessions: docs/SESSIONS-ARCHIVE.md (nothing is ever deleted)
```

**Never delete or summarize the moved entries** — rotation is a move, not a cleanup. History stays greppable, the live file stays readable in one breath.

## Step 4 — Prompt for related follow-ups (briefly, one line each)

If the session:
- Made a non-obvious design choice → "Consider logging an ADR with `/decision`."
- Fixed a non-obvious bug → "Add an entry to `docs/KNOWN-ISSUES.md` while it's fresh."
- Hit a milestone → "Update project status in `CLAUDE.md`."

## Output

```markdown
📝 Handoff saved: **<title>** → top of `docs/SESSIONS.md`.

👉 Next session: start fresh (your project path: `<absolute repo path>`), run `/session last`. It'll load the handoff with these queued items:
- <queued item 1>
- <queued item 2>
```

Always fill the `<absolute repo path>` slot with the real project directory (the nearest ancestor holding `CLAUDE.md` — the same root the handoff was written for), so the next session knows exactly where to `cd` before anything else. List the queued items from the handoff's "Next session should probably" section (omit the bullets if there are none).

If a follow-up is genuinely worth recommending (ADR worth logging, bug worth adding to KNOWN-ISSUES, CLAUDE.md status worth updating), add **one** suggestion line — the single most worthwhile one. Don't list all three. The user can ask "anything else?" if they want more.
