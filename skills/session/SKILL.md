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

**Then offer the system map if an audit is waiting to be drawn.** A resume is
exactly when an audit from a *previous* session gets picked up — and the map
offer must not be lost across that boundary. After returning the handoff, check
for the newest architecture review and whether its map was ever drawn:

```bash
REVIEW=$(ls docs/ARCH-REVIEW-*.md 2>/dev/null | sort | tail -1)   # newest by filename
if [ -n "$REVIEW" ]; then
  # open P0/P1 present?  (title rows still marked open in the P0/P1 sections)
  # Scan the P0 AND P1 sections (a report with zero P0 findings OMITS the `## P0`
  # header, so anchoring on P0 alone would miss every P1-only report). Turn ON at
  # either header; turn OFF at any other `## ` section (P2/P3 or a named section).
  OPEN=$(awk '/^## P0/||/^## P1/{on=1; next} /^## /{on=0} on && /^- / && /Status: \*\*open\*\*/' "$REVIEW")
  # map already drawn?  ABSENT marker == not drawn (legacy reports have no line)
  grep -q '^<!-- Map: drawn ' "$REVIEW" 2>/dev/null || grep -q '^Map: drawn ' "$REVIEW" 2>/dev/null
  DRAWN=$?   # 0 = drawn, 1 = not drawn
fi
```

If `$REVIEW` exists, has open findings, and is **not** drawn (`DRAWN` ≠ 0 / no
`Map: drawn` line), OFFER the interactive map with the run-book's exact wording:
*"This project has an open architecture review whose interactive map hasn't been
drawn yet. Want the full interactive system map — draw.io-style pan/zoom canvas,
🟢/🌐/⏸ node markers + 🔴 P0-P1 / 🟡 P2-P3 gap markers, click-to-trace? [y/N]"*.
On **yes**, render it (per `architecture-review.md`'s canvas standard) and stamp
the review `Map: drawn <date>`. Offer, never auto-draw.

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

**Open architecture findings (if any):**
- <paste open P0/P1 rows from the newest `docs/ARCH-REVIEW-*.md`, or "none">
  <!-- so a structural problem found by an audit doesn't rot between sessions -->

**Next session should probably:**
- <suggested next step>

---
````

If a `docs/ARCH-REVIEW-*.md` exists, pull its open P0/P1 findings into the block
above so they stay visible across sessions:

```bash
# newest review only; P0+P1 sections; whole finding blocks (title + evidence
# lines) are kept or dropped together — only rows explicitly marked open
# survive (fixed, withdrawn, or any future closed status all drop)
REVIEW=$(ls docs/ARCH-REVIEW-*.md 2>/dev/null | sort | tail -1)  # newest by filename, not mtime
[ -n "$REVIEW" ] && awk '/^## P0/{on=1} !on{next} /^## P2/{exit}
  /^## P[01]/{print; next} /^- /{keep=($0 ~ /Status: \*\*open\*\*/)} keep' "$REVIEW"
# no head-cap: open P0/P1 must ALL surface — truncating mid-block would hide
# findings, and a long list is itself the signal the handoff needs to carry
```

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
