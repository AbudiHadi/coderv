---
name: ship
description: |
  Pre-commit checklist. Reads the diff, offers to update docs itself (not just ask you), validates citations in docs haven't gone stale, drafts a why-focused commit message. Runs before every commit that touches multiple files.

  TRIGGER — suggest this skill (even without /ship prefix) when the user says: "commit", "git commit", "commit this", "push it", "push this", "push up", "create a commit", "make a commit", "ready to ship", "I'm done", "all done", "wrap up this change", "finalize", "let's commit", "commit and push", "ready to merge", "draft commit message", "write commit message".

  SKIP — when the user is only asking about git status without intent to commit (e.g. "what changed?", "show me the diff").
user-invocable: true
argument-hint: "(optional: --security for the deep adversarial review; default is the quality gate)"
---

# Ship — Smart Pre-commit

Goal: docs stay fresh + honest, with minimum friction.

## Flags — `--security` (ADR-022)

`/ship --security` runs the whole flow in **DEEP SECURITY REVIEW** mode: the
Step 4.5 fresh-context reviewer gets the full adversarial brief (fuzzing,
parser hardening, adversarially-crafted input) and `[hardening]` findings
block. This is the explicit opt-in for a security pass; use it when the owner
asks for one.

**Default (no flag) = engineering QUALITY GATE mode.** Realistic
correctness / regression / data-loss / reachable-security defects block as
always; exotic adversarially-crafted-input findings are tagged `[hardening]`
and land in a non-blocking **"Non-blocking debt"** section instead of
blocking — a normal dev commit converges in ONE round. Surface any debt
findings to the owner verbatim (transparency rule); they never block and never
oblige another round.

<!-- coderlap:rule:practical-impact -->
### The practical-impact rule (ADR-028)

> Ignore atomic, theoretical, defensive, or extremely low-impact findings that
> do not materially affect the user. Do not block a commit or release for
> issues that have no realistic user-facing impact, do not affect correctness
> in normal use, do not risk data loss or corruption, do not create a
> security/privacy issue, do not break compatibility, release integrity, or
> core contracts, or are only speculative hardening, cosmetic debt, comment
> wording, micro-cleanup, or unlikely edge cases.

Every finding is declared **`BLOCKER`** or **`DEBT`**:

| | Meaning | Effect |
|---|---|---|
| 🚫 **BLOCKER** | Material impact on **users, data, security/privacy, correctness, compatibility, or release integrity** — and it must NAME which one | Blocks |
| 📋 **DEBT** | Small, defensive, theoretical, cosmetic, or low-probability | Never blocks |

If the reviewer cannot identify a realistic material harm in one of those six
categories, the finding is **DEBT by construction**. When only DEBT remains the
review is **done** — report it and stop; do not go looking for smaller issues.
Practical impact is the stopping rule, not theoretical perfection.

**The label never overrides the severity.** `[debt]` on a real defect does not
demote it, and a `[blocker]` that names no category still blocks as malformed —
so the classification cannot be used to smuggle a bug past the gate, in either
direction.

## Step 1 — Look at the diff

```bash
git status
git diff --stat
git diff --stat --cached
```

Categorise changes:
- Routes (`app/api/**`, `routes/**`, `controllers/**`)
- Components (`components/**`, `src/components/**`)
- Schema (`*.prisma`, `migrations/**`, `db/**`, `schema.*`)
- Services (`lib/services/**`, `services/**`)
- Env / config (`.env.example`, `next.config.*`, `package.json` deps)
- Docs (`docs/**`, `CLAUDE.md`, `README.md`)
- Tests
- Locale / i18n

Report in 3–5 bullets.

## Step 2 — Smart doc update (NEW — the core upgrade)

Based on the categories, **offer to update docs yourself** (not just ask the user):

### If routes changed

```bash
# Find added/changed route files
git diff --name-only --diff-filter=ACM | grep -E 'app/api/.*route\.(ts|js)$|routes/.*\.(py|rb|go)$'
```

For each added/changed route:
1. Read the file.
2. Read `docs/api.md` if it exists.
3. Generate the section that should be in `docs/api.md` (method, path, auth, request, response, citation).
4. Show user a preview:

```
Route added: POST /api/partner/[id]/invite

docs/api.md doesn't mention this route. I can add this section:

  ### POST /api/partner/[id]/invite
  Auth: partner role, session.user.partnerId === id
  Request: { phoneNumber: string, role?: string }
  Response: { success: true, invitation: { ... } }
  <!-- src: app/api/partner/[id]/invite/route.ts:12-58 -->

Add it? (y/n/edit)
```

On `y` — append to the relevant section in `docs/api.md`. On `edit` — let the user refine first.

If route **changed** (not added): find its existing section by citation, show a diff of what would change.

If route **deleted**: offer to remove its section from `docs/api.md` (but keep a historical note: `<!-- removed YYYY-MM-DD: POST /api/old-endpoint -->`).

### If components changed

Similar flow: detect new components, check `docs/components.md`, offer to add a short entry (name, path, one-line purpose, props summary, citation).

### If schema changed

```bash
git diff prisma/schema.prisma 2>/dev/null
git diff --name-only | grep -E 'migrations/|schema\.'
```

Detect added/removed/changed models. Offer to update `docs/database.md` sections. Flag backfill concerns for NOT NULL columns.

### If new external dependency added

```bash
git diff package.json | grep -E '^\+' | grep -E 'stripe|twilio|openai|@100mslive|firebase|aws-sdk|...'
```

Offer to add a section to `docs/integrations.md` (what it's used for, env vars, provider docs link).

### Always

Never auto-write without approval. Always show a preview. Default to asking.

## Step 3 — Citation validator (NEW)

Walk every `docs/**.md` file. For each `<!-- src: path:start-end -->` marker found:

```bash
# For each citation "src: lib/auth.ts:42-58"
test -f "lib/auth.ts" || echo "BROKEN: file gone"
wc -l < "lib/auth.ts" # line count must be >= end
```

If the cited file is gone or the line range is out of bounds → flag:

```
Stale citations found:

  docs/api.md:87 cites lib/auth.ts:42-58 but the file is gone.
  docs/architecture.md:15 cites lib/services/video.ts:100-120 but file has 85 lines.

These docs may be lying. Want me to:
  1. Mark the affected sections with <!-- stale: verify -->
  2. Regenerate with /docify --refresh <file>
  3. Skip for now
```

Don't block commit on stale citations — warn, let user decide.

## Step 4 — Adaptive checklist (ask only what applies)

Skip items that don't apply. No bloat.

### Always

- [ ] Anything in the diff you didn't mean to include? (debug logs, commented code, unrelated files)
- [ ] Any helpers / refactors / extras the user didn't ask for? If yes, revert or justify.
- [ ] Does this commit do one thing? If bundled, suggest splitting.

### If code changed

- [ ] Run test suite (check `package.json` or equivalent).
- [ ] Run type checker / linter if configured.

### If API / public interface changed

- [ ] `docs/api.md` — covered by Step 2. Did the auto-update run?
- [ ] Breaking change? Say so in commit message.

### If design choice was made

- [ ] Worth logging with `/decision`? (Ask if it's a trade-off future-you would second-guess.)

### If non-obvious bug was fixed (>15 min to root-cause, or subtle cause)

- [ ] Add to `docs/KNOWN-ISSUES.md` with:
  - Symptom
  - Root cause (1–3 sentences, the actual mechanism)
  - Fix (file paths + line ranges)
  - **Prevention rule** — the test/type/lint/checklist item that would catch it next time

Offer to draft the entry yourself from the diff.

### If a tracked gap (`docs/*-GAPS.md`) was shipped

- [ ] Mark the relevant section: `Status: shipped YYYY-MM-DD (commit: <hash>)`
- **Never delete** the section. Preserve history.

### If the diff resolves an open question on an active effort map

- [ ] Active map naming this topic (`grep -l '^Status: active' docs/PLAN-*.md`)?
  Move the resolved question out of *Open questions*, add the ADR link to
  *Decisions so far*, and if that emptied the frontier run the map's Done
  lifecycle — per the effort-map run-book in the `coderv` skill. This is the
  `/ship`-time update `/before` Step 3 promises; without it the map's frontier
  goes stale.

### If a milestone hit

- [ ] Update `CLAUDE.md` status section if the project tracks phases there.

## Step 4.5 — Converge with the reviewer BEFORE the commit (the pre-commit loop)

This is where writer and reviewer reach agreement **before** anything is
committed — so the commit lands clean on the first try. Reviewing reactively,
after a commit, re-reviews a **cold diff every recommit**, so a thorough
reviewer trickles new findings one commit at a time and the loop can run for
hours (ADR-018). Running the argument **here**, on a stable diff, before the
commit, is what ends that — the reviewer dumps **every** finding at once, you
fix the whole batch without committing, and only a converged diff proceeds.

This step runs a **loop**. Each round: (a) assemble the diff snapshot, (b) run
the fresh-context subagent audit below, (c) adjudicate the whole batch and fix
**without committing**, then re-arm and repeat. Loop control (ADR-010, bounded
so it terminates):

- **Batch, don't trickle.** Adjudicate ALL of a round's findings before
  touching the code, then fix the real ones as one batch. Fixing one finding
  per round burns the cap on trivia.
- **A finding is only rejected with parsed, machine-verified proof** — the
  actual line quoted, the actual command output — never a hunch or a lazy
  `grep` that matched the wrong thing (that once dismissed a *real* lockfile
  finding). No proof → not rejected: fix it or surface it to the owner.
- **Escalate — stop and surface to the owner — when the SAME unresolved
  finding has been rejected twice on substantially the same rationale** (same
  claim, same cited evidence, no materially new code or facts since the last
  rejection). Two bounces means you are looping, not converging; the owner is
  the arbiter, never an excuse to keep hammering.
- **Transparency:** every finding — fixed, rejected, or open — is surfaced to
  the owner with your reasoning. Never silently dropped.

The three end-states come from `docs/planning/two-brain-convergence.md` — this
step does not re-invent them.

**The diff snapshot — assemble the COMPLETE outgoing diff** (a bare
`git diff HEAD` misses untracked files and would let /ship converge on an
incomplete diff):

```bash
DIR=$(pwd)   # or the repo you are committing in
DIFF=$(git -C "$DIR" diff HEAD 2>/dev/null)
[ -z "$DIFF" ] && DIFF=$(git -C "$DIR" diff --cached 2>/dev/null)   # unborn/all-reverted
while IFS= read -r f; do
  [ -z "$f" ] && continue
  UDIFF=$(git -C "$DIR" diff --no-index -- /dev/null "$f" 2>/dev/null)
  [ -n "$UDIFF" ] && DIFF+=$'\n'"$UDIFF"
done < <(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null)
SNAP_HASH=$(printf '%s' "$DIFF" | sha256sum | cut -d' ' -f1)   # the reviewed snapshot
```

**The review itself is the fresh-context subagent audit below** — one clean
reviewer per round, told to be exhaustive in ONE pass (this is what stops the
trickle). Its brief carries the quality-gate policy verbatim (see the audit
section); a fresh round gets a FRESH subagent — a reviewer that saw the old
snapshot is anchored to it.

**Reviewer unavailable → FAIL OPEN, never block** (the subagent fails or
returns empty after ONE retry): surface *"Reviewer unavailable — diff not
peer-reviewed before commit"* verbatim, score the reviewer gate ✖ in the
scorecard, and **proceed to the approval moment** — the owner decides. Never
label this CONVERGED.

**The end of the loop — one of exactly three states** (same set as the plan
phase; `docs/planning/two-brain-convergence.md`):

- **CONVERGED — requires BOTH** (a) the unresolved-**material** set is empty
  (ADR-022: in default mode `[hardening]`/`[edge]`/`[theoretical]` findings are
  NOT material — list them for the owner under "Non-blocking debt" and
  converge; with `--security`, `[hardening]` counts as material. ADR-028: a
  **DEBT-only** round IS convergence — do not spend another round trying to
  turn debt into something blocking)
  **AND** (b) the snapshot you just reviewed is the snapshot you are about to
  commit: `SNAP_HASH` (the diff the reviewer saw) **equals** a freshly
  re-assembled diff hash. A round can resolve every finding yet **change the
  bytes** (the fix itself is an edit), and that new diff is UNREVIEWED — so an
  empty finding set alone is **not** convergence. Re-assemble and re-review
  until the hash holds steady with an empty material set.
- **CAP-STOPPED** — the round cap is reached (default **3**, honouring
  `CODERV_GATE_ROUND_CAP`) and the current snapshot still cannot be certified —
  either ≥1 unresolved material finding remains, **or** the cap prevents
  re-reviewing a snapshot that just changed. The cap stops the loop **whenever it
  blocks reviewing the current diff**, not only when a finding is left open.
  Surface every open finding to the owner verbatim; they decide (fix / accept /
  park). Do **not** spend another round on your own judgment.
- **REVIEW-UNAVAILABLE** — the fail-open case above.

---

**The fresh-context subagent audit (run inside each loop round, above):**

The session that wrote the code cannot be trusted to grade it — accumulated
context drifts. Spawn ONE reviewer subagent with a clean context. Give it:

- the actual diff (`git diff` output, not your description of it),
- the spec checklist written by /before — the ground truth for intent. Its
  name is keyed by project root:
  ```bash
  ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
  cat ~/.claude/coderlap/specs/$(printf '%s' "$(cygpath -w "$ROOT" 2>/dev/null || printf '%s' "$ROOT")" | tr '/\\' '--' | tr -d ':').md
  ```
- an adversarial brief: **"Find what's wrong. For each spec item, verdict
  pass/fail with the diff lines proving it, quoted verbatim with file:line.
  Run the build and tests if the project has them; paste raw output. Flag
  anything in the diff the spec never asked for."**
- the **quality-gate policy**, pasted into the brief verbatim (this is what
  makes one pass exhaustive and the loop terminate): *"Review for correctness,
  edge cases, security, data integrity, and drift from the spec. Style nits do
  not count. Prioritize correctness bugs, regressions, data loss, and broken
  logic a user would actually hit; report realistic security issues (a credible
  attacker can reach the path, high impact). Do NOT recursively harden against
  exotic or adversarially-crafted input — tag such deep-hardening findings
  `[hardening]`: non-blocking debt, not grounds for another round. Declare
  EVERY finding `[blocker]` or `[debt]` — a `[blocker]` must name a material
  harm to users, data, security/privacy, correctness, compatibility, or release
  integrity; if you cannot name one, it is `[debt]` by construction. Do ONE
  EXHAUSTIVE pass: list EVERY real finding you can see NOW, most severe first —
  holding one back for a later round is a failure. If nothing significant,
  reply exactly: LGTM."* **With `--security`**, replace the do-NOT-harden
  instruction with *"Hunt exhaustively with an adversarial mindset: fuzzing,
  parser hardening, exotic shell grammar, adversarially-crafted input.
  Deep-hardening findings block in this mode."*
- the **smell baseline** below, pasted into the brief in full (the subagent has
  no other access to it): *"Also match the diff against these smells (Fowler,
  Refactoring ch.3). Each hit is a labelled judgement call — 'possible Feature
  Envy' — never a hard violation. A rule documented in the project's CLAUDE.md
  overrides the baseline; skip anything the project's tooling already enforces."*

  | Smell | What it is → how to fix |
  |---|---|
  | Mysterious Name | name doesn't reveal what it does/holds → rename; if no honest name comes, the design's murky |
  | Duplicated Code | same logic shape in 2+ hunks/files of the change → extract the shared shape |
  | Feature Envy | method reaches into another object's data more than its own → move it onto the data it envies |
  | Data Clumps | same few fields/params keep travelling together → bundle into one type |
  | Primitive Obsession | primitive standing in for a domain concept → give the concept its own small type |
  | Repeated Switches | same `switch`/`if`-cascade on the same type recurs → polymorphism, or one shared map |
  | Shotgun Surgery | one logical change forces scattered edits across many files → gather what changes together |
  | Divergent Change | one module edited for several unrelated reasons → split per reason |
  | Speculative Generality | abstraction/hooks for needs the spec doesn't have → delete; inline until a real need shows |
  | Message Chains | long `a.b().c().d()` navigation → hide the walk behind one method |
  | Middle Man | class/function that mostly delegates onward → cut it, call the target direct |
  | Refused Bequest | implementer ignores most of what it inherits → drop inheritance, compose |

  Smell hits land in the report as advisory notes for the user, **never** as
  scorecard gates — the scorecard measures the spec, the baseline improves the
  code. (The baseline is adopted from mattpocock/skills' code-review; the
  skill around it was rejected — see ADR-025 in the toolkit's
  docs/DECISIONS.md — because an unbounded second review loop is exactly what
  Step 4.5's round cap exists to prevent.)

When the reviewer returns, **machine-verify its quotes before believing it**:
each quoted line must literally exist at its cited location —

```bash
sed -n '<line>p' <file>   # must contain the quoted text
```

A quote that fails the string match = fabricated evidence → drop that finding,
note it, and re-ask the reviewer for that item. Reviewer findings that survive
become scorecard gates below.

No spec file exists (work done without /before)? Say so — the "spec verified"
gate scores ✖ and the scorecard caps below 100%.

**Architecture hot-spot check.** If a `docs/ARCH-REVIEW-*.md` exists, cross the
diff's changed files (untracked included — they commit too) against the
**newest** review's **open P0/P1** findings:

```bash
# newest by filename (ISO dates sort lexicographically) — NOT ls -t: closing
# a row edits an older file's mtime and would make it look newest
REVIEW=$(ls docs/ARCH-REVIEW-*.md 2>/dev/null | sort | tail -1)
# --name-status -M + cut/tr prints BOTH sides of a rename — a moved P0/P1
# file must still match findings citing its old path
[ -n "$REVIEW" ] && { git diff --name-status -M HEAD | cut -f2- | tr '\t' '\n'; git ls-files --others --exclude-standard; } | while read -r f; do
  # match only OPEN P0/P1 title rows (fixed/withdrawn drop), and only their
  # cited \`path:line\` field — evidence prose that merely mentions a file
  # must not trigger a false hot-spot warning
  awk '/^## P0/{on=1} !on{next} /^## P2/{exit}
    /^- / && /Status: \*\*open\*\*/' "$REVIEW" | grep -qF "\`$f:" \
    && echo "  ↑ $f has an open P0/P1 finding in $REVIEW"
done
```

Any hit → ask the reviewer one extra question: *"This file carries an open
architecture finding (`<title>`). Does this change **address** it, **worsen**
it, or leave it untouched?"* A "worsen" verdict is a scorecard gate — it caps
the score until acknowledged. Close the finding only on a **fully resolved**
verdict backed by evidence (the diff line that removes the flagged problem) —
"addressed" can mean partially mitigated, and a partial mitigation leaves the
row **open** with a progress note rather than removing a still-valid P0/P1
from every downstream check. Closing happens **after the commit lands** —
never during the ship flow (the row records the fixing commit's hash, which
doesn't exist yet, and editing now would mutate a diff the reviewer already
verified): once `git commit` succeeds, edit the row to
`Status: fixed YYYY-MM-DD (commit <hash>)` and commit that report edit as
its own docs-only follow-up. Never delete the row — same pattern as marking a
tracked gap shipped. This is how a
structural problem found once gets caught again at every commit that touches
it at every `/ship` — not left to memory. (This lives in the `/ship`
checklist and nowhere else — a commit made without `/ship` skips it, which is
one more reason the repo rule "never commit without `/ship`" exists.)

**Close the round — the snapshot-hash guard.** The audit just ran builds and
tests, which can touch tracked or generated files, and any fix you applied
edited bytes. So before you trust this round's result, **re-assemble the diff
and re-hash it**, then compare to the `SNAP_HASH` you reviewed at the top of the
round:

```bash
DIFF2=$(git -C "$DIR" diff HEAD 2>/dev/null); [ -z "$DIFF2" ] && DIFF2=$(git -C "$DIR" diff --cached 2>/dev/null)
while IFS= read -r f; do [ -z "$f" ] && continue
  U=$(git -C "$DIR" diff --no-index -- /dev/null "$f" 2>/dev/null); [ -n "$U" ] && DIFF2+=$'\n'"$U"
done < <(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null)
NOW_HASH=$(printf '%s' "$DIFF2" | sha256sum | cut -d' ' -f1)
```

If `NOW_HASH` ≠ `SNAP_HASH`, the bytes moved since the reviewer saw them — the
current diff is **unreviewed**. Re-arm: start a **new round** (re-run this
whole Step 4.5 loop on the new snapshot), unless the round cap is reached —
then CAP-STOP and surface to the owner (never approve an unreviewed diff).
Declare CONVERGED **only** when `NOW_HASH == SNAP_HASH` **and** the
unresolved-material set is empty — so the scorecard, the CONVERGED verdict,
and the diff you are about to commit are all the identical bytes.

## Step 5 — Draft the commit message

Read last 5 commits to match style:

```bash
git log -5 --pretty=format:"%s%n%b%n---"
```

Draft:

```
<type>: short summary in imperative mood

Why: <1-2 sentences — the business or technical reason>
What: <terse list if multi-file>

Closes: <issue ref if any>
```

Explain **why**, not just what. No AI attribution unless the project already uses it.

## Step 6 — Final sanity

- [ ] `git diff --cached` one last time
- [ ] No secrets / API keys / `.env` leaking
- [ ] No large binaries or generated files staged

## Step 7 — The Verification Scorecard (the approval moment)

The score is **computed, never felt**: gates passed / gates total, each gate a
pass/fail check with its real output shown. The model's job is to run checks
and show receipts — not to estimate confidence. Rules:

- **100% requires every gate ✅ with evidence attached.** A check that can't
  run (no tests configured, no spec file) scores ✖ with the reason — never
  silently dropped from the denominator, never rounded up.
- Claims quote their evidence: "committed" shows the `git log` line; "tests
  pass" shows the runner's summary line. **No pasted output → no claim.**
- Human-judgment items (a trade-off, a design choice) are listed under
  "Judgment items" — NEVER folded into the percentage.

The gates (drop only those meaningless for the project — say which and why):

| # | Gate | Evidence shown |
|---|---|---|
| 1 | Grounding receipt exists for this session | receipt path + mtime |
| 2 | Spec checklist: every item verified in the diff | per-item verdict + quoted diff line |
| 3 | Build passes | last line of build output |
| 4 | Tests pass | runner summary ("N passed, 0 failed") |
| 5 | Doc citations valid (Step 3) | "N/N checked" |
| 6 | Reviewer quotes machine-verified | "N/N string-matched" |
| 7 | Fresh-context reviewer: no open objections | reviewer's verdict line |
| 8 | Nothing unrequested in the diff | reviewer + your own check |
| 9 | No secrets / large binaries staged | check output |
| 10 | Required CI green for the pushed commit | `ci-green-check.sh` verdict line + per-job states |

**Gate 10 applies only to a commit that is already pushed** — it answers "is
what's on the remote green?", so on an unpushed commit it scores ✖ with
"not pushed yet", never ✅. Run it as:

```bash
# Installed next to this skill, under whichever host home it came from.
for H in ~/.claude ~/.codex ~/.gemini; do
  [ -x "$H/hooks/ci-green-check.sh" ] && { "$H/hooks/ci-green-check.sh" --dir "$ROOT"; break; }
done
# (in the toolkit repo itself: hooks/ci-green-check.sh --dir "$ROOT")
```

Exit `0` GREEN · `1` NOT GREEN · `2` RUNNING · `3` UNVERIFIED. **Only exit 0 is
a pass.** RUNNING and UNVERIFIED are ✖-with-reason, never rounded up and never
dropped from the denominator — "CI hasn't finished" and "CI is green" are
different facts. A repo with no `.coderv-ci.json` scores ✖ "required jobs
undeclared", which is the honest answer, not a free pass.

> **Green on one platform is not green.** Never substitute a local test run, a
> single-OS result, or `gh run watch` for this gate. `gh run watch` streams ✓
> for the one leg it follows and then exits 1; the run-level `conclusion` reads
> `success` even when a required job never ran. Only the per-job enumeration
> this gate performs distinguishes a full matrix pass from a partial one.

**Default response:**

````markdown
🚢 Ready to ship — <N> files, <one-line summary>.

**VERIFICATION SCORE: <P>% (<passed>/<total> gates)**

✅ 1 Grounding receipt        → <path> (<date>)
✅ 2 Spec verified 4/4        → [say "evidence" to see per-item proof]
✅ 3 Build                    → "✓ built in 4.2s"
✖ 4 Tests                    → no test runner configured in this repo
✖ 10 Required CI             → RUNNING — windows-latest still in progress
… (all gates, one line each, pasted evidence or the reason it can't run)

Unverified claims: <0, or list them>
Judgment items for you: <none, or one line each>

**Suggested commit message:**
```
<type>: <short summary>

<2-3 sentences on WHY>
```

**On "approve" I run:** `git add <files> && git commit -m "<message>"` — committing exactly the CONVERGED snapshot Step 4.5 certified.

👉 **My recommendation: <approve — 100% | fix gate N first | ship at <P>% because <reason>>.**
````

Below 100%, the failing gate line already says exactly what to fix — the user
should never have to ask "why not 100?".

**On request ("details" / "show checklist"), expand:**

```markdown
**Full pre-commit checklist 🚢**

| Area | Status |
|---|---|
| 📦 Files staged | <N files: one-line summary> |
| 📚 Doc updates offered | <N offered, M applied, K skipped> |
| 🔗 Doc references checked | <✅ all good | ⚠ N stale> |
| 🐛 Bug-prevention notes | <✅ logged | ✅ not needed> |
| 🔐 Secrets / large files | <✅ clean | ⚠ <list>> |
| 🧪 Tests / typecheck | <✅ passed | ⚠ skipped | ⚠ failed> |

**Open issues:**
- <blocker, or ✅ none>
```

**Never commit without the user's explicit approval.** Show the command and
wait for "approve". Then run the commit yourself via the Bash tool, and commit
**exactly the snapshot Step 4.5 certified** — if the bytes moved since (the
hash check is cheap, re-run it), that is a new, unreviewed diff: go back to
Step 4.5, never commit it on the strength of the old verdict.

## Step 8 — Suggest follow-ups

Before exiting, suggest (one line each, only if applicable):

- Non-obvious design choice made? → *"Worth logging with `/decision`?"*
- Session winding down? → *"Run `/session` to leave a handoff."*
- Bug prevention rule added? → *"Consider adding a test that enforces this."*
- Stale citations flagged? → *"Run `/docify --refresh <file>` when you have 5 minutes."*
