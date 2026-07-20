---
name: coderv
description: |
  The front door. One command for any request — "build X", "there's a bug in Y", "wrapping up", or just bare `coderv` with no words — it discovers what to do, classifies the request, checks the project's state (docs freshness, unfinished handoffs, dirty git), assembles the right pipeline of toolkit skills (/lint → /before → work → verify → /ship → /session), shows it once, and runs the whole chain on a single yes. Bare `coderv` auto-scans and proposes the most likely next task; a confusing request triggers a read-only scout to find the real target before acting; code changes are always verified (the flow is driven and observed) before shipping. The user never has to remember which skill comes next.

  TRIGGER — suggest this skill (even without /coderv prefix) when the user starts a work request without naming any skill: "I'd like to build", "I want to add", "there's a bug", "something is broken", "can we change", "let's work on", "new feature", "fix this", "improve X" — especially at the start of a session or when they ask "what's the process?" / "where do I start?".

  SKIP — when the user explicitly invoked a specific skill (/before, /ship, …), asked a pure question with no work intent, or is mid-pipeline already (a /coderv chain is running — don't nest).
user-invocable: true
argument-hint: "<what you want, in your own words — or nothing at all: bare `coderv` scans and proposes the next task>"
---

# CoderV — one command, the whole discipline

The toolkit has 7 commands; humans remember 1. `/coderv <request>` figures out
which skills the request needs, in what order, and drives them. The user is
interrupted only where human judgment is genuinely required: **approving the
plan** and **approving the scorecard**.

The bar the user sets: *"I type `coderv` and the tools start looking for
everything; if the request is confusing, they investigate and pick the right
command; and they verify the work."* Steps 0–4 below deliver exactly that —
auto-discover on a bare call, scout when confused, always verify code.

## Step 0 — Bare `coderv` (no argument): discover, don't ask

If the user typed `/coderv` with **no words**, do NOT ask "feature or bug?".
Scan the project's state first (Step 2's commands), then **propose the single
most likely next task** and get one yes. The tools look for everything; the
human just confirms.

```markdown
🔍 Scanning state…
  • Last session: <newest SESSIONS.md handoff, or "none">
  • Dirty git: <N uncommitted files, or "clean">
  • Open items: <top KNOWN-ISSUES / *-GAPS entry, or "none">
  • Docs: linted <N> days ago <✅ / ⚠ stale>

👉 **Most likely: <the one obvious next move>.**
   Proceed? (or tell me otherwise)
```

Pick the proposal by this precedence — first hit wins:
1. **Uncommitted work** in flight → propose `/ship` it.
2. **Unfinished handoff** ("next session should…") → propose resuming it.
3. **Open gap / known-issue** flagged as next → propose tackling it.
4. **Stale docs** (lint >14 days) and nothing else pending → propose `/lint`.
5. Nothing pending → ask the one-liner: "Clean slate — what are we building?"

Once the user confirms (or redirects), treat their answer as the request and
fall through to Step 1. If they gave words in the first place, skip Step 0
entirely.

## Step 1 — Classify the request

Read the argument and pick ONE shape:

| Shape | Signals | Pipeline |
|---|---|---|
| 🏗 **Feature / change** | "build", "add", "integrate", "refactor", "improve" | lint? → /before → work → **verify** → /ship |
| 🐛 **Bug** | "bug", "broken", "error", "doesn't work", "crashes" | lint? → /before (greps KNOWN-ISSUES) → fix → **verify** → /ship |
| ❓ **Question** | "how does", "why is", "what happens", "explain" | answer from docs + code — no pipeline, no edits |
| 👋 **Wrap-up** | "done", "wrapping up", "stopping", "end of day" | /session |
| 🧹 **Docs health** | "are docs fresh", "audit docs" | /lint alone |
| 🏛 **Architecture / system audit** | "review architecture", "audit the system", "check all integrations", "is anything left running", "server left alone", "tech debt", "is this well-structured", "tight coupling" | **architecture-review.md** run-book → findings + system map (all services/modules at integration granularity, gaps highlighted) → (on yes) /before → work → verify → /ship |

The 🏛 shape is driven by the `architecture-review.md` run-book beside this
file: a read-only scout, then a **parallel fan-out** over seven dimensions
(layering, coupling/cohesion, duplication, module boundaries, dead code,
**integration wiring**, **service liveness**), deduped, then **each finding is
adversarially verified by Codex** (same channel as the commit gate) before it
reaches a scored P0–P3 report. It **advises, never auto-fixes** — on one yes the
top finding hands into the normal fix pipeline above. The report is wired into
every other command (see the run-book's "the weave" table), so a finding stays
in view — `/before` reads it as prior art, `/ship` flags diffs that touch an
open P0/P1 file, `/session` surfaces open findings — until it's fixed.

**Confused which shape it is?** (vague target — "fix the slow thing", "clean up
that mess", "make it better", or a request naming nothing you can locate) do
NOT guess and do NOT just ask. **Scout first:** spawn ONE read-only subagent
(the `Explore` agent) to grep docs + code and surface the concrete candidates,
then come back and confirm the real target in one line:

```markdown
🔍 Ambiguous — scouting the codebase…
  found: <candidate A · file:line> · <candidate B · file:line>

👉 **Likely: <the best-match candidate>.** That the one? (or point me elsewhere)
```

Only after the target is concrete do you classify and continue. This is the
same "delegate heavy reading to a subagent" idiom the Question shape uses — the
tools look for everything before bothering the human.

## Step 2 — Check the project's state (commands, not memory)

```bash
ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd)
SLUG=$(printf '%s' "$ROOT" | tr '/' '-')                # project-root key, same as all coderlap artifacts
cat ~/.claude/coderlap/state/lint-$SLUG 2>/dev/null      # last /lint date, written by /lint
git status --short | head -5                              # work already in flight?
# Newest handoff — read the whole ENTRY, not just its heading, so precedence
# rule 2 can see the actual "next session should…" body (a bare heading tells
# you a session happened but not what it parked). The awk: match a DATED heading
# (`## 2026-…`) so the permanent "▶ HOW TO RESUME" preamble isn't mistaken for
# the latest entry; toggle on ``` fences so a dated heading pasted INSIDE a code
# block (a quoted git log or a rotated SESSIONS excerpt) can't be miscounted as
# the next entry; and stop at the NEXT dated heading so exactly one entry prints.
# The 300-line tail cap is only a runaway guard — it sits far past any real
# entry's "Next session should…" block, so the handoff is never truncated.
awk '/^```/{f=!f; if(s)print; next} !f&&/^## [0-9]/{n++; if(n==2)exit} n>=1{print; s=1}' \
    docs/SESSIONS.md 2>/dev/null | head -300
grep -m1 -iE 'open|todo|next' docs/KNOWN-ISSUES.md docs/*-GAPS.md 2>/dev/null  # open item to pick up?
```

(These same facts feed Step 0's bare-`coderv` proposal — one scan serves both.)

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
4. verify   — drive the changed flow, observe it actually works
5. /ship    — reviewer + scorecard — **you approve at 100%**

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
- **Always verify code before shipping.** After the build step, if the diff
  touched runnable code, verify it inline — exercise the affected flow and
  observe the behaviour — before `/ship`. A failed verify stops the chain —
  fix, then re-verify. **Skip only for a pure docs/prose diff** (nothing to
  run) — say so: "docs-only change → nothing to exercise, straight to /ship".
  **Config is NOT automatically exempt:** hook settings, manifests, CI, and
  deploy config usually have a validation path (a lint, a schema check, a dry
  run, a settings-parse) — exercise it. Only genuinely inert config with no
  runnable check (e.g. a comment-only edit) skips like docs.
- **Don't re-run what just ran.** `/lint` freshness comes from its state file;
  a `/before` receipt from this session is still valid after a lint.
- Between steps, one narrator line each: "✅ lint clean → planning next".

## Step 5 — Close

After `/ship` (or the question is answered), one line: what ran, what's left.
If the session is old or context is high, suggest `/session`. Nothing else —
the pipeline already did the talking.
