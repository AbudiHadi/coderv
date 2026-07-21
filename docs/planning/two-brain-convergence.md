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
