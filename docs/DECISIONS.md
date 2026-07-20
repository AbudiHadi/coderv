# Decision Log (ADRs)

> Toolkit-level architectural choices. Run `/decision <title>` to add a new ADR.
> Newest at top. **Never delete.**

---

## Template

```
## ADR-NNN: <Short title>

**Date:** YYYY-MM-DD
**Status:** accepted | superseded by ADR-MMM | deprecated
**Decider(s):** <name(s)>

### Context
What is the problem? What forces are at play?

### Decision
What did we decide?

### Alternatives considered
- **Option A** (chosen) — why
- **Option B** — why not
- **Option C** — why not

### Consequences
- Positive: …
- Negative / trade-off: …
- Revisit if: …
```

---

## ADR-015: The interactive system map is rendered by a forced mechanical procedure, not described as a design goal

**Date:** 2026-07-20
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

Follows ADR-014 (the 🏛 audit shape) — this hardens *how* that shape's system map gets drawn.

### Context
The audit ships a frozen HTML canvas (`skills/coderv/systemmap.template.html`) so every project's map looks and behaves identically (draw.io-style pan/zoom, click-to-trace, textContent injection-safety). But in a live Al-Rafiq session an agent, asked to "draw the map," treated it as a generic design task: it loaded the `artifact-design` skill (which actively invites bespoke palette/type/layout), hand-authored a completely custom HTML page, and never opened the run-book or the template — producing a cramped side-scroll strip with none of the frozen engine's guarantees. Root cause: the run-book *described the template's qualities* ("dark theme, severity colours, a flow of boxes") instead of *commanding the mechanical steps*, and the three render triggers (`/coderv` Step 0, `/session last` resume, the run-book's own Canvas standard) were soft one-file-hop pointers — nothing forced the template to be read before rendering. "Use the frozen engine" was advisory; the pull of a generic design skill won. This is the same disease as the resume-gap fix (offer anchored to the wrong event), one layer deeper: a capable agent builds an impressive lookalike that superficially matches and silently skips the guarantees.

### Decision
Make drawing the map an unambiguous mechanical procedure that FORBIDS hand-authoring, inlined at **all three** trigger sites (no more one-file-hop pointer). Every site now states the literal steps — (1) copy `systemmap.template.html` to scratch, (2) replace **only** the `GRAPH = {…}` block, (3) publish that file — plus an explicit prohibition: do **not** hand-author HTML/CSS/SVG and do **not** load `artifact-design` (or any bespoke-design skill) for the map; "if you are writing a `<style>` block or drawing SVG, STOP — you are doing it wrong." The run-book adds a **pre-publish self-check** keyed to an *immutable template fingerprint* — `grep -q 'FROZEN TEMPLATE' && grep -q 'const GRAPH = {'` — not weak engine strings (`elementFromPoint`, "Fit") a lookalike could coincidentally contain; if the fingerprint is absent the agent authored a bespoke page and must redo from step 1.

### Alternatives considered
- **Forced mechanical steps + fingerprint self-check** (chosen) — turns "use the template" from advice into a procedure with a machine-checkable gate; catches the exact failure mode observed.
- **Keep the descriptive Canvas standard, just make the pointer louder** — rejected: the failure proves description loses to a capable agent + a generic design skill's pull; louder prose is still prose.
- **A `PreToolUse(Artifact)` hook that blocks publishing a non-template arch-map** — considered, deferred: a real belt-and-suspenders option, but it needs a reliable way to tell an arch-map Artifact from any other and lives in harness config, not the run-book; the inlined mandate + self-check covers the observed case now. Revisit if a lookalike still slips through.

### Consequences
- Positive: identical, guaranteed-correct maps across every project; the fingerprint self-check rejects a bespoke lookalike before it publishes; the mandate is self-contained at each trigger, so an agent never has to open a second file to know the rule.
- Negative / trade-off: the self-check is a convention the agent runs, not a runtime-enforced gate (no hook yet) — a determined agent could still skip it; the fingerprint depends on the `FROZEN TEMPLATE` banner staying in the template (a comment strip would silently disarm it).
- Revisit if: a hand-authored map slips through again despite the mandate — then the deferred `PreToolUse(Artifact)` hook earns its place.

---

## ADR-014: The architecture & integration audit is a `/coderv` shape woven through all seven commands — not an eighth command

**Date:** 2026-07-19
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

Extends ADR-007 (the /coderv router) and ADR-013 (the shape-classifier). The 7-command surface is unchanged.

### Context
The owner asked for a whole-project capability: audit the code's architecture (layering, coupling, cohesion, duplication, boundaries, dead code), audit how everything *integrates* (every API/DB/`proxy_pass`/env target points at something live), and detect *"a server left alone"* (orphaned PM2 apps, retired-but-routed ports, dead nginx sites) — the exact hazards the owner's global CLAUDE.md + SERVER-MAP.md discipline exists to prevent. The explicit ask: *"integrate it with ALL coderv commands, nothing left, everything connects in a smart way,"* plus a high-quality workflow drawing. The forces: (1) CLAUDE.md's `never-unrequested` rule caps the surface at 7 commands and sets a bar for slot 8 — it must *reduce* what the human holds in their head, not add to it; (2) the toolkit's grain is find→adversarially-verify with Codex, not first-draft opinion; (3) a report read once and forgotten changes nothing — the error-reduction has to come from the *weave*, not the audit alone.

### Decision
Add the audit as a new **🏛 Architecture / system audit** shape in `/coderv`'s Step 1 classifier, driven by a new `skills/coderv/architecture-review.md` run-book (scout → 7-dimension parallel fan-out → dedup → Codex adversarial verify each finding → scored P0–P3 report). It **advises, never auto-fixes**; on one yes the top finding hands into the normal fix pipeline. The report is then wired into every other command so a finding stays in view until fixed: `/before` reads it as prior art, `/ship` flags diffs touching an open P0/P1 file (in the harness, at commit time), `/session` surfaces open findings, `/lint` flags a stale review, `/docify` links it, `/decision` fires when a structural finding is acted on. Codex is invoked through the **exact serialized-stdin channel** `codex-review-gate.sh` uses (DRY with the two-brain seam). A high-quality rendered workflow Artifact + a versioned Mermaid diagram in the run-book document the flow.

### Alternatives considered
- **A `/coderv` shape woven through all commands** (chosen) — honors the 7-cap (no new slot), and *is* the "integrate with all commands" the owner asked for. The weave — not the audit — is where the error-reduction lives.
- **A standalone `/audit-arch` slot-8 command** — rejected: it breaks the 7-cap and fails the slot-8 bar (a periodic health investigation doesn't reduce daily mental load enough to earn permanent real estate). It also reads the owner's "integrate with all commands" ask more weakly than a native shape does.
- **Fold it into `/ship`'s reviewer** — rejected: SR violation. `/ship` reviews a *diff*; a whole-codebase audit is a different altitude and would slow every commit.

### Consequences
- Positive: no surface growth; the audit's findings keep reducing errors long after it runs, because five other commands hold them in view; Codex verification keeps the advice honest (refuted findings are dropped but footnoted, never silently).
- Negative / trade-off: the coupling/cohesion scoring is a heuristic, not a measurement — real judgment stays with the owner; the integration + liveness dimensions need live-service context (SERVER-MAP.md / `ss` / `pm2`) and degrade to a code-only audit that explicitly states it did NOT check liveness when that context is absent (same honesty rule as the gate's "drift NOT checked").
- Revisit if: the shape proves heavy enough in daily use that a dedicated command would genuinely reduce mental load — then it goes through the slot-8 bar separately.

---

## ADR-013: `/coderv` acts before it asks — bare-scan-propose, scout-when-confused, always-verify

**Date:** 2026-07-19
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude, Codex (adversarial review — 6 findings fixed pre-merge)

Extends ADR-007 (the /coderv router); the 7-command surface and the router's role are unchanged.

### Context
ADR-007 shipped /coderv as a router that classifies a *stated* request and drives the pipeline. Real use exposed two friction points where it still pushed work back onto the human, plus a safety gap. (1) A bare `/coderv` with no words answered with a question — "feature, bug, or wrap-up?" — when the project state (dirty git, an unfinished handoff, an open gap) usually already implies the one obvious next move. (2) A vague request ("fix the slow thing", "clean up that mess") made the router either guess a target or bounce the question back, when the codebase itself holds the answer. (3) The pipeline shipped code straight from build to /ship with no step that actually *ran* the change — the reviewer reads the diff, but nobody drives the flow. The owner's framing: *"I type coderv and the tools start looking for everything; if the request is confusing, they investigate and pick the right command; and they verify the work."*

### Decision
Add three behaviours to the /coderv skill (no new command):
- **Step 0 — bare-scan-propose.** `/coderv` with no argument scans state (lint freshness, dirty git, newest *dated* SESSIONS entry read in full, open gaps/known-issues) and proposes the single most likely next task by a fixed precedence (uncommitted > unfinished handoff > open gap > stale docs > clean slate), then takes one yes. It does not interrogate.
- **Step 1 — scout-when-confused.** A vague target spawns ONE read-only `Explore` subagent to surface concrete candidates (file:line) before classifying — the same "delegate heavy reading to a subagent" idiom the Question shape already uses — then confirms the real target in one line.
- **Steps 3–4 — always-verify.** On a code change the pipeline runs an inline verify step (drive the affected flow, observe behaviour) between build and /ship. Worded as plain *verify*, deliberately **not** a `/verify` skill invocation, because the toolkit ships no such skill — a skill reference would dangle on a clean install. Config is not auto-exempt from verify (hooks/CI/manifests usually have a validation path); only pure docs/prose diffs skip.

### Alternatives considered
- **Fold the three behaviours into /coderv** (chosen) — keeps the surface at 7 commands (ADR-007's bar: slot N must *reduce* what the human holds in their head), and each behaviour removes a prompt the human previously had to answer.
- **Author a real `/verify` skill as slot 8** — rejected here: it would grow the command surface, and the built-in per-project /verify already covers driving the flow. If a toolkit-owned verify ever earns its own slot it goes through the ADR-005/007 slot bar separately.
- **Make bare `/coderv` just ask the one-line menu** — the status quo; rejected because the state scan almost always already implies the answer, and asking when you could propose is the friction ADR-007 set out to remove.

### Consequences
- Positive: the human types `coderv` (or nothing after it) and gets a concrete proposal or a scouted target, not a questionnaire; code no longer reaches /ship unexercised.
- Negative / trade-off: Step 0's proposal can be wrong when state is ambiguous (mitigated — it's always a one-yes proposal the user can redirect); the verify step adds a beat to the pipeline on code changes (intended — it's the point).
- Revisit if: bare-scan mis-proposes often (tighten the precedence list) or the scout subagent proves overkill for the vague-request rate on this machine.

Note: this ADR was itself hardened by the codex-review-gate during /ship — the gate caught six real defects in the implementation before it merged (a dangling `/verify` skill reference, an over-broad config-skip, and four bugs in the handoff-scan command: heading-only grep, non-fence-aware parsing, a truncating output cap, plus jq leading-zero and endpoint-false-match bugs in the companion gate change). Recorded as live evidence that the adversarial reviewer (ADR-008) earns its latency.

---

## ADR-012: The context-gate triggers on an absolute token budget, not a percentage of the model's window

**Date:** 2026-07-19
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude, Codex (adversarial review)

Refines ADR-006 (the context-gate's trigger mechanism only; the three-gate design stands).

### Context
ADR-006 shipped the context-gate with a **percentage-of-window** trigger: `pct = 100 * ctx / CODERV_CONTEXT_WINDOW`, warn at 60%, block at 75%, with `CODERV_CONTEXT_WINDOW` defaulting to 200000. That default was correct when 200k was the standard Claude Code window. On Claude Opus 4.8 the standard window is **1,000,000 tokens** — so the gate divided real usage by the wrong denominator and reported ~5× too high (140k of context read as "70%" against a 200k budget, when it is only ~14% of the real 1M window). The naive "fix" — set `CODERV_CONTEXT_WINDOW=1000000` — is worse: it would move the hard block to 750k, deep into the degradation zone, because it assumes quality survives to 75% of *whatever the server will admit*. ADR-006 itself flagged this residual risk: "token % is a proxy for degradation, not a measure of it."

Three things were verified this session before deciding: (1) the "dumb zone" (context rot / lost-in-the-middle) is best modelled as an **absolute** amount of occupied context (~150–200k), not a fraction of the admission limit — a bigger max window does not move where reasoning degrades; (2) the model ID in the transcript is bare `claude-opus-4-8` with no `1m` marker, and Opus 4.8's 1M window is standard (not a header-gated variant) — so the window **cannot** be inferred from the model string, killing any "detect model → map to window" approach; (3) the occupied-context figure stays sourced from the transcript's last main-chain call. A consolidated `usage` object on the Stop payload was considered as a faster source but rejected during review: whether its counts are per-call or cumulative-across-the-session is unverified, and a cumulative value would overcount and block healthy sessions — so the one figure we can reason about (the transcript's last call) remains authoritative. The occupied-context sum now also includes that call's `output_tokens`, since the just-generated response is carried into the next turn.

### Decision
The gate triggers on an **absolute occupied-context token budget**, taking whichever fires first:

    trigger = min( quality_budget_tokens , window * safety_fraction )

- `quality_budget_tokens` (default ~180k) is the real dumb-zone guard — an absolute floor, configurable, documented as **policy, not measured science**. It is what actually protects quality and is independent of the model's max window.
- `window * safety_fraction` remains only as a ceiling to catch genuinely small-window models before they hit their hard admission limit.

All comparisons move to **absolute tokens** rather than a rounded percentage. The variable that meant "window" is relabelled to mean "quality budget" so the code says what it does.

### Alternatives considered
- **Absolute budget + percentage safety ceiling** (chosen) — models the dumb zone as an absolute occupancy floor (the real phenomenon), stays correct across window sizes, and removes the wrong-denominator class of bug for good.
- **A) Set `CODERV_CONTEXT_WINDOW=1000000`** — rejected: silently moves the block to 750k (deep rot) and disables protection entirely if a smaller-window model is ever run on the same box; a safety gate that fails open is the worst failure.
- **B) Detect the model and map it to its real window** — rejected as the primary fix: the transcript model ID carries no window marker (`claude-opus-4-8` is the same string at 200k or 1M), so detection cannot distinguish the modes; and even a correct window is the wrong basis, since the dumb zone is absolute, not a fraction of the window.
- **Keep percentage-of-window, just fix the default** — rejected: makes the displayed number right while preserving the conceptual bug (that quality scales with the admission limit).

### Consequences
- Positive: the gate fires at an honest, model-independent floor (~180k) instead of a coincidence of a hardcoded denominator; the wrong-denominator bug class is gone; absolute-token comparisons also remove the percentage-scaling bugs at large windows (50k-wide warn buckets, 100k-wide re-arm hysteresis, `round()` boundary jitter).
- Negative / trade-off: `quality_budget_tokens` is a judgement call, not a measurement — it will need tuning as evidence accrues; and the two-brain marketing surface now describes a gate whose mechanism differs from ADR-006's wording, so ADR-006's text carries a pointer here.
- Revisit if: a model ships whose usable-reasoning window is genuinely and measurably larger (raise the budget on evidence), or Anthropic publishes a degradation curve that lets the floor be set from data rather than policy.

### Related
- Refines ADR-006 (anti-dumb-zone gates); supersedes only its trigger math, not its design.

---

## ADR-011: The installer completes the two-brain setup — detect Codex, ship portable reviewer rules, report honestly

**Date:** 2026-07-17
**Status:** accepted
**Decider(s):** owner (asked for "one smart install that finds Codex and completes everything"; chose the non-destructive options), Claude (implementer)

### Context
Installing the toolkit set up the *Claude* half of the two-brain workflow
(skills + the codex-review-gate hook) but left the *second brain* half manual:
the installer never checked whether the Codex CLI was actually present, and
never installed the reviewer rules Codex reads (`~/.codex/AGENTS.md`) — that
file existed only on the author's machine and was VPS-specific (referenced
`/home/appuser`, `SERVER-MAP.md`, "on this VPS"), so it could not ship
verbatim. Result: a downloader got a gate that fails open with a warning on
every commit, with no signal about *why* or how to enable the real review, and
an un-instructed reviewer even after installing Codex.

### Decision
Make `install.sh` a single smart install that completes the workflow:
1. **Detect Codex** — `codex_state()` echoes `absent` / `installed` (found but
   not signed in) / `authed`.
2. **Ship a portable reviewer-rules template** — `templates/codex-AGENTS.md`,
   the universal role + working discipline + hard rules (never commit/push,
   never touch prod infra, sibling-pattern, evidence-driven, no secrets,
   bilingual-aware) with the VPS-specific environment notes rewritten
   generically. The author's live `~/.codex/AGENTS.md` is left as-is.
3. **Install the rules non-destructively** — create `~/.codex/AGENTS.md` from
   the template if absent; if it already exists, **append our rules inside a
   `<!-- claude-docs-toolkit:agents START/END -->` marked block** (idempotent —
   skipped when the marker is present), never overwriting the user's content.
   `--uninstall` matches markers by exact line (never substring) and removes the
   block **line-based**: it drops only the START..END lines (plus an `OWNS-FILE`
   sentinel when present) and keeps every other line verbatim — so user edits
   made after install, above OR below the block, always survive. The whole file
   is removed only when the `OWNS-FILE` sentinel (written solely on fresh create)
   proves the toolkit made it AND nothing else remains — so a pre-existing empty
   file, or a toolkit-created file the user later wrote into, is never destroyed.
   Malformed/duplicated/markerless files are left untouched. The closing status
   reports reviewer-rules state honestly for every Codex state and never claims
   rules are installed when the template was missing.

   **Rejected finding (transparency rule): line-based removal normalises CRLF→LF
   and adds a final newline on a file that lacked one.** The gate flagged this as
   "not byte-for-byte." Rejected in favour of the more important property: a
   byte-exact (length-truncate) design was tried and **destroyed user edits made
   after install** — the common, damaging case. CRLF / no-final-newline in a
   `~/.codex/AGENTS.md` is rare, and normalising to LF-with-final-newline is
   correct POSIX text anyway. We optimise for "never lose a user's edits" over
   "preserve exotic byte encodings", and accept the normalisation.
4. **Install the gate regardless of Codex state** (no regression — it fails
   open harmlessly) and **print an honest status line**: two-brain ON (authed),
   "run `codex login`" (installed-not-authed), or "second brain OFF — run
   `npm i -g @openai/codex && codex login`" (absent).

### Alternatives considered
- **Marked-block append + gate-always + honest message** (chosen) — completes
  the setup without ever clobbering a user's own Codex rules (reuses the
  existing installer marker idiom) and without a second install run; the status
  line turns the silent fail-open into a clear upgrade path.
- **Create-only-if-absent** — leaves users who already have an `AGENTS.md` with
  an incomplete setup and a manual step; rejected for "completes everything".
- **Installer runs `npm i -g @openai/codex` for the user** — most hands-off but
  makes the installer install third-party software (network + npm surface).
  Rejected: the installer never installs third-party software (kept out of
  scope); it points, it doesn't fetch.

### Consequences
- Positive: one `install.sh` run now stands up the whole two-brain workflow (or
  clearly explains the one command to finish it); the reviewer is actually
  instructed; existing user files are never harmed (verified across create /
  append / idempotent-rerun / uninstall-keeps-content / untouched-file cases).
- Negative / trade-off: the shipped reviewer rules are generic, so a user with
  a specialised environment still tailors their own `AGENTS.md` (the marked
  block coexists with their edits by design). Codex detection is a point-in-time
  check — installing Codex later needs no re-run for the *rules* (already in
  place), only `codex login` to flip the gate on.
- Revisit if: hosts beyond Codex gain a review-gate equivalent (generalise the
  reviewer-rules install), or users ask the installer to fetch Codex itself.

---

## ADR-010: Bounded convergence extended to the commit path — the gate-deny anti-loop rule lives in the workflow, not in memory

**Date:** 2026-07-17
**Status:** accepted
**Decider(s):** owner (raised the concern + narrowed the escalation rule), Claude (implementer)

### Context
The codex-review-gate denies a commit until findings are resolved. A real
incident: the gate denied 6× in a row because findings were fixed one-at-a-time
and re-committed after each — every recommit is a fresh diff, so it earns a
fresh review, and the loop never terminates. Twice a *real* finding was also
wrongly dismissed on a lazy `grep` that matched a dependency's version, not the
lockfile's. The owner intervened ("no unlimited loop"). The corrective behavior
(batch-fix + commit-once + rebut-once + evidence-before-dismissal) was saved
only as a memory note (`feedback-gate-deny-no-loop`). The owner's objection:
memory is the *last* reinforcement layer, not the mechanism — a workflow rule
that only lives in memory isn't a guarantee, because it's silently lost if the
memory is pruned or the session runs where that memory isn't loaded. ADR-009
already bounds the *design-phase* (`/before`) loop with a round cap; the
*commit-time* loop had no equivalent bound in any durable artifact.

### Decision
Encode the rule into the workflow itself, four places, so it holds without
memory: (1) `/ship` Step 7 gate-deny block; (2) the gate's own deny message
(`REASON=` in `codex-review-gate.sh`) so it's in front of Claude even with no
skill loaded — text only, no control-flow change; (3) `AI-WORKFLOW-PLAN.md`
principle #8 (bounded convergence, both paths); (4) `~/.codex/AGENTS.md` so
Codex expects one converged retry. The rule: on a deny, fix **all** real
findings and retry in a **single** commit (never per-finding recommit); reject
a finding **only** with parsed, machine-verified proof; rebut to Codex **once**;
then **escalate to the owner when the same unresolved finding is rejected twice
on substantially the same rationale.** "Substantially the same rationale" is
defined narrowly: the **same underlying claim**, the **same cited evidence**,
and **no materially new code or facts** bearing on that finding — if any of the
three changes, it is a fresh finding and escalation does not trip. The memory
note is demoted to a pointer at these durable homes (reinforcement, not
mechanism).

### Alternatives considered
- **Docs + deny-message, no machine state** (chosen) — keeps the live gate's
  control flow untouched (matches how the gate already trusts Claude to
  adjudicate honestly), and the narrow escalation rule targets the real
  pathology (same claim + same evidence bouncing back) without penalizing
  legitimate iteration.
- **A deny-counter in the hook** — a real machine backstop, but adds state +
  reset logic to a live gate, and consecutive-deny ≠ loop (honest iteration
  also denies repeatedly, each time on a *new* finding). Rejected by the owner.
- **Leave it in memory** — the status quo this ADR exists to overturn: not a
  guarantee, invisible to other sessions/machines, lost on prune.

### Consequences
- Positive: the anti-loop guarantee is self-contained — any session follows it
  from `/ship` and the deny message, with or without memory. Same bounded-
  convergence doctrine now covers both the plan path (round cap) and the commit
  path (same-rationale escalation).
- Negative / trade-off: no machine enforcement — the commit loop still relies on
  Claude reading and following the deny text (as the gate already relies on
  honest adjudication) and the owner as final arbiter.
- Revisit if: a loop recurs despite the encoded rule (then reconsider the
  deny-counter backstop), or "substantially the same rationale" proves too
  fuzzy to apply consistently.

---

## ADR-009: The two-model workflow reviews the PLAN, not just the diff — design-phase Codex loop + immutable stamped spec + drift-hunter gate

**Date:** 2026-07-17
**Status:** accepted
**Decider(s):** owner (approved the design in principle + green-lit the convergence mechanism), Claude (implementer)

### Context
ADR-006 put a machine reviewer on every *diff* (the codex-review-gate). But by the time a diff exists, a wrong *approach* has already been built — the cheapest place to catch a bad plan is before any code is written. The two-model AI workflow (`AI-WORKFLOW-PLAN.md`) says the value of a second model is independent judgment; we were spending that judgment only at review time, not at design time. Two gaps followed: (1) `/before` presented a plan to the user with no independent peer review; (2) the gate reviewed diffs for correctness but had no notion of *drift* — a diff can be individually correct yet silently do more (or less) than the approved plan. A latent flaw compounded it: the existing per-task spec had no base-commit stamp, so nothing distinguished a fresh plan from a stale one left over from a prior task.

### Decision
Extend the two-model collaboration to the design phase and make the spec the shared source of truth across both phases:
1. **`/before` design-phase Codex loop** (new step 5.6): Claude drafts the plan, pipes it to Codex via one serialized stdin payload (the gate's channel), adjudicates findings, converges. Termination is guaranteed by a round cap (3), not by "disagreements shrink."
2. **Immutable stamped spec**: `/before` OVERWRITES (never appends) `~/.claude/coderlap/specs/<root-slug>.md` with a `Base:` commit stamp + ISO date. One spec = one task; appended history exposes stale baselines.
3. **Drift-hunter gate**: the codex-review-gate reads that spec ONLY when fresh (stamped base is an ancestor of HEAD AND file <24h old) and prepends it — the review then hunts for drift ([DRIFT]/[BUG] tags) on top of correctness. A stale/mismatched/missing spec falls back to the generic prompt and states "drift NOT checked" in every outcome — a drift review that never read a plan is never claimed.
4. **`/ship` deny-handling becomes a discussion**: on a gate deny, Claude may rebut to Codex once; Claude's call is final; the outcome is surfaced to the user.

Convergence has three terminal end states (CONVERGED / CAP-STOPPED / REVIEW-UNAVAILABLE) plus a non-terminal `running` label meaning "loop again"; "100%" means an empty *verified* unresolved-material set, never consensus; every finding is surfaced to the user with its classification, and the user overrules any of it. Full mechanism: `docs/planning/two-brain-convergence.md`.

### Alternatives considered
- **Plan review + immutable spec + drift gate** (chosen) — reuses the gate's exact stdin/slug patterns (DRY), adds no new user-facing command (stable-surface rule), and makes the same spec file serve `/before`, the gate, and the `/ship` reviewer.
- **A dispatcher that routes tasks between the two models** — machinery the transparency rule already covers; the routing rule in `AI-WORKFLOW-PLAN.md` is applied by Claude as conductor, no code needed.
- **"Convergence = disagreements shrink each round"** — rejected during the design's own Codex review: the material set can grow, so only the round cap guarantees termination.
- **Append to the spec (keep history)** — rejected: a later drift review could hunt against the wrong (stale) plan. History lives in git + SESSIONS, not the live spec.

### Consequences
- Positive: independent judgment now applies at design AND review; a correct-but-off-plan diff is caught; the spec is unambiguously fresh-or-ignored; no new command to remember.
- Negative / trade-off: `/before` adds a Codex round-trip (up to 480s, retried once) before the plan reaches the user; a genuinely fresh spec that predates an intervening commit reads as "not an ancestor" and drops to a generic review (fail-safe, not fail-open). Both degrade loud, never silent.
- Revisit if: the plan-review latency makes `/before` unpleasant (then gate it behind task size), or Codex plan-review quality proves low-signal.

---

## ADR-008: /ship commits via Claude's Bash after approval — the human approves, the machine gate reviews

**Date:** 2026-07-17
**Status:** accepted
**Decider(s):** Claude (per standing "adjust toward the better option" rule); shipped in v0.9.0, no owner veto raised

### Context
The codex-review-gate (4th gate) fires only on `git commit` run through Claude's Bash tool. /ship's old rule — "Never run `git commit` yourself. Show the command. The user runs it." — meant the toolkit's own commit ritual bypassed the machine reviewer entirely: a commit typed into the owner's terminal is invisible to Claude Code hooks. The 2026-07-17 gap scan confirmed this as a high-severity hole (two independent finder agents).

### Decision
/ship keeps the approval pause (nothing is committed until the user says "approve") but after approval **Claude runs the commit itself via Bash**, so every /ship commit passes through the codex-review-gate. On a gate deny, Claude adjudicates findings, fixes real ones, surfaces rejected ones with reasons, and retries.

### Alternatives considered
- **Approval-then-Claude-commits** (chosen) — preserves the old rule's intent (owner controls the commit moment) while guaranteeing the adversarial review the AI workflow plan mandates.
- **Keep "user runs it"; /ship pipes the diff to Codex as a checklist step** — duplicates the hook's logic inside a skill (DRY violation) and produces two review paths that can drift.
- **User runs commit via `! git commit` in-session** — depends on the user remembering the `!` prefix every time; a forgotten prefix silently skips review, which is exactly the failure mode gates exist to remove.

### Consequences
- Positive: "nothing lands unreviewed" now holds for the main commit path; the human-approval pause is unchanged.
- Negative / trade-off: each /ship commit waits 1–3 min for Codex; commits made in an outside terminal still bypass the gate (unfixable from inside Claude Code — documented, not hidden).
- Revisit if: the owner rejects Claude-run commits, or Codex latency makes /ship unusable (then consider reviewing at /ship-start in parallel).

---

## ADR-007: `/coderv` earns the 7th command slot — the router that makes the other six invisible

**Date:** 2026-07-15
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-005 set the bar for slot 7 "at least as high" as /lint's. Meanwhile the owner's real usage showed the actual adoption blocker: remembering which command comes next ("I don't want to keep writing commands manually — one command that identifies what's needed"). Six commands is a surface a human must index in their head; the craft literature (Matt Pocock's skills repo, `writing-great-skills`) names the cure: when user-invoked skills multiply past what you can remember, add a **router skill**.

### Decision
Add `/coderv <request>` as the 7th command: classify the request (feature / bug / question / wrap-up / docs-health), check project state from facts (lint freshness state file, dirty git, newest handoff), assemble the pipeline (/lint → /before → work → /ship → /session), show it once, drive the chain on a single yes — pausing only at the two human-judgment points (plan approval, scorecard approval).

### Alternatives considered
- **Router as 7th command** (chosen) — reduces the surface a human must remember from six to one; the six stay intact and individually invocable (SR preserved).
- **Grow the coderv-router hook instead** — the hook can only *suggest* per prompt; it cannot sequence a pipeline or carry state between steps. Complementary, not sufficient.
- **Fold routing into /before** — /before's single responsibility is pre-code grounding; making it also dispatch /lint//ship//session breaks SR and muddies its trigger vocabulary.

### Consequences
- Positive: the human types one command; discipline stops depending on memory. The 6-command surface is unchanged underneath — power users keep direct access.
- Negative / trade-off: 7 commands in the catalog; a pipeline abstraction that must never bridge past approval pauses (rule written into the skill).
- Revisit if: /coderv mis-classifies often (tighten Step 1 table) or users bypass it consistently (the router may be unnecessary on this machine).

---

## ADR-006: Anti-dumb-zone gates — ADR-004's principle extended from artefacts to live sessions

**Date:** 2026-07-15
**Status:** accepted (context-gate trigger math refined by ADR-012, 2026-07-19)
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-004 ruled that durable artefacts must cite verifiable sources. But the failure that motivated it (a compacted summary claiming v0.3.9 was shipped when nothing was committed) is a *live-session* disease: long sessions degrade ("the dumb zone"), compaction swaps state for intent, and agents ignore existing docs and start from scratch. Docs cannot fix this — it is a context problem, not a knowledge problem. Field comparison against Matt Pocock's skills repo shaped the approach: prevention over policing, feedback loops against ground truth (tests, git) rather than LLM-judges-LLM, fresh-context handoffs over riding into compaction.

### Decision
Three always-on Claude Code hooks + verification steps in the skills:
1. **grounding-gate** (PreToolUse) — first code edit in a doc-system project is blocked until /before writes a grounding receipt (or a conscious skip is declared). "Read the docs first" becomes physics, not advice. Docs-only edits never blocked.
2. **compact-rehydrate** (SessionStart, matcher `compact`) — injects a git/versions snapshot with the rule "when summary and snapshot conflict, the snapshot wins."
3. **context-gate** (Stop) — measures real context use from the transcript (last main-chain usage, sidechains excluded); warns at 60%, hard-blocks once per session at 75% with "write the handoff" as the only sanctioned move.
Plus: /before writes a spec checklist to disk (ground truth for intent); /ship spawns a fresh-context adversarial reviewer and computes a **verification scorecard** (gates passed/total, evidence pasted, 100% required for approval — never a self-rated confidence); /session handoffs embed verbatim command output; /lint sweeps in a subagent whose findings' quotes are machine string-matched.

### Alternatives considered
- **Prevention + machine gates** (chosen) — every check anchors to something that cannot hallucinate (files, git, string matches, token counts).
- **Always-on LLM auditor watching every turn** — cost/latency on every reply, judges share the model's blind spots, and a false accusation can push a true claim into a false "correction". Kept only in its cheap form: the fresh-context reviewer at /ship time.
- **Standing panel of per-doc expert agents auditing every request** — subagents don't persist; 21 agent runs per request; secondhand summaries multiply hallucination (telephone game). The salvageable ideas — delegate heavy reading, independent fresh-context review — are in the chosen design.
- **More/better documentation** — docs fix ignorance, not degradation; the failure occurs while holding perfect docs.

### Consequences
- Positive: the three failure modes each meet a mechanical gate; nothing depends on agent or human discipline. Scorecard turns approval into a glance.
- Negative / trade-off: hooks run machine-wide (every session on this box) — a misbehaving gate is felt everywhere; hence `CODERV_GATES_OFF=1` and tight scoping (gate applies only where CLAUDE.md + docs/ exist). Receipt validity is session-start-time based, so a receipt from a parallel same-machine session can unlock the door (rare, benign — accepted for KISS).
- Known residual risks (documented, accepted): reader/reviewer summaries are lossy (mitigated by file:line citations); a reviewer can share the model's blind spots where nothing is runnable; token % is a proxy for degradation, not a measure of it.
- Revisit if: gates false-positive enough to annoy (loosen scoping), or the 75% block fires mid-atomic-operation in practice (add a grace mechanism).

---

## ADR-005: `/lint` earns the 6th command slot — the toolkit gains its missing third operation

**Date:** 2026-07-13
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
The toolkit's rule says "keep the 5-command surface stable; features go in existing skills before they justify a new command." Yet field use (Al-Rafiq, 2026-07: a rule superseded → un-superseded → retired across three session entries; an obsolete OWNER-TODO list an audit had to catch; 9 draft docs wearing STALE banners for days) showed a failure class NO existing skill owns: docs that **lie**. Framed by the wiki pattern (ingest → query → lint): `/docify`+`/ship`+`/session` ingest, `/before`+`/session last` query — and *nothing* lints. `/ship`'s citation check is the only fragment, and it runs only when a commit happens to occur.

### Decision
Add `/lint` as the 6th command: audit CLAUDE.md + docs/ for contradictions, stale claims, dead references, and rot; report with `file:line` + the conflicting reality; offer fixes but never auto-apply and never delete history. Also in this release: `/session` rotates entries >20 to an append-only archive, and `release.sh` turns the VERSION/CHANGELOG/tag/website ritual into a machine gate.

### Alternatives considered
- **New `/lint` command** (chosen) — auditing is a distinct responsibility (SR): /docify generates, /ship maintains at commit time, /lint verifies on demand. Distinct trigger vocabulary ("are the docs up to date?" ≠ "write docs").
- **Fold into `/docify --lint`** — conflates generate with audit; docify's TRIGGER intent ("no docs exist") is nearly opposite to lint's ("docs exist but may lie"); flag-modes are invisible in the skill picker.
- **Fold into `/ship`** — lint only-on-commit misses exactly the rot that accumulates *between* commits, and makes shipping slower every time.

### Consequences
- Positive: the ingest/query/lint triad is complete; doc trust becomes checkable instead of assumed.
- Negative / trade-off: 6 commands to learn instead of 5; the surface-stability rule needed an amendment (bar for slot 7 explicitly set at least this high).
- Revisit if: /lint goes unused for months (fold its checks into /ship) or its checks prove too noisy (tighten to citations + version strings only).

---

## ADR-004: Verification of model claims is a toolkit-wide principle, not a `/session` patch

**Date:** 2026-04-25
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-001 fixed a symptom: `/session` trusted a compacted summary that lied about shipping. ADR-003 broadened *how* `/session` verifies. But the underlying disease is bigger: **every skill in the toolkit consumes prompt context and writes durable artefacts based on it.** Each one has the same failure mode `/session` just exhibited.

- `/ship` reads "what changed" from the diff — but its commit message is drafted from the model's *narrative* of what changed, which a compaction can corrupt the same way.
- `/decision` writes ADRs from conversation context. If the model misremembers an alternative we considered, the ADR records a fiction as history. (Ironically, this very ADR is vulnerable.)
- `/docify` is the cleanest of the five — it cites source files and re-validates citations. That's the *correct* pattern. The other skills should match it.
- `/before` reads "prior art" from grep + memory; less exposed because it acts before the work, not after.

Treating verification as a `/session`-only feature leaves four of the five skills vulnerable to the same class of failure that motivated ADR-001 in the first place.

### Decision
**Establish a toolkit-wide verification principle and apply it to all five skills.**

The principle: **every durable artefact a skill writes (handoff, ADR, commit message, doc) must cite a verifiable source — a file, a commit, a diff, a directory listing — not a model recollection.** When prompt context conflicts with verifiable source, the source wins, and the conflict is recorded in the artefact.

Concrete application per skill:
- **`/session`** — verifies as per ADR-001 + ADR-003 (git or filesystem snapshot). Already covered.
- **`/ship`** — must re-read the actual `git diff` (not the model's description of it) before drafting the commit message. Citation validation already happens here for docs; extend to "the commit message's claims must match the diff."
- **`/decision`** — when an ADR cites a "prior conversation" or "we discussed", the skill should require the user to confirm or reject the recollection inline. The ADR records confirmed facts only. Unverified recollections get marked `(unverified — model recollection)`.
- **`/docify`** — already correct. Codify it as the design precedent in the toolkit's docs.
- **`/before`** — must run actual `grep` / `git log` searches for prior art, not summarise from memory. If the model says "I think we did this in `auth.ts`," the skill must `grep` `auth.ts` before stating it as fact.

### Alternatives considered
- **Toolkit-wide principle, applied per-skill** (chosen) — closes the failure mode at its actual scope. Matches the existing `/docify` pattern (which already works). Adds a unifying principle to the toolkit's design docs that future skills inherit by default.
- **Patch each skill ad-hoc as failures arise** — the path of least resistance, but it means every skill has its own failure-then-fix cycle. We just lived through one; no need to schedule four more.
- **Add a sixth "verify" skill that other skills call** — violates ADR-002 (keep the surface at 5). Verification is a *cross-cutting concern*, not a user-facing command. It belongs inside the existing five, not beside them.
- **Trust the model and accept occasional drift** — the toolkit's whole pitch is *discipline for AI-assisted dev*. Accepting that the discipline tools themselves drift is incoherent.

### Consequences
- Positive: One principle, applied five places, closes a class of bugs instead of one instance. Aligns the toolkit's internals with the citation-grounded story `/docify` already tells externally. Future skills (if any) inherit the principle by default.
- Positive: Gives the toolkit a real architectural identity — *"every claim is sourced"* — that differentiates it from prompt-template libraries that just chain LLM calls.
- Negative / trade-off: Each skill's prompt grows in size and tool-call count. Slower runs. More visible tool noise to the user. Mitigation: keep verification commands minimal and structured; don't dump verbose output back to the user unless there's a contradiction worth flagging.
- Negative / trade-off: This ADR is itself unverified (it summarises today's session from memory). The first thing the new principle would catch is *its own creation*. That's noted, not paralysing — ADRs document intent; the implementation is what enforces the principle going forward.
- Revisit if: Implementation reveals that one or more skills genuinely don't have a verifiable source for some claim. At that point, mark the unverifiable claim explicitly rather than dropping the principle.

### Related
- ADR-001 (the original failure that exposed this)
- ADR-002 (keeps the surface at 5; this ADR explains how to make those 5 trustworthy without adding a 6th)
- ADR-003 (the verification *mechanics* — this ADR is the *principle* those mechanics implement)
- `/docify`'s existing citation model — the precedent this principle generalises from.

---

## ADR-003: Verification mechanics — no-git fallback, session-anchored windows, multi-repo, and uncommitted state

**Date:** 2026-04-25
**Status:** accepted (extends ADR-001)
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-001 said "verify ship claims from git." Pressure-tested, that decision has four real gaps:

1. **No-git environments.** Solo writers, fresh folders, kiosks, locked-down corporate machines. CoderLap's pitch is *low-friction discipline*; failing on day one for anyone without `git init` undermines that.
2. **Time-window staleness.** The skill template uses `git log --since="6 hours ago"`. After a weekend, holiday, or sick day, that window is empty and `/session` reports "nothing shipped" while Friday's commits sit just outside the window.
3. **Uncommitted-but-real work.** Most days, the most useful handoff is *"I have changes staged but not committed; here's what's in flight."* Pure commit verification flags this as "nothing shipped" — technically true, practically wrong.
4. **Multi-repo sessions.** Today's session edited two repos in lockstep (toolkit + website). `/session` runs in one cwd; the other repo is invisible. The compaction-lied incident is a direct consequence of this — half the state was unwatched.
5. **Branches.** Work committed on a feature branch is invisible to `git log` on `main`. Same family of issue as #4.

Issue #6 (locale/timezone for "6 hours ago" interpretation) collapses into #2 once we anchor windows to the previous session's timestamp instead of wall-clock.

### Decision
**Two-tier verification, anchored to the previous session, covering staged + unstaged + committed state across all repos the user declares relevant.**

**Tier 1 — git available:**
- Window: `git log --since="<timestamp of previous SESSIONS.md entry>"`. Falls back to "24 hours" only on a fresh `SESSIONS.md`.
- Capture three states explicitly: `git diff --stat` (unstaged), `git diff --cached --stat` (staged), `git log --oneline <since-anchor>..HEAD` (committed). Each appears in the handoff with its own label, never collapsed into "what shipped."
- Branch awareness: include `git branch --show-current` and `git log --all --since=<anchor>` so work on feature branches is visible.
- Multi-repo: the user can declare related repos via a `coderlap.repos` list in `CLAUDE.md` frontmatter or a top-level `.coderlap/repos.txt`. `/session` walks each. A repo not declared is not verified — by design, to avoid surprise filesystem traversal.

**Tier 2 — no git:**
- Snapshot file: `/session` writes `.coderlap/last-session.json` at end of every run. Captures `{path, mtime, size, sha256}` for every file in the project (excluding `.gitignore`-equivalent patterns: `node_modules/`, `dist/`, `.env*`).
- Next session: diff current filesystem against the snapshot. New files, modified files, deleted files all surface. Handoff says "filesystem-verified (no git)" so the user knows verification was best-effort.
- Snapshot file is `.gitignore`-d. It's per-machine state, not project state.

**Both tiers:**
- If prompt context claims something happened that verification contradicts, the handoff records the contradiction explicitly: *"Note: prior conversation claimed X shipped; verification shows Y."* Never silently overwrite either source.
- If neither tier is available (no git, no write access for snapshot), `/session` writes the handoff with a top banner: *"⚠ Unverified — no verification mechanism available. Treat 'what shipped' as model recollection."* Better honest-and-flagged than confidently-wrong.

### Alternatives considered
- **Two-tier, session-anchored, multi-state, multi-repo** (chosen) — closes all four scoping gaps in one decision. Tier 2 makes CoderLap usable for non-developers without forcing git on them. Snapshot diffing is well-understood (rsync, restic, etc., do the same).
- **Require git, hard fail otherwise** — simpler but excludes a real audience (writers, students, kiosks). Contradicts the toolkit's "low-friction" positioning.
- **Pure mtime-based fallback (no snapshot file)** — can't detect deletions, can't detect content changes that preserve mtime, and resets across machine reboots in some filesystems. Snapshot file is a small price for correctness.
- **Auto-discover all git repos under cwd recursively** — too invasive; surprises the user when `/session` reports on a vendored submodule or a node_modules `.git` folder. Explicit declaration is the right tradeoff.
- **Wall-clock window ("last 6 / 24 hours")** — fails after weekends as documented. Session-anchoring is more work but matches actual user behaviour (work happens between sessions, not between hours).
- **Treat staged and unstaged as one bucket** — loses the "in flight vs. committed" distinction that's the whole point of a handoff.

### Consequences
- Positive: `/session` works for non-developers (Tier 2). Works after weekends (session-anchoring). Captures in-flight work (staged/unstaged tracked separately). Handles multi-repo workflows the toolkit author actually uses (ADR-001 was *itself* discovered via a multi-repo failure).
- Positive: Honest about its limits. The "⚠ Unverified" banner is a feature, not a failure — better than the current implicit-trust-in-model failure mode.
- Negative / trade-off: Two code paths in `skills/session/SKILL.md`. Snapshot file is yet another piece of per-machine state to maintain. Multi-repo declaration adds a config surface (`.coderlap/repos.txt` or CLAUDE.md frontmatter) — the toolkit's first piece of declarative configuration.
- Negative / trade-off: Snapshot diffing on large projects is slow. Mitigation: cap at ~10k files; skip directories matching common ignore patterns; offer an opt-out.
- Negative / trade-off: ADR-002 said "keep surface at 5." This ADR doesn't add a skill, but it does grow `/session`'s prompt and tool-call count significantly. Watch for the skill becoming unwieldy.
- Revisit if: A meaningful number of users hit the "no verification mechanism available" branch — that signals the tiers don't cover real workflows. Or if Claude Code adds a native filesystem-state primitive that obviates the snapshot file.

### Related
- ADR-001 (this extends it; ADR-001's git assumption is now Tier 1)
- ADR-002 (this respects "5 commands stable" by enriching `/session` rather than adding a new skill)
- ADR-004 (the *principle* this ADR's mechanics implement — verification is toolkit-wide)
- `/docify`'s citation-validation model is the design precedent for "verify against source, flag contradictions."

---

## ADR-002: Curate the skill surface — CoderLap's 5 must stay legible amid third-party skills

**Date:** 2026-04-25
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
The user's environment now exposes ~50 skills: CoderLap's 5 (`/before`, `/docify`, `/decision`, `/ship`, `/session`) plus the impeccable design suite (`/critique`, `/distill`, `/audit`, `/polish`, etc.) plus framework-level skills (`/init`, `/review`, `/security-review`). Worse, the impeccable skills appear *twice* — once unprefixed (`/critique`) and once namespaced (`/impeccable:critique`) — every shared name resolves to two near-identical entries.

A new CoderLap user reading the skill picker can't tell which 5 commands *are* CoderLap. The discipline loop is the product; if it's lost in the noise, the product is lost in the noise. This is the same anti-pattern the licence page has (11 identical bricks problem) — too many same-shape items dilute the few that matter.

### Decision
1. **Treat the CoderLap 5 as a curated set with shared visual/textual identity.** Every CoderLap skill description starts with the same opening sentence pattern ("Pre-code checklist...", "Pre-commit checklist...", "Session handoff..."). Add a consistent prefix or visual marker to make them scannable as a set in the skill picker.
2. **Document the duplication, do not try to fix it.** The `impeccable:*` namespace duplication is upstream (impeccable's distribution choice), not ours. Add a one-line note to `README.md` so users aren't confused: "CoderLap ships 5 skills. Other skills you see (`/critique`, `/audit`, etc.) come from other plugins like impeccable — not us."
3. **Resist the urge to add more skills.** Per CLAUDE.md "Never add unrequested scope" — new behaviour goes into the existing 5 (smarter TRIGGER phrases, richer step lists) before it justifies a 6th command.

### Alternatives considered
- **Curate identity + document boundary** (chosen) — keeps the 5 legible without fighting upstream namespace decisions; honours the existing "stable surface area" rule in CLAUDE.md.
- **Add a `coderlap:` namespace prefix to all 5 skills** — would solve scannability, but breaks every existing user's muscle memory (`/before` → `/coderlap:before`) and every doc/screenshot in circulation. Cost > benefit at current adoption.
- **Build a `/coderlap` meta-skill that runs the 5 in sequence** — adds a 6th skill to the surface area we just said we'd keep stable. Solves nothing — users still need to know the 5 individually for the loop to work.
- **Ignore it** — accepts ongoing user confusion; the discipline loop's discoverability degrades as more third-party skills enter the picker.

### Consequences
- Positive: New users can identify the CoderLap set at a glance; the 5-skill scope stays defended against feature creep; no breaking change to existing users.
- Negative / trade-off: Requires a small editing pass across all 5 skill descriptions to enforce shared opening patterns. Doesn't *solve* the namespace duplication — only documents it.
- Revisit if: Claude Code adds a native skill-grouping or plugin-bundle mechanism that lets us declare the 5 as a coherent set without touching individual descriptions.

### Related
- ADR-001 (verification in `/session` — same theme: making the discipline loop trustworthy)
- ADR-004 (the verification principle that ADR-001 generalises into)
- CLAUDE.md rule: "Keep the 5-command surface area stable"

---

## ADR-001: `/session` must verify ship claims from git, not from prompt context

**Date:** 2026-04-25
**Status:** accepted (extended by ADR-003 and generalised by ADR-004)
**Decider(s):** Hadi (CoderLap author), Claude

### Context
Today's session hit a real failure. A compacted conversation summary asserted that v0.3.9 was "fully committed, bumped, tagged, pushed, GitHub release created" — and the prior `/session` handoff faithfully captured that claim. None of it was true. `git status` showed both repos with `CLAUDE.md` + `docs/` still untracked. `cat VERSION` still read `0.3.8`. No tag existed. No release existed.

The failure mode: Claude's compaction summarised *intent* as if it were *state*. `/session` then transcribed that intent into the handoff. A future session reading "shipped" would have skipped the actual ship steps, leaving the project in a broken half-state.

This is not a model bug — it's a design gap in `/session`. The skill writes whatever the conversation context contains. If context is wrong, the handoff is wrong. The user's whole thesis ("discipline for AI-assisted dev") collapses if the discipline tool itself can't be trusted.

### Decision
`/session` must run verification commands and source ground-truth facts from them — not from prompt context — for the "What shipped" section. Specifically:

1. Before writing the handoff, run: `git status -s`, `git log --since="6 hours ago" --oneline`, and (if a `VERSION` file exists) `cat VERSION` plus a grep for the version string in the relevant config/package files.
2. The "What shipped" bullets must reference *commit hashes* or *tracked file paths* — not prose like "fully committed". If a file is untracked, that fact appears in the handoff, not its absence.
3. If the conversation context claims something shipped that the verification commands contradict, `/session` flags the contradiction in the handoff itself ("Note: prior summary said X shipped; git shows it didn't"). It does not silently trust either source.

> **Note (added 2026-04-25):** ADR-003 extends this with a no-git fallback, session-anchored time windows, multi-repo support, and explicit handling of staged/unstaged state. ADR-004 generalises the underlying principle ("verify against source, not recollection") to all five skills. ADR-001 is the original, narrow scoping; refer to ADR-003 + ADR-004 for the current implementation contract.

### Alternatives considered
- **Verify from git, flag contradictions** (chosen) — matches the citation-grounded philosophy of `/docify`. Same principle: doc claims must be backed by source artefacts, not by model confidence.
- **Trust prompt context, ask the user to confirm** — adds friction to every `/session` invocation; users skip prompts; same failure mode survives.
- **Verify silently and overwrite contradictions** — loses the audit trail. The contradiction itself is valuable signal — future sessions should see that a prior summary lied, so they learn to verify too.
- **Do nothing; document the failure mode in CLAUDE.md** — passes responsibility to the user. The whole point of skills is that the user *doesn't* have to remember the discipline.

### Consequences
- Positive: Handoffs become trustworthy artefacts. Failure mode that just happened cannot recur silently. Reinforces the "verify from source, not from confidence" principle that already underpins `/docify`.
- Negative / trade-off: `/session` becomes slightly slower (3-4 extra commands per invocation). Skill prompt grows more complex. Extra tool calls visible to the user.
- Revisit if: A lighter-weight verification mechanism appears (e.g. Claude Code exposes git state to skills natively without explicit shell calls).

### Related
- ADR-002 (skill curation — same theme of making the discipline loop reliable)
- ADR-003 (extends this with no-git fallback and the four scoping gaps)
- ADR-004 (generalises the principle behind this decision to all five skills)
- KI-NNN: log the original incident as a Known Issue once the fix lands.
- The `/docify` citation model is the design precedent for this — every doc claim cites a source line; every handoff claim should cite a git fact.

---

<!-- New ADRs above this line, newest first -->
