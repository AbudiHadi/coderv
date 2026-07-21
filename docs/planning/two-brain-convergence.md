# Convergence mechanism — FINAL (Codex rounds 1-3 all folded in)

## End states (four, mutually exclusive, all distinctly labeled)
- CONVERGED  : unresolved-material set EMPTY and every material fix VERIFIED.
              The only state that means "100%".
- CAP-STOPPED: round cap reached with >=1 unresolved material finding
              (rejected/deferred/unverified). Surfaced "stopped at cap, N
              material items open."
- REVIEW-UNAVAILABLE: Codex timed out / auth-lapsed after one retry. Plan goes
              to the user "not peer-reviewed — Codex down." NEVER labeled
              CONVERGED. (Codex round-3 finding 1.)
- (running)  : none of the above -> next round.

## FIXED requires verification (Codex round-3 finding 2)
A finding is "fixed" (and leaves the unresolved-material set) ONLY when its fix
is VERIFIED. In the plan phase, if a fix can't be verified yet, it is marked
UNVERIFIED-CARRIED and remains in the unresolved set — carried to the diff-review
(gate/ship) phase where verification is possible. A claimed fix with failed or
skipped verification stays UNRESOLVED. (Consistent with /ship's scorecard, which
already refuses to count unverified claims.)

## Loop control
Each round: run Codex, adjudicate every finding.
- Codex unavailable after 1 retry      -> REVIEW-UNAVAILABLE, exit.
- unresolved-material set empty (all VERIFIED) -> CONVERGED, exit.
- cap reached                          -> CAP-STOPPED, exit.
- else                                 -> next round.
"No new finding" alone never = convergence; only an empty verified set does.

## Termination guarantee (honest)
The CAP bounds the loop. Material set is NOT strictly shrinking. Convergence /
review-unavailable are early exits; the cap is the guarantee.

## "Material" — impact threshold, size-independent
Left unaddressed could plausibly cause: wrong result, security/data problem, or
unrequested scope. Size irrelevant. Non-material ONLY: genuine preference,
restatement, or no-impact style. Unsure -> MATERIAL.

## Full transparency
EVERY finding (all rounds, resolved+unresolved, material+non-material) surfaced
to the user with classification + reasoning. Classification is a recommendation,
never a filter. User challenges any classification, overrules any rejection, is
final authority above both models.

## Never forces agreement
Documented disagreement is legal. "100%" := empty VERIFIED unresolved-material
set — not consensus on opinions.

## Three phases, one mechanism (ADR-018)
The same convergence loop runs at three points in a task's life, with the SAME
three end-states (CONVERGED / CAP-STOPPED / REVIEW-UNAVAILABLE) and the same
"material" threshold:
1. **Plan phase** — `/before` Step 5.6 loops Claude↔Codex on the PLAN.
2. **Pre-commit phase** — `/ship` Step 4.5 loops on the DIFF, before any commit.
3. **Commit phase** — `codex-review-gate.sh` reviews the diff at commit time
   (the machine backstop; enforcement detailed below).
Phases 2 and 3 review the diff; phase 2 exists so phase 3 is a fast confirmation
of an already-agreed diff, not the place the argument happens (which — on a cold
diff re-reviewed per recommit — trickled findings and burned the owner's hours).

## Pre-commit phase (/ship Step 4.5), 2026-07-21
Invariants that make phase 2 safe and honest:
- **Same diff bytes as the gate.** /ship assembles the diff EXACTLY as
  `codex-review-gate.sh` does (`git diff HEAD`, `--cached` fallback, plus
  untracked via `git diff --no-index`), so the bytes Codex reviews are the bytes
  the gate will hash. A bare `git diff HEAD` (untracked omitted) would let /ship
  converge on an incomplete diff and the gate would find the rest cold.
- **Numeric round cap** (default 3, `CODERV_GATE_ROUND_CAP`) bounds the loop —
  the twice-rejected-identical early-exit sits on top of it, not instead of it
  (new findings each round never trip the identical rule; the cap is the real
  bound). "The CAP bounds the loop" — same guarantee as the plan phase.
- **CONVERGED requires BOTH** an empty unresolved-material set AND
  reviewed-snapshot-hash == current-diff-hash. A round can resolve every finding
  yet change the bytes (the fix is an edit); that current diff is UNREVIEWED, so
  an empty finding set alone is not convergence. If the cap prevents re-reviewing
  a changed snapshot → CAP-STOPPED (the cap stops the loop whenever it blocks
  reviewing the CURRENT diff, not only when a finding is left open).
- **Fail-open.** Codex unavailable in /ship never blocks the commit — surface
  loudly, score the gate unmet, proceed; the owner decides. The gate still
  reviews at commit time, so this is not a coverage hole.
- **The gate is the sole author of its trust marker.** /ship NEVER writes
  `~/.claude/coderlap/codex-reviewed/$HASH`. A /ship-written `lgtm` is
  indistinguishable from a gate-written one, so it would silently disarm the
  backstop on any /ship failure and could race the gate's monotonic `denied`
  marker. The redundant commit-time review IS the safety property (ADR-018).

## Commit-phase enforcement (codex-review-gate.sh, 2026-07-20)
The cap is enforced BY THE MACHINE at the commit gate, not by prose:
- The reviewer must impact-tag every finding. MATERIAL = [data-loss] |
  [security] | [correctness] | untagged/unparsed. MARGINAL = [edge] |
  [theoretical].
- Round counter per (canonical repo, HEAD): flock-atomic read+append, no
  delete path (HEAD movement + the 24h sweep reset it). Default cap 3,
  override CODERV_GATE_ROUND_CAP.
- round >= cap AND >=1 material open -> DENY = THIS DOC's CAP-STOPPED end
  state: the loop is over, the owner decides. An identical-diff retry stays
  DENIED until the owner asserts the explicit in-band override
  (CODERV_GATE_OWNER_OVERRIDE=1 on the retried commit), which passes WITH a
  loud caveat — the override is the owner's decision signal, never the
  agent's, and it keeps the gate from ever hard-locking the owner out.
- round >= cap AND all findings marginal -> ALLOW with a loud caveat, the
  findings surfaced to the owner verbatim. This is a commit-phase refinement,
  NOT auto-CONVERGED: adjudication of the marginal residue passes to the
  owner instead of holding the commit hostage.

## Why the loop bled tokens, and the permanent fix (ADR-019, 2026-07-21)
The gate's cold-diff review is MEMORYLESS: each `codex exec` is a fresh session
that sees only the diff, with no record of what it already raised and no access
to the surrounding code. So a thorough reviewer (a) re-raises a finding Claude
already resolved, because it never learns the disposition, and (b) invents false
findings the real code disproves, because it can't read that code. Every such
finding is a new deny -> another round -> the owner ends the loop by hand. The
old cap only ESCALATED-TO-HUMAN, which made the human the loop's off-switch on
every project — that is the bleed. ADR-019 makes GENUINE CONVERGENCE (Codex LGTM
because it finally has full context) reachable, so escalate-to-human is reserved
ONLY for a real unmitigated [security]/[data-loss] finding at the hard ceiling.

Four inputs, added at the commit gate (and inherited by /ship Step 4.5 and
/before Step 5.6 — DRY, defined here once):

1. **Findings ledger (memory).** A per-(canonical repo, HEAD) ledger file sits
   beside ROUNDS_FILE in `$CACHE` (`ledger-<sha of CANON_REPO@BASE>`), same
   lifecycle: flock-guarded append, no delete path, reaped by the 24h sweep and
   by HEAD movement. Each reviewed finding is fingerprinted (a hash of its
   normalized text — lowercased, whitespace/line-number-stripped) and recorded.
   The accumulated fingerprints + their finding text are fed into the next
   round's prompt with an explicit instruction: *you already raised these; do
   NOT raise one again unless the CURRENT code still exhibits it — cite the line
   that still shows the problem.* This is what stops re-raising resolved
   findings. The ledger is best-effort: a flock/IO failure just means an empty
   prior-findings block (the pre-ADR-019 behavior), never a block on the commit.

2. **Project context (read the real code).** The `codex exec` runs with the repo
   as its cwd (`cd "$DIR"`) under `-s read-only`, is given the list of changed
   files, and is told to READ the surrounding code before judging — so a finding
   the code already disproves is never raised. The owner APPROVED sending
   surrounding project files to OpenAI (same trust boundary as the diff, just
   wider). This kills false findings at the source.

3. **Convergence pressure.** A finding first appearing at round >= 2 (visible in
   the ledger as absent from all prior rounds) is tagged [LATE] by the reviewer
   and must justify why it could not have been seen at round 1. The prompt
   carries an explicit definition: *converged = you reply LGTM because, with the
   prior findings and the real code in front of you, nothing material remains* —
   NOT "no NEW finding this round."

4. **Ceiling (a rarely-hit safety net, not the normal exit).** Above the
   existing soft cap (`CODERV_GATE_ROUND_CAP`, default 3) sits a hard
   `CODERV_GATE_ROUND_MAX` (default 5) and a `CODERV_GATE_DIFF_BUDGET` (a
   cumulative bytes-reviewed proxy, default 800000). If fixes 1-3 work the loop
   converges around round 2-3 and the ceiling is never reached. At the ceiling,
   ONLY a still-open [security] or [data-loss] finding may BLOCK — and that block
   is the existing owner-escalation path (CODERV_GATE_OWNER_OVERRIDE=1), i.e. the
   gate refusing to auto-merge a security hole, which is a safety decision, NOT a
   human being asked to adjudicate ordinary code. Every non-security finding must
   have converged by the ceiling; if any [correctness]/untagged remains open at
   ROUND_MAX it is surfaced but the commit is ALLOWED-with-caveat (the loop
   self-terminates rather than escalating routine code to the human).

Invariants preserved (non-negotiable): fail-open when Codex is down (allow with a
loud unreviewed warning); the kill switches (CODERV_GATES_OFF / CODEX_REVIEW_OFF)
and the CODERV_LOG_OFF contract untouched; the gate stays the sole author of its
trust marker (ADR-018). ADR-019 only ADDS context to the review and RAISES the
ceiling above the cap — it never weakens a material block below the cap.

**"Built" is not "live."** The fix reaches a project only after that project's
user `git pull`s the toolkit and re-runs `install.sh` (which re-copies the hook).
Until a reinstall, their deployed gate keeps the old trickle. The CHANGELOG/README
must say so.
