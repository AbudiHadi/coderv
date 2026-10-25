# /ship — Step 4.5 — Converge with the reviewer BEFORE the commit (the pre-commit loop)

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

