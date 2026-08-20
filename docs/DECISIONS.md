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

## ADR-027: Green is per-job, never per-run — required CI is declared in-repo and verified by enumeration

**Date:** 2026-08-10
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude (with Codex plan review, 1 round → CONVERGED, 3 findings all confirmed and adopted)

### Context

"Green on one platform is not green" existed only as a sentence in a downstream
handoff (`devkit/docs/SESSIONS.md`). Nothing read it, so nothing enforced it,
and the same failure happened twice in one week:

- Run `31374769158` on `4e795eb` — `go-verify (windows-latest, stable)` was the
  **only** failed job of five. The test suite had been run on Linux only and
  that was treated as sufficient.
- The preceding session shipped under the same assumption.

Two API behaviours make this trap easy to fall into, both verified against the
live repository rather than assumed:

1. **The run-level conclusion is not the per-job truth.** `gh run view --json
   conclusion` reports `success` for a run in which a required job never
   appeared. Any check keyed on `.conclusion` reproduces the exact bug.
2. **`gh run watch` lies.** It streams ✓ for the single leg it follows and then
   exits 1 — a green stream is not a green run.

Two further facts shaped the design, both measured:

3. **A commit can have several runs.** Ten shas in devkit's history carry two
   runs each (branch push + tag push), and run `30986570121` — recorded in
   devkit's ADR-006 as a *failure* — reads `success` today because it was
   re-run in place. "The run for this sha" is not a single well-defined object.
4. **Job identity alone is ambiguous.** A job exposes only `name`;
   `workflowName` exists solely at the run level. Two workflows defining the
   same job name are indistinguishable unless the workflow is declared too.

### Decision

**1. Required jobs are declared by the repository, verified by the toolkit.**
Each repo carries `.coderv-ci.json` listing required jobs by explicit
`{workflow, job}` identity. Required jobs are a property of the repository; the
generic enforcement mechanism is a property of the toolkit. The toolkit never
infers what "required" means from workflow YAML.

**2. The verdict is derived only from the declared jobs.** For each one:
consider only runs for HEAD's sha whose `workflowName` matches, select the
highest `databaseId` containing that job (run ids are monotonic, so this is
deterministic — `createdAt` was observed out of order against `startedAt` on
real reruns and is not a safe tiebreak), and let that job's conclusion decide.
**An unrelated workflow can neither manufacture green nor manufacture red.** A
nightly job still running does not block a genuinely green required set; a
nightly job failing does not fail it.

The commit's runs are requested from GitHub **by commit**
(`gh run list --commit <sha>`), never filtered out of a recent-runs window: a
window silently stops containing the target commit as history grows, and every
required job would then read `MISSING` — a false red indistinguishable from a
real one. The target sha is first resolved through git to one full 40-character
id (`rev-parse --verify --quiet <sha>^{commit}`); an abbreviation that resolves
to nothing is `UNVERIFIED`, and runs are matched by equality so a sha *prefix*
can never pool runs from sibling commits.

**3. Every non-success state stays distinct.** `MISSING`, `FAILED`,
`CANCELLED`, `SKIPPED`, `RUNNING`, `UNVERIFIED` are reported separately and
exit non-zero (0 GREEN, 1 NOT GREEN, 2 RUNNING, 3 UNVERIFIED). Collapsing them
would destroy the distinction between "a leg failed" and "a leg never ran" —
which is precisely the information the incident needed. GitHub's other terminal
conclusions (`timed_out`, `action_required`, `stale`, `neutral`) are not success
and so are not green; each keeps its raw conclusion in the report. A conclusion
this script does not recognise is `UNVERIFIED` — not assumed bad, not assumed
good, because a future GitHub state guessed either way is a lie.

**4. Configuration fails closed.** Missing, unreadable, malformed, empty, or
duplicate-bearing config is `UNVERIFIED`, never a pass. Absence of a
declaration means "requirements unknown", never "no requirements". Parsing uses
`jq -e` with explicit type and length checks, never the `?` operator: on valid
JSON that simply lacks `required_jobs` (or carries it empty), `jq -r
'.required_jobs[]?'` exits **0** with empty output, so a naive loop iterates
zero times and reports a vacuous green — the same class of bug this ADR exists
to prevent. (A malformed file does signal a non-zero `jq` status, but relying on
that alone would still miss the empty and missing-key cases.)

**5. `UNVERIFIED` is never rounded up.** In `/ship`'s scorecard it scores
✖-with-reason and stays in the denominator. "We could not check" and "it is
green" are different facts.

### Alternatives considered

- **Per-job enumeration against a declared list (chosen)** — the only approach
  that catches a required job which never ran.
- **Trust the run-level `conclusion` (rejected)** — verified to report `success`
  while a required job is absent. This *is* the bug.
- **Infer required jobs from `.github/workflows/*.yml` (rejected)** — the YAML
  describes what *can* run, not what is *required*; matrix legs expand at
  runtime and `if:` conditions are not statically resolvable.
- **Hardcode devkit's five jobs (rejected)** — makes a general mechanism
  single-repo and puts repo policy in the toolkit.
- **Match jobs by name only (rejected)** — ambiguous across workflows (fact 4).
  devkit has one workflow today, so this would work by luck and break silently
  on the second.
- **Treat any in-progress run for the sha as RUNNING (rejected, owner
  correction)** — lets an unrelated workflow block a green required set. The
  verdict must derive from the declared jobs alone.
- **A documentation rule (rejected)** — this was already the state of the world,
  and it failed twice.

### Consequences

- Positive: the historical failure is now caught mechanically. Against the real
  commit `4e795eb`, the checker returns `NOT GREEN` and names
  `go-verify (windows-latest, stable)` as the sole failed leg.
- Positive: partial-matrix success — a `success` run missing a required job —
  cannot be reported as green.
- Positive: states remain diagnosable; the output names which leg and why.
- Trade-off: every repo wanting the gate must add `.coderv-ci.json`, and a repo
  without one scores ✖ rather than passing. This is deliberate: silence is not
  consent.
- Trade-off: the declared list can drift from the workflow if a job is renamed.
  The failure mode is safe — a renamed job reads `MISSING`, which blocks rather
  than passes.
- Revisit if: GitHub exposes workflow identity on the job object (job-name
  matching would then need no declared workflow), or if repos accumulate enough
  required jobs that a bare list stops being sufficient.

---

## ADR-026: Wave-2 adoptions from mattpocock/skills — effort maps without a tracker, grill mode, merge-conflict rule; the reviewer split is rejected on re-analysis

**Date:** 2026-07-28
**Status:** accepted (updates one line-item of ADR-025)
**Decider(s):** Hadi (CoderLap author), Claude (with Codex plan review, 2 rounds → CONVERGED)

### Context
After ADR-025 shipped, the owner asked whether the remaining unadopted items could be adopted "in an extremely smart way", then asked for a re-analysis with honest confidence scores. The re-analysis found: (a) wayfinder's tracker dependency was never essential — his own setup offers a local-files mode, so the *decision-map discipline* is adoptable on plain markdown; (b) grilling's one-question-at-a-time discipline has a clean opt-in home inside `/before`; (c) ADR-025's dismissal of `resolving-merge-conflicts` as "generic" conflated the *skill* (still not worth adopting) with its distilled *rule* (one CLAUDE.md line); (d) my own wave-2 proposal to split `/ship`'s reviewer into two subagents (his Standards/Spec separation) scored only 68% under re-analysis and is rejected below.

### Decision
Three adoptions (same release, v0.16.0):

1. **🗺 Effort maps** — a new `/coderv` shape (ADR-014 pattern) driven by `skills/coderv/effort-map.md`: one `docs/PLAN-<topic>.md` per multi-session effort with `Status: active|done`, Destination, Decisions-so-far, Open questions, fog ("Not yet specified"), and Out of scope. Two invariants close the hazards Codex and self-review found: **the map is an index, never a store** — decisions live only as ADRs, the map links them (two homes for one decision is the contradiction `/lint` hunts); and **selection is deterministic** — `grep -l '^Status: active' docs/PLAN-*.md`, with multiple actives always asked about, never guessed. `/before` reads the active map as prior art; `/session` hands off the frontier; `/lint` flags a >30-day-untouched active map as rot.
2. **Grill mode** — opt-in Step 4.5 in `/before` for requests with open *decisions* (not missing facts): one question per message, each with a recommended answer; facts are looked up, never asked; scout findings are settled facts and never re-asked; exit into the normal plan, answers landing in the spec checklist.
3. **`coderlap:rule:merge-conflicts`** in `templates/CLAUDE.md` — resolve from primary sources; both intents where compatible, the merge's stated goal where they conflict; never invent behaviour; `--abort` is not the default exit. This **updates ADR-025's line-item**: the *skill* stays rejected (thin), the distilled *rule* is adopted — recorded here so it reads as a considered status change, not a silent reversal.

**Rejected: the two-subagent reviewer split** (Spec axis and Standards axis in separate clean contexts). Re-analysis: the masking problem it solves is *merged rankings* — and `/ship`'s scorecard already keeps spec gates and advisory smell notes structurally separate, with the codex gate as an independent second context besides. The residual benefit doesn't justify doubling reviewer-subagent tokens on every commit. Revisit if smell notes ever start drowning spec verdicts in the single reviewer's report.

**Still not adopted** (unchanged from ADR-025): a real issue tracker (maps deliberately stay local markdown), `to-spec`/`handoff`/`implement` (duplicates of stronger toolkit parts), his persona/content skills.

### Alternatives considered
- **Adopt the discipline, keep local markdown** (chosen) — the value of wayfinder is the decision-map shape, not the tracker plumbing; local files keep the toolkit's no-server grain and `/lint` can police the map like any doc.
- **Adopt wayfinder verbatim with a tracker** — rejected: infrastructure the flow doesn't run, and per-ticket child issues would fight DECISIONS.md for ownership of decisions.
- **Build all four wave-2 items** — rejected: shipping a 68%-confidence item into a minimal-surface toolkit is how surfaces bloat; the rejection is recorded with its revisit trigger instead.

### Consequences
- Positive: multi-session efforts (career hub, migrations) get a persistent decision frontier that survives session boundaries instead of living in "next session should…" prose; vague requests get a cheap alignment loop; every conflict resolution has a written discipline.
- Negative / trade-off: one more run-book to maintain; a map only helps if work-through mode actually gets invoked — `/coderv`'s bare-scan proposal (precedence slot 4) is the mechanism that keeps it alive.
- Revisit if: maps stay `active` untouched for months across projects (the discipline isn't sticking — simplify or drop), or the single-reviewer report shows smells crowding out spec verdicts (reopen the split).

---

## ADR-025: Adopt mattpocock/skills' clean-code substance, woven into the 7 commands — reject its review loop and tracker machinery

**Date:** 2026-07-28
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude (with Codex plan review, 2 rounds → CONVERGED)

### Context
The owner evaluated [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, ~192k stars) against the toolkit and set the goal explicitly: *not* defending the toolkit — "I am looking for something [that] deliver[s] a clean code to me." A full read of all 17 engineering + productivity skills found genuinely superior articulations of several clean-code disciplines the toolkit lacked — alongside machinery that would break the toolkit's hard-won invariants: his `code-review` is an ungated second review loop (no ledger, no cap, no ceiling — exactly what ADR-019/021/022/023/024 exist to bound), and `wayfinder`/`triage`/`to-tickets` are built on issue-tracker infrastructure this flow doesn't run. The `never-unrequested` 7-command cap and the ADR-014 precedent (weave capabilities through existing commands, never a new slot) constrain *how* anything gets adopted.

### Decision
Adopt the **substance** of seven items, each woven into an existing command (v0.16.0):

1. **`docs/CONTEXT.md` project vocabulary** — new `templates/CONTEXT.md`; generated by `/docify` through the normal drafts-first flow; read by `/before` Step 3 (position 2); lint-checked deterministically (every Terms row carries a code anchor verified like any citation; the Domain-only section is anchor-exempt by design).
2. **`coderlap:rule:tests`** in `templates/CLAUDE.md` — expected values from an independent source of truth (never recomputed the code's way); vertical slices by default, with regression/characterization tests as named exceptions.
3. **`coderlap:rule:design`** in `templates/CLAUDE.md` — deep modules, the deletion test, accept-dependencies-don't-create-them, one-adapter-hypothetical/two-real; scoped to core logic, with adapters/handlers/glue as named exceptions. `/before`'s detailed plan now names the seam being touched.
4. **Fowler smell baseline** (12 smells, name → fix) — into `/ship`'s fresh-context reviewer *brief* only; advisory notes, never scorecard gates; repo-documented standards override.
5. **Prototype discipline** — `/before` Step 5 may plan a "prototype first" step for open design questions (throwaway-marked, one command, no persistence, verdict via `/decision`, never lands on main).
6. **Bug-diagnosis run-book** — `skills/coderv/bug-diagnosis.md` (sibling of `architecture-review.md`, per ADR-014's run-book pattern), driven by the 🐛 shape: a red-capable repro loop is mandatory *before* any hypothesis.
7. This ADR itself, so the rejections below survive future "should we adopt X?" re-debates.

**Rejected: his `code-review` skill.** Its two-axis *insight* is already native (the codex gate is the standards/defect axis; the fresh-context subagent verdicts each spec item and flags unrequested diff content — the Spec axis; they are reported separately and never reranked). What the skill would add is the loop: a second, ungated reviewer with no memory, no cap, and no self-termination — re-creating precisely the failure the gate's ledger/cap/ceiling machinery closed. The smell *baseline* carries the remaining value without the loop.

**Not adopted (recorded so they aren't re-litigated):** `wayfinder`/`triage`/`to-tickets` (tracker infrastructure the flow doesn't run; SESSIONS.md + specs serve the multi-session role — revisit only if a tracker enters the flow); `handoff` (weaker than `/session`'s git-verified claims, ADR-001); `to-spec` (`/before` Step 5.5); `improve-codebase-architecture` (ADR-014's audit, whose CDN-based HTML report also violates the toolkit's grain); `research`/`implement`/`resolving-merge-conflicts` (thin or generic; the
merge-conflicts line-item was later updated by ADR-026 — skill stays rejected,
a one-line distillation was adopted).

### Alternatives considered
- **Weave the substance, reject the machinery** (chosen) — clean code was the goal; every adopted item acts directly on code being written or committed, and nothing touches a hook or adds a command.
- **Install his repo as a Claude Code plugin alongside** — rejected: duplicate front doors (`grill-with-docs`/`wayfinder` claim the same triggers as `/before`, splitting the router's HIGH-confidence path), his `code-review` would run ungated, and his setup skill writes a parallel docs tree (`docs/agents/`, `CONTEXT-MAP.md`) beside the toolkit's.
- **Adopt nothing** — rejected by the owner's stated goal; the test/design/vocabulary articulations are genuinely better than what the toolkit had.

### Consequences
- Positive: every project scaffolded or docified from the toolkit now carries test-honesty and module-depth rules; every `/ship` diff gets a smell pass; every hard bug gets a repro-loop discipline; naming drifts get a canonical vocabulary that `/lint` can mechanically police.
- Negative / trade-off: `templates/CLAUDE.md` grows (~30 lines) — every downstream session pays that context; the smell baseline adds reviewer-subagent tokens per `/ship`; CONTEXT.md is only as alive as its lint cadence.
- Revisit if: a real issue tracker enters the owner's flow (wayfinder becomes worth a fresh look), or the smell notes prove noisy enough that the baseline needs a diff-size floor.

---

## ADR-024: The heredoc fail-closed deny honours the owner gates-off flag — the last gate block that could trap the owner is closed

**Date:** 2026-07-25
**Status:** accepted
**Decider(s):** owner (explicit "approved 100%" in-session) + Claude (plan converged with Codex, LGTM round 2)

### Context
An audit of "can any gate block the owner with no in-band escape?" found exactly one. `codex-review-gate.sh` fails CLOSED (a hard `deny`) when a commit contains a `<<` heredoc AND the `awk` command-scrub cannot run (awk missing/failing) — because a heredoc body could otherwise smuggle an unreviewed commit line past the scrub. That deny fires very early, *before* the review target repo is resolved, so it sat ahead of BOTH owner-escape checks: the emergency gates-off flag (previously at the normal skip site) and the ADR-023 per-diff `--approve` marker. Result: on an awk-less host, an owner who said "ship it" had no in-band way past the fail-closed deny — the exact "gate overrules the owner" failure ADR-023 exists to forbid, surviving in one un-audited corner. Reachability was low (awk present on the dev host three ways), but the charter violation was real: ADR-023 says an explicit owner decision outranks *every* gate state, and this was a state it did not outrank.

### Decision
Consult the owner's **gates-off flag** at the fail-closed point, before the deny — and *only* the gates-off flag:
- A pure predicate `owner_gates_off_fresh()` + the `GATES_OFF_FLAG` path are defined once near the top of the hook (depending on nothing resolved later). The early fail-closed branch and the normal skip site both call it, so the two can never diverge (DRY). The early branch emits its own minimal `jq` allow (the `allow_with_warning`/`log_skip` helpers are defined later in the file); the deny message, when the flag is absent, now names the gates-off flag as the fail-closed owner exit.
- **`--approve` is deliberately NOT honoured here.** It is keyed to a specific repo's exact diff, and at the fail-closed point the target repo can only come from the very command the scrub failed to sanitize. Resolving it to the session cwd would let a `git -C /other-repo commit -F - <<EOF` decoy pass on an unrelated cwd approval — the exact-diff guarantee broken (Codex's plan-review finding 1). gates-off is global ("skip ALL reviews this session"), needs no target, and is therefore the only owner escape that is *safe* before the target is known.
- Fail-closed stays the default when no flag is present (T64 unchanged: awk-fail + heredoc still denies).

Also corrected three stale references to the superseded `CODERV_GATE_OWNER_OVERRIDE` launch-env override, which a hook cannot read from a command prefix (ADR-023 already replaced it with `--approve`): the in-code comments at the CAP-ride branch, `two-brain-convergence.md`'s CAP-STOPPED escape wording, and — separately — the `context-gate` block message, which overstated a one-shot Stop nudge as the "only sanctioned move" when continuation is in fact allowed and the user is the final authority.

### Alternatives considered
- **Honour gates-off only at the fail-closed point (chosen)** — the one owner escape whose correctness does not depend on knowing the target diff; keeps ADR-023's exact-diff guarantee intact.
- **Also honour `--approve` via the session cwd** — rejected (Codex finding 1): passes a `git -C /other` decoy on an unrelated cwd approval; silently breaks the exact-diff scope.
- **Move the whole fail-closed block after target resolution** — rejected: the block exists *because* the command can't be trusted to resolve the target; you cannot safely resolve `-C <dir>` from text the scrub just failed on.
- **Leave it (accept the low reachability)** — rejected: a charter violation in a corner is still a charter violation; the owner ordered it closed.

### Consequences
- Positive: there is now **no gate block that can trap the owner in-band** — every deny path has an owner escape (fail-closed → gates-off flag; every other → `--approve`). ADR-023's "owner outranks every gate state" is now literally true. Regression-locked by T76 (suite 255 checks).
- Positive: the DRY predicate means the gates-off semantics (presence + 24h TTL) are defined once; the early and normal sites cannot drift.
- Trade-off: on an awk-less host the owner's fail-closed escape is the *global* gates-off flag, not the per-diff `--approve` — coarser than elsewhere. Accepted and documented: per-diff scope is impossible when the diff identity is unknowable, and the safe honest option is the switch that needs no identity.
- Revisit if: a future change makes the review target resolvable without trusting the command text at the fail-closed point — then per-diff `--approve` could safely apply there too.

---

## ADR-023: Owner authority is mechanically enforceable — per-diff recorded approvals outrank every gate state

**Date:** 2026-07-23
**Status:** accepted
**Decider(s):** owner (explicit requirement, verbatim in the session) + Claude

### Context
Live-fire on the alrafiq career-tone test branch exposed that the gate could overrule an explicit owner decision — the opposite of its charter. The owner's requirement, stated verbatim: *"I am the final authority; the gate advises and blocks autonomous agent decisions, but it must not overrule an explicit owner decision. When the gate raises a finding and I explicitly say approved, the agent must record my approval and execute the exact rejected diff without waiting for the cap, retrying through cache, or asking me to run terminal commands. The override must be scoped to that exact diff or finding, while the gate remains active for everything else."*

Two mechanical failures made that impossible:

1. **The documented owner exit was a dead end for everyone.** Deny messages instructed re-running the commit with `CODERV_GATE_OWNER_OVERRIDE=1`, but the hook reads that variable only from its own process environment — Claude Code's environment, frozen at session launch. An env prefix inside the command string (typed by the agent OR the owner via `!`) never reaches the hook. The "in-band pass" only worked from a bare terminal, where no hook runs and the variable is meaningless. A session burned a full round telling the owner to run a command the gate itself would then deny.
2. **The only working owner decisions were all-or-nothing** (kill switches, hook uninstall) — global, unscoped, and mostly requiring a relaunch or a terminal. There was no way to say "ship exactly THIS, keep reviewing everything else."

A note on attribution: any mechanism the agent can invoke, the agent could abuse — the hook file itself is agent-writable, so a hard cryptographic attribution boundary never existed. The real control is scope + audit + policy: key the authority to one exact diff, record the owner's words, make every use loud and logged, and forbid (in the prompt the gate itself emits) recording an approval the owner did not give.

### Decision
**`codex-review-gate.sh --approve <repo-dir> "<the owner's words>"`** — the owner-approval recorder:

- **Exact-diff scope, mechanically enforced:** the approval key is a sha256 of repo@HEAD + the current outgoing diff (worktree delta + untracked — computed by the same `collect_outgoing_diff`/`approval_key` functions the review path hashes with, so writer and reader can never diverge). One changed byte → different key → normal review. Other diffs, other repos, later commits: gate fully armed.
- **Top precedence:** the review path checks the approval marker before the round cache, cap, ceiling, and security-escalation states, and before any Codex call. An explicit owner decision is final — it outranks even a ceiling `[security]` stop (proven by test T75).
- **Single-use + auditable + loud:** the marker stores the owner's quoted words and timestamp; it is consumed on the pass; unused markers are swept by the existing 24h TTL. The allow is a loud warning that quotes the approval and restates that open findings remain unresolved and must be surfaced (transparency rule). Every record and every use emits an event to the live-loop log.
- **The deny messages teach the exit:** every deny (ordinary round-1, cap-reached, ceiling) now names the real flow — owner says "approved" in chat → agent records it with `--approve` → identical commit passes once. No cap-waiting, no cache tricks, no terminal commands for the owner.
- **Demoted:** the `~/.claude/coderlap/gates-off` flag file (built earlier the same day) stays as a documented EMERGENCY switch only (24h TTL, loud) — explicitly not the primary owner exit, per the owner's requirement. The legacy `CODERV_GATE_OWNER_OVERRIDE` launch-env check remains for compatibility but is superseded.

### Alternatives considered
- **Per-diff recorded approval, top precedence (chosen)** — matches the owner's requirement word for word; scoped, auditable, self-expiring.
- **Global 24h gates-off flag as primary** — built first, rejected by the owner: it disables review for everything, not the one decided diff. Kept as emergency-only.
- **Command-prefix override parsing (`CODERV_GATE_OWNER_OVERRIDE=1` in the command text)** — implemented, then removed the same session: it only resolved the cap-escalation state (not an ordinary deny), carried no recorded owner quote, and was redundant next to `--approve`.
- **Keep env-only override** — provably nonfunctional in-band (the failure that triggered this ADR).

### Consequences
- Positive: "owner says approved → it ships, exactly that, once" is now a mechanical guarantee; the gate can no longer overrule the owner; the loop's owner-escalation exit terminates in one chat sentence; regression-locked by tests T74–T75 (suite now 249 checks).
- Negative / trade-off: the recorder is agent-invocable, so enforcement of "only on explicit owner approval" is policy + audit (quoted words in the marker, loud allow, event log), not cryptography. Accepted: see attribution note above.
- Revisit if: Claude Code exposes user-attributed input to hooks — a real attribution boundary would let `--approve` demand proof the words came from the human.

---

## ADR-022: Quality gate by default, deep security review by explicit opt-in — the severity-policy split that ends the trickle

**Date:** 2026-07-23
**Status:** accepted
**Decider(s):** owner + Claude (plan converged with Codex, LGTM round 2)

### Context
Even with ADR-019's memory + cap + ceiling, the gate kept "behaving like a
penetration tester on every commit." The round-8/9 shell-lexer saga was the
proof: fixing the review-target hijack spawned eight review rounds, each
surfacing one more *genuinely real but exotic* shell-grammar corner
(`$'...'` ANSI-C quoting, mid-word `#`, backtick segments, …). Every finding
was tagged `[security]`, `[security]` can never be marginal, so each one
BLOCKED — and the surface of "ways a determined shell author could craft
pathological input against a local guardrail" is infinite, so the trickle
could never converge. An earlier direction this session (delete the lexer /
cwd-only target resolution) was explored and abandoned: it just relocated the
trickle to redirect-vector enumeration (`-C` → `--git-dir` → `GIT_DIR` → …).
The bug was never the lexer. It was the SEVERITY POLICY: exotic-input
defense-in-depth findings carried the same blocking weight as a real
reachable auth bypass.

### Decision
Split the policy along REACHABILITY + IMPACT, never craftedness or rarity:

1. **Default mode = engineering QUALITY GATE.** The reviewer brief prioritizes
   correctness / regressions / data-loss / broken logic / realistic security
   and explicitly forbids recursive hardening against exotic input. A new
   MARGINAL tag `[hardening]` marks a security-relevant weakness with NO
   credible reachable high-impact path (the shell-grammar-corner class).
   `[hardening]` is FORBIDDEN when a realistic attacker can reach the path —
   real injection is usually crafted input and must still block.
2. **Marginal never blocks in default mode.** A marginal-only review
   (`[hardening]`/`[edge]`/`[theoretical]`) ALLOWS in ROUND 1 — not cap-gated —
   with the findings surfaced under a labeled **"Optional Security Review
   (non-blocking)"** section (transparency preserved: surfaced, never dropped).
   A normal dev commit with no realistic-impact defect converges in ONE round.
3. **Impact subordination governs ALL marginal tags:** a rare-but-reachable
   high-impact defect must take a MATERIAL tag; `[edge]`/`[theoretical]` may
   not downgrade it any more than `[hardening]` may.
4. **Deep security review is an explicit opt-in:** `CODERV_GATE_SECURITY=1`
   (exported by `/ship --security`) flips the reviewer to the full adversarial
   brief (fuzzing, parser hardening, exotic shell grammar) AND makes
   `[hardening]` MATERIAL. The pre-0.14.0 cap-gated marginal semantics apply
   unchanged in this mode.
5. **Scope: policy only.** The 0.13.1 shell lexer stays in the tree, active
   and fully tested — its findings class just stops blocking by default.
   Realistic `[security]`/`[data-loss]`/`[correctness]` blocking, the cap /
   ledger / ceiling machinery, and the ceiling security escalation are all
   unchanged.

### Alternatives
- **Keep perfecting the lexer round-by-round** (rejected) — the KI-002-class
  loop with an infinite surface; round 9 was already the scoped "once and
  done" pass and the gate still had more.
- **Delete the lexer / cwd-only target resolution** (explored, de-scoped by
  owner) — relocated the trickle to redirect-vector enumeration; same
  infinite-surface trap, minus the protection the lexer already provides.
- **Owner-override each trickle** (rejected) — makes the human the loop's
  off-switch again, the exact failure ADR-019 exists to prevent.

### Consequences
- Positive: normal dev commits converge in one round; exotic findings stay
  visible (Optional section) instead of blocking; deep review still exists,
  on demand, where it belongs; the terminal state is genuine convergence.
- Trade-off: in default mode a finding the reviewer *mis*-tags `[hardening]`
  will not block. Mitigated by the impact-subordination rule (reachability
  wins, stated in the prompt as the governing rule), untagged-defaults-to-
  material, and the commit still carrying the finding to the owner verbatim.
- Supersedes: the abandoned cwd-only / lexer-deletion direction (never an
  ADR; recorded here so it is not re-explored).
- Verified by: `tests/gate-cap.sh` T65–T73 (round-1 hardening allow, security/
  correctness still block, opt-in flip, mixed-severity routing with the
  marginal findings re-listed verbatim under the Optional section, prompt
  flip, and mode-flip cache isolation); the legacy T1–T64 suite runs pinned
  to security mode and proves the pre-0.14.0 machinery unchanged.
- Refinement from this ADR's own pre-commit review (Codex round 1): the
  review MODE joined the gate's cache identity — a default-mode allow marker
  (`lgtm`/`optional`) must never satisfy an explicit `--security` rerun of
  the identical diff, and a security-mode verdict must not pre-answer a
  default run. Each mode owns its own review, marker, and retry semantics.

---

## ADR-021: The gate is the ONLY sanctioned Codex diff-review loop — hand-run `codex exec` is banned

**Date:** 2026-07-22
**Status:** accepted
**Decider(s):** owner + Claude

### Context
ADR-019 gave `codex-review-gate.sh` memory (findings ledger), project context, and a round counter + cap, so the Claude↔Codex loop self-terminates. It works — but every one of those properties lives **inside the gate** and only applies to rounds that go **through** it. On alrafiq's career-floor regex, Claude drove Codex by hand — a bare `codex exec` per "round" — outside the gate. The gate's log proves it: exactly one gate round (`"round":1`) was recorded, then a hand-driven R2/R3/R4/R5. A manual `codex exec` touches no ledger (so each round re-discovers the space cold), increments no counter (so the cap of 3 never fires), and has no ceiling (so it loops until the human ends it). It is the pre-ADR-019 memoryless trickle reproduced by hand — the exact bleed ADR-019 was built to kill, re-created by bypassing it. The finding-per-round was even *legitimate* (each regex patch had a real new hole), which is precisely why only the CAP — not a "perfect" review — can end such a loop.

### Decision
Make the gate the single sanctioned adversarial diff-review path, and forbid hand-driven Codex review of a diff:
1. **`two-brain-convergence.md`** gains a top "THE ONE RULE THAT MAKES THE CAP REAL" section: the anti-loop guarantee only counts rounds through the gate; a manual `codex exec` on a diff is banned; if you catch yourself typing it — STOP and run `/ship`. A new real finding per round is EXPECTED; the CAP, not a perfect first review, ends the loop.
2. **`~/.codex/AGENTS.md`** (and the `templates/codex-AGENTS.md` seed for fresh installs) gains a "gate is the only sanctioned review loop" bullet under *Your role*: if Codex is invoked by hand to "do one more round" on a diff, it points back to the gate instead of becoming an uncapped manual loop.
3. The sanctioned `codex exec` call sites are unchanged — they live INSIDE `/ship` Step 4.5 and the commit hook, which own the ledger/counter/cap. Only *ad-hoc* hand invocation is banned.

### Alternatives
- **Add a hook that hard-blocks any `codex exec` outside the gate** (deferred) — a shell wrapper could refuse `codex exec` unless an in-gate env sentinel is set. Rejected for now: `/ship` and the hook legitimately call `codex exec`, and a global block risks false positives on future sanctioned uses; the documented rule + Codex-side self-refusal covers the actual failure (Claude hand-looping). Revisit if the rule alone proves insufficient.
- **Do nothing — treat it as a one-off operator error** — rejected: the whole ADR-019 investment is defeated by one habit; the bypass must be written down as a rule, not left to memory.

### Consequences
- Positive: the ADR-019 cap becomes un-bypassable in practice — every diff review now flows through the counter, so round 3 reaches CAP-STOPPED and the owner decides, instead of an unbounded hand-loop. Closes KI-002.
- Trade-off: the ban is enforced by documentation + Codex self-refusal, not (yet) by a machine block. A determined hand-run still works; the guard is a rule, not a lock. Acceptable because the failure was a habit, not a hostile actor.
- Deployment: same as ADR-019 — the `templates/` seed reaches new projects on install; `~/.codex/AGENTS.md` is already live on this VPS. Existing installs inherit the rule when their `~/.codex/AGENTS.md` is refreshed.

---

## ADR-020: REJECTED — do NOT downgrade a pre-ceiling gate `deny` to `ask`

**Date:** 2026-07-22
**Status:** rejected
**Decider(s):** owner + Claude

### Context
An uncommitted working-tree change (author/session unknown; discovered 2026-07-22) flipped `codex-review-gate.sh` so that every material finding **below the ceiling** emitted `permissionDecision: "ask"` (the owner approves or declines) instead of `"deny"` (a hard block that forces a retry). The stated appeal: stop the gate from *interrupting* routine work with hard blocks, since ADR-019 already reserves the durable hard stop for a ceiling `[security]`/`[data-loss]` finding. It shipped with a comment citing "ADR-020" but no ADR text existed, and it passed the test suite.

### Decision
**Rejected. The pre-ceiling verdict stays `deny`.** The change was reverted (`git checkout hooks/codex-review-gate.sh tests/gate-cap.sh`).

The gate's own adversarial review (round 2) caught it, and the finding is correct: `ask` below the cap **breaks the ADR-019 invariant** stated verbatim in `two-brain-convergence.md` line 182 — *"ADR-019 ... never weakens a material block below the cap"* — and line 113 — *"round >= cap AND >=1 material open → DENY."* The whole convergence mechanism depends on a below-cap material finding being a **retry-deny**: that is what forces Claude to fix the batch and re-submit, which is how genuine agreement is reached. Downgrade it to `ask` and a **round-1 material finding can be waved through on a reflexive "yes,"** so the converged-retry loop never has to run — the gate stops being a gate below the ceiling. The change silently contradicted ADR-019 without superseding it.

### Alternatives
- **Keep `ask` below the ceiling** (rejected — this ADR) — defeats ADR-019's retry loop; a real bug can land on a fast "yes." If the hard-block friction is genuinely too high, the correct fix is to make Codex raise *fewer, higher-confidence* pre-cap findings (tune the reviewer threshold), NOT to weaken the verdict that forces convergence.
- **Supersede the ADR-019 below-cap invariant deliberately** — not taken: no rationale was offered strong enough to trade away the loop's forcing function. Left on the record here so a future session that wants `ask` must first argue *against this ADR* and edit line 182, rather than silently re-flipping the verdict.

### Consequences
- The ADR-019 invariant stands: pre-ceiling material findings `deny`; only a ceiling `[security]`/`[data-loss]` finding is a durable owner hard-stop. `permissionDecision` is `deny` in all three gate branches (verified: `hooks/codex-review-gate.sh` lines 677, 1539, 1547).
- This ADR number is spent on a rejected change (per "never delete history" — a rejected decision keeps its slot with the reasoning). ADR-021 is the accepted anti-hand-loop decision.
- Prevention: a below-cap `ask` in the gate is now a documented regression (see KI-002's sibling reasoning); the gate's own review flags it, and this ADR explains why.

---

## ADR-019: The commit gate gets memory + project context + a convergence ceiling so the Claude↔Codex loop self-terminates without the human

**Date:** 2026-07-21
**Status:** accepted
**Decider(s):** owner + Claude (design grounded by a Plan agent; rules in `docs/planning/two-brain-convergence.md`)

### Context
`codex-review-gate.sh` reviews a **cold diff** on every recommit through a fresh, **memoryless** `codex exec` that can see only the diff — never the surrounding code, never what it already raised. Two consequences bled the community's tokens: (1) it **re-raises** a finding Claude already resolved, because it never learns the disposition; (2) it **invents false findings** the real code disproves, because it cannot read that code. Each such finding is a new deny → another round → and the old round cap only **escalated to the human**, making the owner the loop's off-switch on every project. The owner's framing: *"I need result when you agree with Codex 100%. I don't want to decide for something regarding coding."* — the terminal state must be **genuine convergence**, not a human adjudicating code. ADR-018 shipped the pre-commit half; ADR-019 is the gate-side permanent fix.

### Decision
Add four inputs to the commit gate (inherited by `/ship` Step 4.5 and `/before` Step 5.6 — rules defined once in `two-brain-convergence.md`, DRY):
1. **Findings ledger (memory)** — a per-(canonical repo, HEAD) file beside `ROUNDS_FILE` in `$CACHE`, same flock-guarded / no-delete / 24h-swept lifecycle. Each reviewed finding is fingerprinted (hash of its normalized text) and recorded; prior findings are fed into the next round's prompt with an instruction not to re-raise a finding unless the **current** code still exhibits it (cite the line). Best-effort: an IO/flock failure yields an empty prior-findings block, never a block.
2. **Project context** — `codex exec` runs from the repo cwd (`cd "$DIR"`) under `-s read-only`, is given the changed-file list, and is told to READ the real code before judging — killing false findings. The owner approved sending surrounding project files to OpenAI (same trust boundary as the diff, wider).
3. **Convergence pressure** — a finding first appearing at round ≥ 2 is tagged `[LATE]` and must justify itself; the prompt defines *converged = LGTM with prior findings + real code in front of you*, not "no new finding this round."
4. **Ceiling** — above the existing soft cap (`CODERV_GATE_ROUND_CAP`, default 3) sits a hard `CODERV_GATE_ROUND_MAX` (default 5) and `CODERV_GATE_DIFF_BUDGET` (cumulative bytes-reviewed, default 800000). At the ceiling only a still-open `[security]`/`[data-loss]` may BLOCK — via the existing owner-override escalation, i.e. the gate refusing to auto-merge a security hole. Every non-security finding must have converged; a routine `[correctness]`/untagged residue at the ceiling is surfaced but **allowed-with-caveat**, so the loop self-terminates rather than escalating ordinary code to the human.

### Alternatives
- **Keep escalating every capped loop to the owner** (chosen: rejected) — that IS the bleed; it makes the human the off-switch on every project. The ceiling now auto-terminates non-security residue.
- **Diff-only review, no project context** — rejected: it leaves the false-finding half of the bleed unfixed; the owner explicitly approved the wider trust boundary to close it.
- **Store dispositions (fixed/rejected) in the ledger, not just fingerprints** — deferred: the gate cannot know a finding's disposition (that is Claude's adjudication, off-gate). Recording the fingerprint + text and telling Codex "you raised this; re-raise only if the code still shows it" achieves the suppression without the gate guessing state it doesn't own.
- **Lower the ceiling to the soft cap** — rejected: the soft cap (3) is where marginal residue already auto-allows; the point of ROUND_MAX (5) is to give real convergence a couple more rounds before the hard stop, since with context+memory most loops end at round 2-3.

### Consequences
- Positive: with memory + real code, Codex reaches a genuine LGTM in ~2-3 rounds, so the loop terminates on **convergence**, not on a human. Escalate-to-human is reserved for a real unmitigated security/data-loss hole at the ceiling — a safety decision, not a code decision.
- Trade-off: surrounding project files are sent to OpenAI on every review (owner-approved; same trust boundary as the diff). And the review call does more work (reads code) — slower per round, but far fewer rounds.
- Trade-off: the ledger and context are **best-effort**; every failure path degrades to the pre-ADR-019 behavior (empty prior block, diff-only) and never blocks a commit. Fail-open and the kill switches (`CODERV_GATES_OFF`/`CODEX_REVIEW_OFF`) and the `CODERV_LOG_OFF` contract are untouched; the gate stays the sole author of its trust marker (ADR-018).
- Deployment: "built" is not "live." A project gets the fix only after its user `git pull`s the toolkit and re-runs `install.sh` (which re-copies the hook). Until then their gate keeps the old trickle — the CHANGELOG/README says so.
- Revisit if: a project needs a disposition-aware ledger (Claude writing fix/reject back into it) — the fingerprint substrate here is what that would build on.

---

## ADR-018: The Claude↔Codex argument moves to a pre-commit convergence loop in `/ship`; the gate stays the sole author of its trust marker

**Date:** 2026-07-21
**Status:** accepted
**Decider(s):** owner + Claude (plan converged over 5 Codex rounds via `/before` Step 5.6)

### Context
Every project was hitting the commit gate's `commit → deny → fix → commit` loop for hours. The owner's words: *"why do the findings never run out?"* Root cause: `codex-review-gate.sh` reviews a **cold diff on every recommit** and keeps no memory of prior findings' *content* (only the diff-HASH cache + a round counter), so a thorough reviewer trickles a **new** finding each commit and the owner had to end every loop by hand. The owner's ask: make it behave like the `/before` plan loop — Claude and Codex argue to 100% agreement **first**, all findings at once, and only **then** commit.

### Decision
- `/ship` gains **Step 4.5 — a pre-commit convergence loop**. Each round: (a) assemble the diff snapshot **exactly as the gate does** (`git diff HEAD`, `--cached` fallback, plus untracked via `git diff --no-index`) and hash it to `SNAP_HASH`; (b) run **one exhaustive Codex pass** on the same serialized-stdin channel the gate uses, the reviewer told that holding a finding back for a later round is a **failure**; (c) batch-fix or rebut every finding **without committing**; repeat.
- The loop ends in exactly one of the three shared end-states (`docs/planning/two-brain-convergence.md`): **CONVERGED** (requires BOTH an empty unresolved-**material** set AND `SNAP_HASH` == a freshly re-assembled diff hash — an empty finding set alone is not convergence, because the fixes themselves changed the bytes and that new diff is unreviewed), **CAP-STOPPED** (numeric round cap, default 3 / `CODERV_GATE_ROUND_CAP`, reached with the current snapshot uncertifiable → surface every open finding, owner decides), or **REVIEW-UNAVAILABLE** (Codex down after one retry → fail open, never block, score the gate ✖, owner decides).
- **`/ship` NEVER writes the gate's trust marker** (`~/.claude/coderlap/codex-reviewed/$HASH`). The commit-time gate runs its **own** independent review; a converged diff just makes that a fast LGTM instead of a fresh argument. The redundant second review **is** the safety property.

### Alternatives
- **Let `/ship` write the gate's `lgtm` marker after it converges** (chosen: rejected) — a seam audit proved this UNSAFE: a marker `/ship` writes is indistinguishable from a gate-written one, so any `/ship` failure would silently **disarm the backstop**, and a plain write can **race** the gate's monotonic `denied` marker. The gate stays the sole author of its marker.
- **Keep only the commit-time gate, no pre-commit loop** — rejected: that IS the status quo that trickled findings and burned the owner's hours; phase 2 exists precisely so phase 3 is a fast confirmation of an already-agreed diff, not the place the argument happens.
- **Converge on `git diff HEAD` alone (untracked omitted)** — rejected: `/ship` would converge on an incomplete diff and the gate would then find the untracked remainder cold. Same-bytes-as-the-gate is an invariant.
- **Non-numeric "twice-rejected-identical" early-exit as the only bound** — rejected as the *sole* bound: new findings each round never trip the identical rule, so a numeric cap is the real termination guarantee; the identical-rejection rule sits on top of it.

### Consequences
- Positive: the Claude↔Codex argument resolves once, before the commit, so the commit-time gate is a fast confirmation rather than a fresh cold-diff review — the trickle that cost the owner hours stops at the source.
- Positive: the backstop is untouched — the gate remains the sole author of its trust marker, so no `/ship` failure can disarm it and no write can race its `denied` marker.
- Trade-off: `/ship` now spends Codex tokens on a pre-commit pass. That is the point (front-load the argument) but it is real cost; fail-open keeps it from ever blocking a commit when Codex is down.
- Trade-off: this reduces the *frequency* of gate trickle but does not remove the gate's own memorylessness — a cold-diff gate can still raise a fresh finding at commit time. **ADR-019 is the permanent fix** (give the gate a findings ledger + project context + a convergence ceiling); ADR-018 is the pre-commit half that ships first.
- Revisit if: ADR-019 lands and makes the commit-time gate itself converging — Step 4.5 then becomes belt-and-suspenders rather than the primary defense.

---

## ADR-017: Every gate event carries a unique `eid` + an exchange `xid`; skips emit `gate_skipped`

**Date:** 2026-07-21
**Status:** accepted
**Decider(s):** owner + Claude (plan hardened over 4 Codex rounds)

### Context
The owner wanted the `coderv-loop` viewer to show **all** gate activity across **all** projects — not just full reviews. Two gaps blocked that: (1) the three real skip *decisions* (docs-only, empty-diff, merge/rebase-incoming) exited before any `log_event`, so a skipped commit was invisible; (2) events carried no identity, so the viewer couldn't group an exchange under concurrent/interleaved commits, and SSE reconnect-replay double-counted every stat. A single per-user log already interleaves all repos (each event carries `repo`), so multi-project support needed no new plumbing — only correct identity + skip visibility.

### Decision
- `log_event` now stamps two fields on every event: `eid` (per-event identity) and `xid` (exchange id). `eid = <epoch_ns>-<pid>-<urandom-hex>` — on a healthy host (epoch-nanoseconds + pid + `/dev/urandom`) it is strongly unique across concurrent gate processes without a shared sequence; on a *degraded* host it degrades to **best-effort probabilistic** uniqueness (see the Hardening note), never an absolute guarantee. `xid` is the review's existing diff `HASH` (`sha256(repo@HEAD+diff)`), set once via `EVENT_XID` so all 18 review-path call sites inherit it (DRY, no call can miss). The viewer de-dupes on `eid` alone and groups by `xid`.
- A new `gate_skipped` event (actor `system`, payload `{reason, subcmd, files?}`) fires on the three real skip *decisions* only. Each mints one `eid` and derives `xid = skip-<reason>-<eid>` from it (the two stay correlated). Repo label is canonicalised (`readlink -f` of the toplevel) on the skip, review, and cached-retry paths so one repo never splits across two project names.
- Exchange status is the **latest terminal outcome** per `xid`: a denied-then-passed retry counts once as passed (recovered), never as both.

### Alternatives
- **Positional grouping ("until the next commit_attempt")** — rejected: Codex showed it misattributes late events under concurrent same-repo commits. A gate-stamped `xid` is interleave-proof.
- **Dedup by `(xid,type,ts)`** — rejected: `ts` is 1-second resolution, so multiple findings / rapid skips in the same second would collapse. A unique `eid` is required.
- **`eid = date +%s%N` alone** — rejected: not unique across concurrent processes or safe under clock adjustment; pid + urandom close it without a shared lock.
- **Emit on every early exit (kill-switch / missing-jq / non-git)** — rejected: those are *gate-didn't-run* infrastructure exits, not skip *decisions*; firing on them spams the loop with noise unrelated to the two-brain exchange.

### Consequences
- Positive: every commit (reviewed, retried, or skipped) is now visible and correctly grouped in the viewer, across all projects; stats survive reconnect. The `log_event` contract (never influences allow/deny, swallows failures, honours `CODERV_LOG_OFF`) is preserved.
- Trade-off: adds one `mint_eid` (a `date`+`od` call) per event, including on the docs-only handoff hot path — negligible, same order as the existing `commit_attempt` log.
- Hardening: `mint_eid` swallows a missing/failing `date`, `od`, or `tr` (each subshell has `2>/dev/null` + a fallback: time → `$SECONDS`-derived ns; entropy → a token from a **successfully-created** `mktemp` file that is then removed, and only if `mktemp` *also* fails → `$RANDOM$RANDOM`), so the logging-is-invisible contract holds even on a degraded host and the eid never collapses to the empty `--$$--` shape. The degraded entropy is **best-effort probabilistic**, not a hard guarantee: `mktemp`'s pathname randomness is, in practice, far stronger than `$RANDOM`'s 15-bit PRNG (which under PID reuse / PID namespaces could otherwise collide two events in the same second and make the viewer de-dup a real event), but once the temp file is removed the name could in theory be reissued — neither `mktemp`'s entropy source nor its suffix strength is a portable contract. Guarded by `tests/mint-eid.sh`: cases 1–4 exercise `mint_eid` in isolation; case 5 drives the **whole hook** through a docs-only skip on a degraded host (asserting a silent allow, zero hook stderr, and exactly one correlated `gate_skipped` event); case 6 regression-protects the `mktemp` entropy fix (fails if it reverts to bare `$RANDOM$RANDOM`); case 7 covers the empty-diff skip path; case 8 pins the both-fail `$RANDOM$RANDOM` last-resort branch to its deterministic value; and case 9 drives the merge-incoming skip path (allow-with-warning: non-empty JSON with a `systemMessage`, no deny, exit 0, and exactly one correlated `gate_skipped/merge_incoming` event).
- Revisit if: multi-writer workflows make the concurrent same-diff race in ADR-016 material — the `xid`/`eid` identity model is the substrate a real fix would build on.

---

## ADR-016: The concurrent same-diff review race in codex-review-gate is an accepted, documented hardening opportunity — not a release-blocking defect

**Date:** 2026-07-21
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
A Codex review of the gate hardening work flagged a concurrency bug (finding 2): the cache fast-path at `codex-review-gate.sh` reads the marker and exits *without a lock*, while the actual `codex exec` review runs much later — with no lock spanning the check-then-review window. So for the same diff (the cache key is `sha256(repo + HEAD + diff)`), a fast LGTM review can publish `lgtm` and let an identical-diff retry take the fast-path and pass, *while a concurrent review of that same diff is still running and destined to deny*. The deny marker still lands afterward (the finding-1 monotonic fix preserves it), but the commit has already gone through.

The mechanism is real. A deterministic harness (`scratchpad/repro-finding2.sh`) drives the unmodified hook via the suite's fake-codex shim + `FAKE_DELAY` and reproduces the bypass 5/5 runs: retry returns ALLOW while the concurrent review returns DENY. (Two traps found along the way: the verdict is a `permissionDecision:"deny"` JSON on stdout at exit 0 — not an exit code; and the slow review must start first so both clear the empty cache before either publishes.)

The deciding factor is the operating model, not the mechanism. The workflow is documented **single-writer, serialized-review** (`AI-WORKFLOW-PLAN.md`): one Claude session issuing git commands, and Claude Code runs PreToolUse hooks synchronously and serially, so one session cannot have two commit reviews in flight. Two concurrent reviews of a byte-identical diff at the same HEAD only arise off-model — e.g. two sessions or a human+agent committing the same diff on one repo within the review window.

### Decision
Treat finding 2 as an **accepted, documented hardening opportunity**. Do **not** add per-hash review-lifecycle locking or any other concurrency machinery to the release path at this time.

### Alternatives considered
- **Accept + document, no lock** (chosen) — the race is unreachable under the supported single-writer model; the fix would serialize an expensive `codex exec` under flock and add lock-timeout failure modes to the commit hot path, buying safety only for a configuration the workflow forbids.
- **Add a per-hash lock over check→review** — closes it fully, but serializes the slowest step of every commit and adds new failure modes to the release path for an out-of-model scenario. Rejected as cost > benefit today.
- **Locked "review pending" sentinel** (lighter: write a pending marker before `codex exec` so cached retries wait/deny until in-flight reviews resolve) — the leading candidate *if* this is ever revisited, but still unjustified complexity for a race that can't occur in-model. Deferred, not adopted.

### Consequences
- Positive: the release path stays simple — no lock contention, no lock-timeout edge cases on every commit — and the material half of this work (finding 1: equal-round marker downgrade, reachable even in the sequential retry path) is fixed on its own merits.
- Trade-off: under an *off-model* multi-writer setup, one diff that a concurrent review would block can slip through once; the deny marker still lands, so the next retry is correctly blocked (not silent-forever).
- Revisit if: the project adopts multi-session / multi-writer workflows on a shared repo — then reopen with a dedicated design proposal (the "review pending" sentinel is the starting point). The repro at `scratchpad/repro-finding2.sh` is the executable evidence to fold into that work.

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
