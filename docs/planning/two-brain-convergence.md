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
