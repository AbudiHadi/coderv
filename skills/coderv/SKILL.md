---
name: coderv
description: |
  The front door. One command for any request — "build X", "there's a bug in Y", "wrapping up" — it classifies the request, checks the project's state (docs freshness, unfinished handoffs, dirty git), assembles the right pipeline of toolkit skills (/lint → /before → work → /ship → /session), shows it once, and runs the whole chain on a single yes. The user never has to remember which skill comes next.

  TRIGGER — suggest this skill (even without /coderv prefix) when the user starts a work request without naming any skill: "I'd like to build", "I want to add", "there's a bug", "something is broken", "can we change", "let's work on", "new feature", "fix this", "improve X" — especially at the start of a session or when they ask "what's the process?" / "where do I start?".

  SKIP — when the user explicitly invoked a specific skill (/before, /ship, …), asked a pure question with no work intent, or is mid-pipeline already (a /coderv chain is running — don't nest).
user-invocable: true
argument-hint: "<what you want, in your own words — a feature, a bug, a question, or 'wrapping up'>"
---

# CoderV — one command, the whole discipline

The toolkit has 7 commands; humans remember 1. `/coderv <request>` figures out
which skills the request needs, in what order, and drives them. The user is
interrupted only where human judgment is genuinely required: **approving the
plan** and **approving the scorecard**.

## Step 1 — Classify the request

Read the argument and pick ONE shape:

| Shape | Signals | Pipeline |
|---|---|---|
| 🏗 **Feature / change** | "build", "add", "integrate", "refactor", "improve" | lint? → /before → work → /ship |
| 🐛 **Bug** | "bug", "broken", "error", "doesn't work", "crashes" | lint? → /before (greps KNOWN-ISSUES) → fix → /ship |
| ❓ **Question** | "how does", "why is", "what happens", "explain" | answer from docs + code — no pipeline, no edits |
| 👋 **Wrap-up** | "done", "wrapping up", "stopping", "end of day" | /session |
| 🧹 **Docs health** | "are docs fresh", "audit docs" | /lint alone |

No argument given? Ask one line: "What are we doing — a feature, a bug, a
question, or wrapping up?"

## Step 2 — Check the project's state (commands, not memory)

```bash
ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd)
SLUG=$(printf '%s' "$ROOT" | tr '/' '-')                # project-root key, same as all coderlap artifacts
cat ~/.claude/coderlap/state/lint-$SLUG 2>/dev/null   # last /lint date, written by /lint
git status --short | head -5                           # work already in flight?
grep -m1 '^## ' docs/SESSIONS.md 2>/dev/null           # newest handoff — unfinished business?
```

Decide the pipeline steps from facts:

- **/lint first** when the state file is missing or older than **14 days** —
  every later gate trusts the docs; verify the anchors before enforcing them.
  Skip when fresh (say so: "docs checked N days ago — skipping lint").
- **Unfinished handoff or dirty git?** Surface it before anything: "Last
  session left X in flight — continue that, or park it and start the new task?"
- **Question shape** → skip everything; answer (delegate heavy reading to a
  subagent, act on cited slices).

## Step 3 — Show the pipeline once, get one yes

```markdown
🧭 /coderv: <request in one line>

1. /lint    — docs last checked <N> days ago → refresh the anchors   (~x min)
2. /before  — read docs, plan, write spec — **you approve the plan**
3. build    — hooks guard grounding + context silently
4. /ship    — reviewer + scorecard — **you approve at 100%**

Proceed? (one yes runs the chain; you'll only be stopped at the two bold points)
```

Adapt the list to what Step 2 actually found — never show steps that will be
skipped.

## Step 4 — Drive the chain

On yes, invoke each skill in order via the Skill tool. Rules of the road:

- **Pause points are sacred.** `/before` ends waiting for plan approval;
  `/ship` ends waiting for scorecard approval. Never bridge past them.
- **A step's failure stops the chain.** `/lint` found 🔴 contradictions →
  resolve before `/before` (the plan would be built on lies). Reviewer fails
  the diff → fix and re-review before showing the scorecard.
- **Don't re-run what just ran.** `/lint` freshness comes from its state file;
  a `/before` receipt from this session is still valid after a lint.
- Between steps, one narrator line each: "✅ lint clean → planning next".

## Step 5 — Close

After `/ship` (or the question is answered), one line: what ran, what's left.
If the session is old or context is high, suggest `/session`. Nothing else —
the pipeline already did the talking.
