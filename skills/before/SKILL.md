---
name: before
description: |
  Pre-code checklist that reads the relevant docs, greps prior art, checks past decisions, states a plan, and waits for approval. Runs automatically before any non-trivial code change so the dev never has to remember what to read. Skips itself for tiny / exploratory edits. This is the core discipline skill — it prevents Claude from diving in without context.

  TRIGGER — suggest this skill (even without /before prefix) when the user asks to: "add <feature>", "build <feature>", "implement <X>", "refactor <X>", "rewrite <X>", "rename <X>", "integrate <service>", "migrate <X>", "port <X>", "extract <X>", "set up <X>", "wire up <X>". Also when they say "take your time", "think about this", or touch a module for the first time this session.

  SKIP — when the user says "quick fix", "just", "small change", "tiny edit", "typo", when they're undoing something from earlier in this same session, or when the task is documentation-only.
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

If you skip, tell the user: `skipping /before — task is <reason>`, and **declare the skip to the grounding gate** so the first edit isn't blocked:

```bash
ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd)   # key by project root, same as the gate
mkdir -p ~/.claude/coderlap/receipts
printf '{"mode":"skip","reason":"<why in a few words>"}' > ~/.claude/coderlap/receipts/$(printf '%s' "$(cygpath -w "$ROOT" 2>/dev/null || printf '%s' "$ROOT")" | tr '/\\' '--' | tr -d ':')
```

Then do the task directly.

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
2. `docs/CONTEXT.md` if it exists — the project vocabulary. Use its terms in the plan, the spec, and everything you name; if the task's wording conflicts with a glossary term, surface the conflict in Step 5 instead of silently picking one.
3. `docs/MASTER.md` (or `docs/MASTER-INDEX.md`) if it exists — the docs entry-point map. `MASTER.md` orients you to the top-level docs areas; `MASTER-INDEX.md` (when present) adds a "Task → Doc Map" — find the rows that match.
4. Any docs named in that map, in order.
5. If `docs/DECISIONS.md` exists — grep it for terms related to the task. If any ADR applies, read it.
6. If `docs/KNOWN-ISSUES.md` exists — grep it. If there's a prior bug in this area, note the prevention rule.
7. If `docs/SESSIONS.md` exists — read the last entry. It may have "next session should probably…" hints or in-flight context.
8. If a `docs/ARCH-REVIEW-*.md` exists — read the newest one. Its **open P0/P1
   findings are prior art**: if the file you're about to change is named in one,
   plan around it (surface it as a "heads-up" row in Step 5), so you don't
   re-introduce or worsen a known structural problem.
9. If an **active effort map** exists (`grep -l '^Status: active' docs/PLAN-*.md`;
   several hits → list and ask which, never guess) and the task touches its
   topic — read it. Mapped decisions are prior art (they link ADRs); a task that
   contradicts one is a "heads-up" row in Step 5, and a task that resolves one
   of its open questions should say so — the map gets updated at `/ship` time
   (its Step 4 checklist carries the matching item, so the update is gated,
   not remembered).

## Step 4 — Find prior art in the code

Grep the repo for terms from the task:

```bash
grep -rn "<key term>" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" | head -20
find . -path ./node_modules -prune -o -type f -name "*<keyword>*" -print 2>/dev/null | head -10
```

If similar code exists — **read it** before writing new code. Match the existing style. Don't reinvent what already exists.

## Step 4.5 — Grill mode (opt-in, for vague or large requests)

When the request leaves **decisions** open that the plan can't be built without
— not missing *facts*, missing *choices* — offer once: *"This has a few open
decisions. Want me to grill you first — one question at a time, each with my
recommendation?"* Never auto-run it; on "no", plan under stated assumptions.

Rules of the grill (adapted from mattpocock/skills `grilling`, MIT — ADR-026):

- **Facts are never questions.** Anything the code, docs, or a read-only look
  can answer is looked up, not asked. (When `/coderv` scouted first, its
  findings are settled facts — never re-ask them.) Only genuine *decisions* go
  to the user.
- **One question per message**, hardest-dependency first, each with **your
  recommended answer** — the user says "yes" or corrects, which is cheap;
  deciding from scratch is expensive.
- **Exit** when the decisions the plan needs are answered, or the user says
  "enough" — then continue to Step 5. Each answer lands in the Step 5.5 spec
  checklist as a verifiable line, so nothing agreed in the grill gets lost.

## Step 5 — State the plan (terse by default)

**Default response — short, 3–5 lines max:**

```markdown
<One sentence: what this task is and what's already in place.>

👉 **My recommendation: <proceed | do X first | hold>.** ~<estimate>, <low/medium/high> risk.

*Want the full breakdown of what I checked, files I'll touch, and risks? Say "details".*
```

That's it. No big tables in the default response. The user usually just wants to say `go`.

**On request ("details" / "show me more" / "explain"), expand to the full breakdown:**

```markdown
**Full breakdown 🔍**

| What I checked | What I found |
|---|---|
| 📜 Rules (CLAUDE.md) | <one-line takeaway, or ✅ nothing blocks this> |
| 📚 Past decisions | <ADR-NNN title, or ✅ none apply> |
| 🐛 Known bugs in this area | <KI-NNN, or ✅ none> |
| 🔎 What's already built | <file/pattern in plain words, or ✅ fresh territory> |

**What I want to do:**
1. <step>
2. <step>
3. <step>

**Files I expect to touch:**
- `<path>` — <one-line why>

**Seam:** <the public interface this change is made and tested through — an existing one by name, or the new one being introduced and why an existing seam can't carry it>

**Heads-up:** <anything surprising, or ✅ nothing>
```

Always end with **a recommendation**, in both default and detailed form. Never ask "approve to proceed?" with no opinion.

**Prototype-first option.** When the plan hinges on an open design question — a
state model that's hard to reason about on paper, a UI direction nobody has seen
yet — the plan may include a **"prototype first"** step instead of guessing:
throwaway code that answers exactly that question. Rules: named/located so a
casual reader sees it's a prototype, one command to run, no persistence, no
polish. When the question is answered, the verdict is logged via `/decision`
and only the validated decision lands on main — the prototype itself never does.

## Step 5.5 — Write the grounding receipt + spec (to disk, before coding)

Two small files anchor everything that happens later. Write them now, while
the reading is fresh:

**1. The grounding receipt** — unlocks the grounding-gate hook for this
session, and records *what was actually read* (per ADR-004: artefacts cite
sources, not recollections):

```bash
# Key both files by the PROJECT ROOT (the dir holding CLAUDE.md) — the
# grounding-gate hook derives its key the same way, so cwd depth never matters.
ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd)
SLUG=$(printf '%s' "$(cygpath -w "$ROOT" 2>/dev/null || printf '%s' "$ROOT")" | tr '/\\' '--' | tr -d ':')
mkdir -p ~/.claude/coderlap/receipts ~/.claude/coderlap/specs
printf '{"mode":"full","task":"<task in a few words>","read":["CLAUDE.md","docs/<...>"],"prior_art":"<file:line or none>"}' \
  > ~/.claude/coderlap/receipts/$SLUG
```

**2. The spec checklist** — the request as 3–5 checkable lines. This file is
the ground truth for TWO reviewers: the `/ship` fresh-context reviewer AND the
codex-review-gate's drift-hunter. The diff is audited against *this*, never
against anyone's memory of the conversation.

**Always OVERWRITE, never append.** One spec = one task. An appended history
leaves stale baselines behind that a later review could mistake for the current
plan (a drift-hunter reading two plans hunts against the wrong one). Stamp a
`Base:` line with the current commit — the gate trusts the spec only when that
base is an ancestor of HEAD and the file is under 24h old; otherwise it falls
back to a generic review and says "drift not checked". So the stamp is what
*arms* the drift-hunter for this task:

Compute the stamp values into shell variables first, then write the body with
a QUOTED heredoc — the task/spec text is filled in by you and may contain `$(`,
backticks, or other shell metacharacters; an unquoted heredoc would execute
them. Only the two stamp lines interpolate, and they come from trusted commands:

```bash
STAMP_DATE=$(date +%F)
STAMP_BASE=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)
{ printf '# Spec — <task title>   (written by /before, %s)\n' "$STAMP_DATE"
  printf 'Base: %s\n' "$STAMP_BASE"
  cat <<'EOF'
Request: <the user's ask, one line, their words>
- [ ] <verifiable outcome 1>
- [ ] <verifiable outcome 2>
- [ ] <verifiable outcome 3>
Out of scope: <what was explicitly NOT asked>
EOF
} > ~/.claude/coderlap/specs/$SLUG.md
```

Each checklist line must be checkable against a diff ("endpoint X returns Y",
not "works well"). If the user corrects the plan in Step 6, OVERWRITE the spec
file to match — the spec always mirrors the *approved* plan, and re-stamping
(a fresh `Base:` from the current HEAD) keeps the drift-hunter armed.

## Step 5.6 — Two-brain design review (Codex peer-reviews the PLAN)

Before the plan reaches the user, the *other* AI reviews it. The gate already
does this for diffs; this does it for plans — the same independent judgment,
one phase earlier, where a wrong approach is cheapest to fix. Run this for any
task substantial enough to warrant `/before` in the first place; skip it only
when Codex is the very thing being planned in a way that would recurse.

**Feed Codex ONE serialized stdin payload — no competing sources** (identical
channel to `codex-review-gate.sh`; a heredoc is NOT used, so the instructions
and the plan can never blur together):

```bash
OUT=$(mktemp)
{ printf '%s\n' \
    "You are reviewing a PLAN written by another AI (Claude), not a diff." \
    "Findings ONLY — gaps, risks, wrong approaches, missed prior art. 2-3" \
    "bullets max. Do NOT rewrite the plan. If it is solid, reply exactly: LGTM" \
    "---PLAN BELOW---"
  cat ~/.claude/coderlap/specs/$SLUG.md
} | timeout 480 codex exec --skip-git-repo-check -s read-only -o "$OUT" -
RC=$?
REVIEW=$(cat "$OUT"); rm -f "$OUT"
```

**Adjudicate, then decide the end state** (mechanism: `docs/planning/two-brain-convergence.md`):

- **Codex unavailable** — `RC != 0` OR empty `REVIEW`: retry ONCE. Still failing
  → **REVIEW-UNAVAILABLE**. Tell the user verbatim: *"Codex unavailable — plan
  not peer-reviewed."* A timeout is **never** an LGTM. Stop the loop here.
- Otherwise adjudicate every finding: fix the real ones (re-write the spec, it
  stays the source of truth), reject the wrong ones **with a reason**. A finding
  is "material" if unaddressed it could cause a wrong result, a security/data
  problem, or unrequested scope — unsure → material.
- **A fix leaves the unresolved-material set only when VERIFIED.** In the plan
  phase a fix is usually a plan edit you can confirm on the spot. If a fix can't
  be verified until code exists, mark it UNVERIFIED-CARRIED — it stays in the
  unresolved set and rides to the diff-review (gate) phase, where the drift-
  hunter can check it. A claimed-but-unverified fix never counts toward
  CONVERGED (same rule the `/ship` scorecard enforces; convergence doc §"FIXED
  requires verification").
- **Approach changed** by a fix → re-send the updated plan (new round).
- **Converge — one of exactly three end states** (same set as the gate and the
  convergence doc; a conscious rejection is not a fourth state — it resolves
  into these two by whether the *material* set is left empty):
  - **CONVERGED** — the unresolved-material set is empty: Codex replied `LGTM`,
    OR every remaining finding was adjudicated non-material (or fixed). The only
    state that means "100% reviewed".
  - **CAP-STOPPED** — 3 rounds reached with ≥1 unresolved *material* finding
    (rejected, deferred, or unfixed).
  - **REVIEW-UNAVAILABLE** — see the unavailable case above.

**Transparency (non-negotiable):** EVERY finding from EVERY round is surfaced to
the user with its classification (material/not) and your reasoning — resolved
and unresolved alike. Classification is a recommendation, never a filter; the
user overrules any of it and is the final authority. On CAP-STOPPED or a
conscious-rejection stop, list every unresolved finding VERBATIM plus your
rationale. Never hide a finding by mislabeling it.

## Step 6 — Wait for approval

Do **not** start coding until the user confirms (or corrects) your plan. This is the whole point — catch misalignment before, not after.

Present the plan together with the Step 5.6 review outcome: the end state
(CONVERGED / CAP-STOPPED / REVIEW-UNAVAILABLE) and any unresolved findings.
The user approves, corrects, or overrules — they sit above both models.

If the user corrects the plan, update the spec and re-state it (a substantive
change re-arms Step 5.6). Don't code until aligned.

## Step 7 — Watch for follow-ups (during the task, not just after)

As you code, suggest the right next command **at the right moment**. Don't wait for the end.

- **Design choice made with trade-offs?** Say once, inline: *"This is a real trade-off between X and Y — worth logging with `/decision`?"*
- **Non-obvious bug found and fixed?** (>15 min to root-cause, or subtle cause) Say: *"Worth adding to `KNOWN-ISSUES` via `/ship`? The prevention rule would be: <draft rule>."*
- **Closes a gap** listed in `docs/*-GAPS.md`? Say: *"This closes gap #N — `/ship` will offer to mark it shipped."*
- **Session running long** (you've coded for 1+ hours without a commit or the user is pausing)? Say: *"Want me to write a `/session` handoff, or `/ship` the current state?"*

**Never auto-run skills.** Always suggest. User approves or ignores.

## Step 8 — Remind before commit

When the task is done: *"Ready to commit? Run `/ship` — it'll walk doc updates and draft a commit message."*
