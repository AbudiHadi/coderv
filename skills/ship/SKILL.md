---
name: ship
description: |
  Pre-commit checklist. Reads the diff, offers to update docs itself (not just ask you), validates citations in docs haven't gone stale, drafts a why-focused commit message. Runs before every commit that touches multiple files.

  TRIGGER — suggest this skill (even without /ship prefix) when the user says: "commit", "git commit", "commit this", "push it", "push this", "push up", "create a commit", "make a commit", "ready to ship", "I'm done", "all done", "wrap up this change", "finalize", "let's commit", "commit and push", "ready to merge", "draft commit message", "write commit message".

  SKIP — when the user is only asking about git status without intent to commit (e.g. "what changed?", "show me the diff").
user-invocable: true
argument-hint: "(no args — reads git diff and staged files)"
---

# Ship — Smart Pre-commit

Goal: docs stay fresh + honest, with minimum friction.

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

### If a milestone hit

- [ ] Update `CLAUDE.md` status section if the project tracks phases there.

## Step 4.5 — Converge with Codex BEFORE the commit (the pre-commit loop)

This is where the two brains reach agreement **before** anything is committed —
so the commit lands clean on the first try. Historically the Claude↔Codex
argument happened *reactively*, after the codex-review-gate denied a commit
(Step 7). That path re-reviews a **cold diff every recommit**, so a thorough
reviewer trickles new findings one commit at a time and the loop can run for
hours (ADR-018). Moving the argument **here**, on a stable diff, before the
commit, is what ends that — the reviewer dumps **every** finding at once, you
fix the whole batch without committing, and only a converged diff proceeds.

This step runs a **loop**. Each round: (a) assemble the diff snapshot, (b) run
the fresh-context subagent audit below, (c) run one Codex pass, (d) adjudicate
the whole batch and fix/rebut **without committing**, then re-arm and repeat.
The loop reuses the loop-control already written in **Step 7** (batch-don't-
trickle + the twice-rejected-identical escalation, ADR-010) and the three end-
states in `docs/planning/two-brain-convergence.md` — it does not re-invent them.

**The diff snapshot — assemble it EXACTLY as `codex-review-gate.sh` does**, so
Codex here hashes the same bytes the gate will hash at commit time (a bare
`git diff HEAD` misses untracked files and would let /ship converge on an
incomplete diff — the gate would then find the rest cold):

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

**The Codex pass — same serialized-stdin channel the gate uses**, with the
reviewer told to be exhaustive in ONE pass (this is what stops the trickle):

```bash
OUT=$(mktemp)
SPEC=~/.claude/coderlap/specs/$(ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done; [ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd); printf '%s' "$ROOT" | tr '/' '-').md
{ printf '%s\n' \
    "You are the independent adversarial reviewer in a two-model workflow." \
    "Review this outgoing git diff for correctness, edge cases, security, data" \
    "integrity, and (if a plan is included) drift from it. Style nits do not count." \
    "Do ONE EXHAUSTIVE pass: list EVERY real finding you can see NOW, most severe" \
    "first — holding one back for a later round is a FAILURE (it wastes a converged" \
    "retry and lets real bugs hide behind cosmetic ones). file:line + the concrete" \
    "failure + the fix, per finding. If nothing significant, reply exactly: LGTM"
  [ -f "$SPEC" ] && { printf -- '--- APPROVED PLAN ---\n'; cat "$SPEC"; printf -- '--- END PLAN ---\n'; }
  printf 'Diff below:\n%s' "$DIFF"; } | timeout 180 codex exec --skip-git-repo-check -s read-only -o "$OUT" -
RC=$?
REVIEW=$(cat "$OUT"); rm -f "$OUT"
```

**Codex unavailable → FAIL OPEN, never block** (RC ≠ 0 or empty `REVIEW` after
ONE retry): surface *"Codex unavailable — diff not peer-reviewed before commit"*
verbatim, score the reviewer gate ✖ in the scorecard, and **proceed to the
approval moment** — the owner decides. Never label this CONVERGED. This is not
a coverage hole: the codex-review-gate still runs its own review at commit time.

**The end of the loop — one of exactly three states** (same set as the plan
phase and the gate; `docs/planning/two-brain-convergence.md`):

- **CONVERGED — requires BOTH** (a) the unresolved-**material** set is empty
  **AND** (b) the snapshot you just reviewed is the snapshot you are about to
  commit: `SNAP_HASH` (the diff Codex saw) **equals** a freshly re-assembled
  diff hash. A round can resolve every finding yet **change the bytes** (the fix
  itself is an edit), and that new diff is UNREVIEWED — so an empty finding set
  alone is **not** convergence. Re-assemble and re-review until the hash holds
  steady with an empty material set.
- **CAP-STOPPED** — the round cap is reached (default **3**, honouring
  `CODERV_GATE_ROUND_CAP`) and the current snapshot still cannot be certified —
  either ≥1 unresolved material finding remains, **or** the cap prevents
  re-reviewing a snapshot that just changed. The cap stops the loop **whenever it
  blocks reviewing the current diff**, not only when a finding is left open.
  Surface every open finding to the owner verbatim; they decide (fix / accept /
  park). Do **not** spend another round on your own judgment.
- **REVIEW-UNAVAILABLE** — the fail-open case above.

**The gate is still the backstop — and /ship must NOT try to shortcut it.** The
codex-review-gate runs its **own** independent review when you commit; a
converged diff just makes that a fast LGTM instead of a fresh argument. Never
write the gate's cache marker (`~/.claude/coderlap/codex-reviewed/$HASH`) from
/ship to skip that review: a marker /ship writes is indistinguishable from a
gate-written one, so any /ship failure would silently disarm the backstop, and a
plain write can race the gate's own `denied` marker (ADR-018, ADR-016). The gate
is the sole author of its trust marker. The redundant second review **is** the
safety property, not waste.

---

**The fresh-context subagent audit (run inside each loop round, above):**

The session that wrote the code cannot be trusted to grade it — accumulated
context drifts. Spawn ONE reviewer subagent with a clean context. Give it:

- the actual diff (`git diff` output, not your description of it),
- the spec checklist written by /before — the ground truth for intent. Its
  name is keyed by project root:
  ```bash
  ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
  cat ~/.claude/coderlap/specs/$(printf '%s' "$ROOT" | tr '/' '-').md
  ```
- an adversarial brief: **"Find what's wrong. For each spec item, verdict
  pass/fail with the diff lines proving it, quoted verbatim with file:line.
  Run the build and tests if the project has them; paste raw output. Flag
  anything in the diff the spec never asked for."**

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
checklist, not in `codex-review-gate.sh` — a commit made without `/ship`
skips it, which is one more reason the repo rule "never commit without
`/ship`" exists.)

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

If `NOW_HASH` ≠ `SNAP_HASH`, the bytes moved since Codex saw them — the current
diff is **unreviewed**. Re-arm: start a **new round** (re-run this whole Step
4.5 loop on the new snapshot), unless the round cap is reached — then CAP-STOP
and surface to the owner (never approve an unreviewed diff). Declare CONVERGED
**only** when `NOW_HASH == SNAP_HASH` **and** the unresolved-material set is
empty — so the scorecard, the CONVERGED verdict, and the diff the gate will
review at commit time are all the identical bytes.

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

**Default response:**

````markdown
🚢 Ready to ship — <N> files, <one-line summary>.

**VERIFICATION SCORE: <P>% (<passed>/<total> gates)**

✅ 1 Grounding receipt        → <path> (<date>)
✅ 2 Spec verified 4/4        → [say "evidence" to see per-item proof]
✅ 3 Build                    → "✓ built in 4.2s"
✖ 4 Tests                    → no test runner configured in this repo
… (all gates, one line each, pasted evidence or the reason it can't run)

Unverified claims: <0, or list them>
Judgment items for you: <none, or one line each>

**Suggested commit message:**
```
<type>: <short summary>

<2-3 sentences on WHY>
```

**On "approve" I run:** `git add <files> && git commit -m "<message>"` — the codex-review-gate reviews the outgoing diff before it lands.

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
wait for "approve". Then run the commit yourself via the Bash tool — that
routes the diff through the codex-review-gate (the machine reviewer). A
commit the user runs in their own terminal would silently bypass that gate.

**If the gate denies — it opens a discussion, not a verdict.** Codex is a
peer reviewer, not a boss; Claude holds final authority and can push back.
(With Step 4.5's pre-commit convergence done, a converged diff should reach the
gate as a fast LGTM — a deny here means the gate's independent review, its
proper backstop role, caught something Step 4.5's pass missed. Adjudicate it
the same way, in one batch; it is a rare single event now, not the loop.)

> **Converge in ONE retry — never loop.** A recommit is a *fresh* diff, so it
> earns a *fresh* review; fixing findings one-at-a-time and recommitting after
> each produces a new review every time and can deny indefinitely (this is a
> real incident, not a hypothetical — see ADR-010). So: **fix ALL real findings
> first, then retry with a single commit.** Batch, don't trickle. This is the
> commit-path twin of the design-phase round cap in
> `docs/planning/two-brain-convergence.md` — both bound the loop so it
> terminates.
>
> **Escalate — stop and surface to the owner — when the SAME unresolved finding
> has been rejected twice on substantially the same rationale.** "Substantially
> the same rationale" is narrow: the **same underlying claim**, resting on the
> **same cited evidence**, with **no materially new code or facts** bearing on
> that finding since the last rejection. If any of those three has changed (the
> claim shifted, new evidence, or the diff/facts moved), it is a *fresh*
> finding — keep going, escalation does not trip. But the same claim on the same
> evidence bouncing back twice means you are looping, not converging: stop,
> hand the owner every unresolved finding with your reasoning, and let them
> decide. The owner is the arbiter above both models; an unresolved gate is
> their call, never an excuse to keep hammering the commit.

1. Adjudicate **all** findings before committing anything. Fix every finding
   that is genuinely real, then commit the whole batch **once** — that single
   retry earns one fresh review, instead of one review per finding.
   **A finding is only rejected with parsed, machine-verified proof** — the
   actual line quoted, the actual command output — never a hunch or a lazy
   `grep` that matched the wrong thing (that once dismissed a *real* lockfile
   finding). No proof → not rejected: fix it or escalate it.
2. For a finding you believe is wrong, you may **rebut to Codex ONCE** —
   re-run the review with your counter-argument appended, same stdin channel.
   Include the approved plan when it exists, so a `[DRIFT]` finding can be
   reconsidered against the same ground truth the gate measured it against:
   ```bash
   OUT=$(mktemp)
   SPEC=~/.claude/coderlap/specs/$(printf '%s' "$ROOT" | tr '/' '-').md
   { printf '%s\n' "You flagged: <finding>." \
       "Rebuttal: <why it is not a real issue — cite the code/convention>." \
       "Reconsider. If you still disagree, say so and why."
     [ -f "$SPEC" ] && { printf -- '--- APPROVED PLAN ---\n'; cat "$SPEC"; printf -- '--- END PLAN ---\n'; }
     # Same diff assembly as the gate + Step 4.5 (untracked included) — a bare
     # `git diff HEAD` would review different bytes than the gate hashes.
     D=$(git -C "$DIR" diff HEAD 2>/dev/null); [ -z "$D" ] && D=$(git -C "$DIR" diff --cached 2>/dev/null)
     while IFS= read -r f; do [ -z "$f" ] && continue
       U=$(git -C "$DIR" diff --no-index -- /dev/null "$f" 2>/dev/null); [ -n "$U" ] && D+=$'\n'"$U"
     done < <(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null)
     printf 'Diff below:\n%s' "$D"; } \
     | timeout 180 codex exec --skip-git-repo-check -s read-only -o "$OUT" -
   VERDICT=$(cat "$OUT"); rm -f "$OUT"
   ```
   Read `$VERDICT` — Codex either concedes or holds. One rebuttal round only:
   this is a strong hand, not an argument to win. Either way, **Claude's call
   is final**.
3. Surface the outcome to the user: every finding, whether fixed / rejected /
   rebutted-and-held, with your reasoning. A rejection that survived a rebuttal
   is still surfaced — never silently dropped (transparency rule). The user is
   the final authority above both models.
4. Then retry the commit.

## Step 8 — Suggest follow-ups

Before exiting, suggest (one line each, only if applicable):

- Non-obvious design choice made? → *"Worth logging with `/decision`?"*
- Session winding down? → *"Run `/session` to leave a handoff."*
- Bug prevention rule added? → *"Consider adding a test that enforces this."*
- Stale citations flagged? → *"Run `/docify --refresh <file>` when you have 5 minutes."*
