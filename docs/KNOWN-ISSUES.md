# Known Issues & Recurring Bugs — toolkit

> Recurring issues with skills, installer, or templates.
> Each fixed non-obvious bug gets an entry with a **prevention rule**.

---

## Template

```
## KI-NNN: <Symptom>

**First seen:** YYYY-MM-DD
**Last seen:** YYYY-MM-DD
**Status:** open | fixed in commit <hash>

### Symptom
What the user sees.

### Root cause
The actual bug.

### Fix
What was changed.

### Prevention
Rule / test / check that would catch this next time.

### Related
- ADR-NNN / KI-NNN
```

---

## KI-004: the gate's security-severity policy made exotic findings block like real bugs — the round-8/9 lexer trickle

**First seen:** 2026-07-22
**Last seen:** 2026-07-22
**Status:** CLOSED 2026-07-23 by ADR-022 (the [hardening]/Optional policy split)

### Symptom
Fixing the 0.13.1 review-target hijack spiralled into 8+ review rounds, each
surfacing one more real-but-exotic shell-grammar corner (heredoc delimiter
quoting, `$'...'` ANSI-C escapes, mid-word `#`, backtick segments, …). Every
finding was tagged `[security]`, `[security]` can never be marginal, so each
blocked the commit — the gate behaved like a penetration tester on every
commit and the loop could not converge (trajectory `1->2->1->1->1->1->1->1`).

### Root cause
A SEVERITY-POLICY bug, not a lexer bug. The severity contract had no class for
"security-relevant weakness with NO credible reachable high-impact path", so
defense-in-depth gaps against adversarially-crafted pathological input (whose
only 'attacker' is someone defeating a local guardrail in their own commit
message) carried the same blocking weight as a reachable auth bypass. The
surface of such exotica is infinite, so blocking on it can never converge —
perfecting the lexer round-by-round (round 9, 213/213 checks) and relocating
target resolution (cwd-only) were both tried and both just moved the trickle.

### Fix
ADR-022: the `[hardening]` marginal tag + the quality-gate default mode.
Exotic no-reachable-impact findings route to a non-blocking "Optional Security
Review" section and the commit allows in round 1; realistic-impact findings
still block; `CODERV_GATE_SECURITY=1` (`/ship --security`) is the explicit
deep-review opt-in where `[hardening]` blocks again. The round-9 lexer stays
in-tree and active — it was correct work, it just no longer holds commits
hostage.

### Prevention
Severity is classified by REACHABILITY + IMPACT, never craftedness or rarity
(the governing rule is stated in the reviewer prompt and enforced by tests
T65–T71). Any future "the gate keeps finding one more exotic corner" loop is
a policy smell, not a fix-it-again task: check the finding's reachable impact
before spending a round.

### Related
- ADR-022 (the fix), ADR-019 (the convergence machinery this rides on),
  KI-002/KI-003 (sibling loop-class issues)

---

## KI-003: /ship Step 4.5 + /before Step 5.6 convergence loops have a PROSE-only cap

**First seen:** 2026-07-22
**Last seen:** 2026-07-22
**Status:** open — real fix needs its own /before (a design change, not a drive-by)

### Symptom
ADR-019 claims `/ship` Step 4.5 and `/before` Step 5.6 "inherit" the gate's
ledger + round counter + cap. They don't: both SKILL.md convergence loops call
`codex exec` with no machine round counter and no ledger — their "cap of 3" is
prose an agent is merely asked to obey.

### Root cause
The anti-loop machinery (rounds file, ledger, cap/ceiling enforcement) is
implemented only inside `hooks/codex-review-gate.sh`. The skills describe the
same discipline in words but share none of the state files, so nothing
machine-stops a pre-commit loop that keeps finding one-more-thing. This is the
same failure class as KI-002: a capable agent + a prose cap loses to the pull
of "one more round". The commit-time gate still bounds the damage (the diff
cannot land unreviewed), but nothing bounds the pre-commit token burn.

### Fix
Not yet applied. The real fix — wiring both skills to the gate's rounds/ledger
files so skill-phase rounds are counted by the same machine state — is a design
change worth its own `/before` session.

### Prevention
Until wired: treat the skills' round caps as hard personal limits (count rounds
explicitly in the transcript, stop at 3). Mechanical-over-descriptive: any new
convergence loop added anywhere must point at a machine counter, never a prose
cap alone.

### Related
- KI-002 (same failure class, hand-run loop), ADR-021, ADR-019 (the machinery the skills don't actually share)

---

## KI-002: hand-run `codex exec` reproduces the uncapped review loop the gate exists to prevent

**First seen:** 2026-07-22
**Last seen:** 2026-07-22
**Status:** fixed by ADR-021 (rule + Codex self-refusal); machine-lock deferred

### Symptom
On alrafiq's career-floor regex, the Claude↔Codex review looped past the round
cap: R1 → fix → R2 finds a new hole → fix → R3 → R4 → about to write R5. Each
round found a *genuinely different, real* flaw (guarantee slip → false positive
→ sentence-exemption bypass → greedy-mask bypass → arbitrary-filler bypass), so
it *looked* like healthy convergence progress — but it never terminated on its
own. It felt like "the ADR-019 fixes aren't working."

### Root cause
The ADR-019 anti-loop machinery (findings ledger, project context, round
counter, cap, ceiling) all lives **inside `codex-review-gate.sh`** and only
governs rounds that pass **through** the gate. The rounds here were hand-driven
`codex exec` calls made *outside* the gate — so no ledger (each round rediscovers
the space cold, unaware of prior findings), no counter increment (the gate log
shows only `"round":1` for the whole episode), and no cap/ceiling (nothing to
stop it). It is the pre-ADR-019 memoryless trickle reproduced by hand. The
context+ledger fixes make each round *smarter*; they never make rounds *stop* —
only the CAP does, and the cap was bypassed. A per-round real finding is normal
for a legitimately fragile design (a masking regex over natural-language
negation); expecting a "perfect" first review to end the loop is the trap.

### Fix
ADR-021: the gate is the ONLY sanctioned diff-review loop. `two-brain-convergence.md`
gains a top "THE ONE RULE THAT MAKES THE CAP REAL" section banning hand-run
`codex exec` on a diff; `~/.codex/AGENTS.md` + `templates/codex-AGENTS.md` gain a
"gate is the only sanctioned review loop" bullet so Codex, if hand-invoked to
"do one more round," points back to the gate instead of looping. Sanctioned
`codex exec` sites inside `/ship` Step 4.5 and the commit hook are unchanged.

### Prevention
Never run `codex exec` by hand to adjudicate a diff, "confirm convergence," or do
"one more round" — route every diff review through `/ship` (or the commit gate),
which arms the counter + cap. If you catch yourself typing `codex exec` on a
diff, STOP and run `/ship`. A machine-lock (a `codex exec` wrapper that refuses
outside an in-gate sentinel) is the deferred hard-enforcement option in ADR-021
if the rule alone proves insufficient.

### Related
- ADR-021 (the ban), ADR-020 (rejected: do NOT downgrade a pre-ceiling deny to ask), ADR-019 (the in-gate machinery that only counts gate rounds), ADR-018

## KI-001: drift-hunter note sits downstream of the review cache

**First seen:** 2026-07-17
**Last seen:** 2026-07-17
**Status:** open (follow-up; not a release blocker per owner)

### Symptom
The drift-status decision (fresh-spec drift-hunt vs. generic "drift NOT checked")
is computed *after* the 24h review cache check in `codex-review-gate.sh`. If an
identical diff (same repo + HEAD + diff bytes) is first reviewed in one drift
state and then re-run in a different drift state — e.g. reviewed with no fresh
spec, then a fresh spec appears without the diff changing — the cached verdict
is reused and the drift status does not refresh for that diff.

### Root cause
The cache key is `sha256(repo + HEAD + diff)` and the cache short-circuits with
`exit 0` before the drift/spec-freshness block runs. Spec freshness is not part
of the key, so a spec-state change on an unchanged diff is invisible to the cache.

### Fix
None yet — recorded as a follow-up. In normal use `/before` writes the spec
*before* any diff exists, so the drift state is stable across a task and the
window can't occur; this is the same post-cache placement class as `HIST_NOTE`
and `TRUNC_NOTE`. When addressed, the fix is to fold a spec-freshness marker
(e.g. the fresh spec's `Base:` + mtime, or "no-fresh-spec") into the cache key.

### Prevention
If the cache key ever needs to reflect review *mode* (not just diff bytes),
add the mode to the hash — a stubbed-codex test that runs the same diff twice
under different spec states and asserts the second run re-reviews would catch a
regression.

### Related
- ADR-009 (the drift-hunter this concerns)

<!-- New entries above this line, newest first -->
