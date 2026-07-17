# Plan: two-brain CoderLap workflow (v3 — after Codex rounds 1-2)

## Goal
Claude (writer/conductor) and Codex (reviewer) collaborate at BOTH design and
review phases; Claude holds final authority.

## Changes
1. /before design-phase Codex loop (new step ~5.4, before presenting to user):
   - Claude drafts the plan.
   - ONE serialized stdin payload feeds Codex — no competing sources:
       { printf '%s\n' "<instructions>" "---PLAN BELOW---"; cat "$PLANFILE"; } \
         | timeout 480 codex exec --skip-git-repo-check -s read-only -o "$OUT" -
     (identical channel to codex-review-gate.sh; heredoc NOT used.)
   - Prompt: "Reviewing a PLAN by another AI (Claude). Findings only — gaps,
     risks, wrong approaches. 2-3 bullets. Do NOT rewrite. Solid → LGTM."
   - Claude adjudicates: fix real findings, reject wrong ones with reason.
     Approach change → re-send.
   - Convergence — stop at whichever first: (a) LGTM, (b) 3 rounds, (c) all
     remaining findings consciously rejected/deferred. (b)/(c): every unresolved
     finding listed to the user VERBATIM + Claude's rationale.
   - Timeout/auth-fail (rc!=0 or empty) = NOT a verdict: retry once, then note
     "Codex unavailable — plan not peer-reviewed" to the user (fail-loud, like
     the gate). Never treat a timeout as LGTM.
2. Immutable per-task spec (fixes a latent flaw in the existing spec design too):
   - /before OVERWRITES ~/.claude/coderlap/specs/<slug>.md with THIS task's plan
     (never appends — Codex round-2 finding 2: appended history exposes stale
     baselines). Stamp a header: task title + ISO date + base commit
     (`git rev-parse HEAD`).
   - The gate reads the spec ONLY if fresh: its stamped base commit == current
     HEAD's ancestor AND mtime within 24h. Stale/mismatched/missing → fall back
     to the generic adversarial prompt and say "no approved plan on file — drift
     not checked" (never claim a plan was reviewed when it wasn't; Codex round-1
     finding 1 + round-2 finding 2).
3. Drift-hunter gate prompt (only when a fresh spec exists): prepend the plan —
   "Approved plan: <plan>. Review the diff: find where the code DEVIATED (missed
   steps, scope creep, silent changes) PLUS any correctness/security/data bug."
4. /ship deny-handling = DISCUSSION: on deny, Claude may push back to Codex ONCE
   with a rebuttal; strong hand, Claude's call final; outcome surfaced to user.
5. ADR-009 (two-brain design phase + immutable spec + drift gate); CHANGELOG
   [Unreleased]; version bump at release.

## Constraints / prior art
- ~/.codex/AGENTS.md: review-only, no docs/commits, -s read-only.
- Reuse codex-review-gate.sh stdin-pipe + project-root slug patterns exactly.
- No new user-facing commands.

## Out of scope
- Mid-implementation Codex consultation. Codex writing implementation code.
