# Changelog

All notable changes to the CoderLap Docs Toolkit.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [0.12.0] — 2026-07-20

### Added
- **The architecture-audit system map is now a draw.io-style interactive canvas, standardised across every project** (builds on ADR-014). A new frozen template `skills/coderv/systemmap.template.html` is the single rendering engine: each audit fills one data block (the `GRAPH` object — `meta` header, `nodes`, `edges`, `findings`), and the engine — canvas, styling, pan/zoom, emoji markers, click-to-trace — is never edited per project, so every project's map looks identical.
  - **Draw.io feel:** the stage grows to the graph's natural extent (arbitrarily tall/wide) inside a pan-and-zoom viewport — never scaled down to cram it onto a page. Drag-to-pan + wheel-zoom for pointer users; a toolbar (**Fit** / **Width** / **+ / −**), arrow-key panning, and `Esc`-to-clear for keyboard/non-pointer users (a11y). Loads at Fit.
  - **Emoji markers so state reads at a glance:** 🟢 live · 🌐 external · ⏸ parked/not-firing on nodes; 🔴 P0/P1 · 🟡 P2/P3 on gap edges. State is encoded in form (a coloured stripe) as well as colour, never colour alone.
  - **One canonical payload — authored once, rendered twice:** the assembled node/edge/finding set is the single source; the audit writes the report's `mermaid` fence and the Artifact's `GRAPH` from that one set in the same step, so they stay identical. The `mermaid` fence is the durable static fallback (renders anywhere, diffs cleanly, no browser needed) — pan/zoom and click-to-trace are interactive-Artifact-only.
  - **The map and the findings list are two views of one open set:** clicking (or keyboard-activating) a node highlights its gap, traces the path on the map, and spotlights + scrolls the matching finding into view in the rail; clicking a finding highlights its nodes and edges. A node in several findings cycles through them on repeated activations.
  - **Interactive runs always OFFER the full map** with an explicit yes/no prompt after the report is written; on no, the `mermaid` fence is the deliverable.

### Fixed
- **System-map canvas: dragging to pan no longer flash-highlights the whole diagram or selects text.** A drag-release is no longer treated as a click (only a genuine click on blank canvas clears a trace), and the canvas sets `user-select: none` so panning never triggers native text selection.
- **System-map canvas: every repo-controlled value is now rendered safely.** All node/edge/finding strings **and the header** (project, context, base, scores) live in the `GRAPH` data and are written via DOM `textContent` — never HTML substitution — so `<`, `&`, and quotes display as literal characters and can never inject markup. A `<` that must appear inside a string is written with its unicode escape so a closing `script` sequence can't break out; values render losslessly (a name `<worker>` shows as `<worker>`).
- **System-map canvas: large graphs load fully fitted, and empty graphs don't crash.** The Fit action can now shrink below the interactive zoom floor so a very large map loads fully visible instead of cropped, and an empty node set falls back to a usable blank canvas instead of `-Infinity` dimensions.
- **System-map canvas: edges between the same node pair no longer collide.** Each edge is keyed by a unique index, so multiple relationships between the same two nodes (even of the same severity) all render and click-to-trace highlights the right one; a finding references an edge by node pair (`from->to`) or a specific relationship (`from->to#rel`).

## [0.11.0] — 2026-07-19

### Added
- **Architecture & integration audit — a new `/coderv` shape woven through all seven commands** (ADR-014). A whole-project health investigation that answers three questions a diff-level reviewer can't: is the code well-structured (layering, coupling/cohesion, duplication, module boundaries, dead code), is everything wired to something live (integration wiring), and is anything left running that shouldn't be (service liveness — "a server left alone"). Driven by a new `skills/coderv/architecture-review.md` run-book:
  - **Pipeline:** read-only scout → **parallel fan-out over 7 dimensions** → dedup by `file:line`+principle → **Codex adversarially verifies each finding** through the exact serialized-stdin channel `codex-review-gate.sh` uses (DRY with the two-brain seam) → scored **P0–P3** report at `docs/ARCH-REVIEW-<date>-<time>.md` (always timestamped, never overwritten, full-SHA base-commit stamp, open findings carried forward so the newest report is the complete open set). It **advises, never auto-fixes** — on one yes the top finding hands into the normal `/before → work → verify → /ship` pipeline.
  - **Honest degradation, four states:** with observed runtime (`ss`/`pm2`/`nginx -T` all ran) both live dimensions run; with partial runtime, checks gate per source that actually ran (source exit status verified, output sanitized at collection); with only a `SERVER-MAP.md` registry, wiring is checked against the registry but service liveness does NOT run (a static registry can't reveal an orphan process or a dead listener); with neither, both are skipped and the report says *"code-only audit; integration wiring and service liveness NOT checked"* — never a claimed check that couldn't run (same rule as the gate's "drift NOT checked"). Codex-refuted findings are dropped from the report but footnoted, never silently discarded.
  - **The weave (nothing left, everything connects):** `/coderv` routes the shape and hands findings to the fix pipeline; `/before` reads the newest review as prior art so new work plans around known fragile spots; `/ship` flags any diff touching a file with an open P0/P1 finding and asks the reviewer whether the change addressed or worsened it (regression caught at every `/ship`-run commit — the check lives in the `/ship` checklist, not the gate hook); `/session` surfaces open P0/P1 findings so they don't rot; `/lint` flags a review whose `Base commit:` stamp predates structural changes as maybe-stale; `/docify` links the newest review from `architecture.md`; `/decision` fires when a structural finding is acted on. The audit finds a problem once and five other commands keep it in view until it's fixed.
  - A high-quality rendered **workflow diagram** (Artifact) plus a versioned **Mermaid** diagram in the run-book document the flow. Surface stays at 7 commands — the audit is a shape, not an eighth command (ADR-014 rejects slot 8 against the `never-unrequested` bar).

### Changed
- **`/coderv` now acts before it asks** (ADR-013). A bare `/coderv` discovers project state itself (git, docs freshness, last handoff) and proposes the next move instead of asking "what do you want?"; a vague target spawns a read-only scout before planning; the verify step is always on.
- **`codex-review-gate` loop events enriched for the dashboard** — each review beat now carries the review duration, and each finding carries its `file:line`, so the coderv-loop viewer can show where a finding points without opening the transcript.

### Fixed
- **`install.sh` gate roster folded into one source of truth.** Install and uninstall previously each typed the four gate-hook names separately — a drifted list could leave an orphaned hook config behind on uninstall. Both paths now read the same roster.

## [0.10.1] — 2026-07-19

### Changed
- **`/session` handoff now hands the next session its exact starting point.** The closing template prints the absolute repo path (the nearest ancestor holding `CLAUDE.md`) plus the queued "next session should probably" items inline with the `/session last` pointer — so a fresh session knows where to `cd` and what's parked before it reads anything. Skill body only; no behaviour change to the saved handoff file.

### Fixed
- **Doc lint pass (4 findings):** `docs/architecture.md` said the toolkit adds "three gate hooks" — corrected to **four** (+ADR-008); the three `/docify`-generated docs (`overview.md`, `architecture.md`, `skills.md`) carried a stale `fbb1954` (v0.3.8) provenance banner while their bodies describe v0.10.0 — banners now note they are hand-maintained and last verified against `f8a0314`; and ADR-008 in `docs/DECISIONS.md` read `Status: accepted` yet still carried a "pending owner veto" trailer (it shipped in v0.9.0) — trailer corrected. A fifth finding (KI-001's deferred prevention rule) was an owner-accepted open follow-up, not rot — left as-is.
- **`docs/SESSIONS.md` rotated** — grown past the ~500-line threshold, its 7 oldest entries (2026-07-17 gap-scan back to 2026-04-24 docify) moved byte-identical into new `docs/SESSIONS-ARCHIVE.md`, per the `/session` rotation rule, with a pointer left behind.

## [0.10.0] — 2026-07-19

### Added
- **Two-model workflow now reviews the PLAN, not just the diff** (ADR-009). Independent judgment moves one phase earlier, to where a wrong approach is cheapest to fix:
  - **`/before` design-phase Codex loop** (new step 5.6). Claude drafts the plan, then pipes it to Codex via the gate's exact one-payload stdin channel for an adversarial review (gaps, risks, wrong approaches — findings only, no rewrite). Claude adjudicates and converges to one of three terminal end states (a fourth label, *running*, just means "loop again"): **CONVERGED** (Codex LGTM — empty unresolved-material set), **CAP-STOPPED** (3 rounds, ≥1 material finding open), or **REVIEW-UNAVAILABLE** (Codex timed out/auth-lapsed after one retry — never treated as LGTM). Every finding from every round is surfaced to the user with its material/not classification and reasoning; the user overrules any of it. Mechanism: `docs/planning/two-brain-convergence.md`.
  - **Drift-hunter in `codex-review-gate`.** When `/before` left a FRESH approved plan for the repo — its stamped `Base:` commit is an ancestor of HEAD AND the spec is under 24h old — the gate prepends the plan and the review hunts on two axes: DRIFT from the plan (missed steps, unapproved scope, silent changes) plus the existing correctness/security pass, tagging findings `[DRIFT]`/`[BUG]`. A stale, mismatched, or missing plan falls back to the generic correctness prompt and states "drift NOT checked" in every outcome (LGTM and deny) — a drift review that never read a plan is never claimed.
- **Live-loop event log in `codex-review-gate`** — a pure side-effect that streams the Claude↔Codex exchange for the optional **coderv-loop** dashboard. The gate appends one JSON line per beat to `~/.claude/coderlap/loop-events.jsonl` (writer's commit attempt → reviewer started → verdict → each finding → terminal outcome). CONTRACT: the log never influences the allow/deny decision, never errors the hook, is silent when `jq` is absent, and honours the gate's kill switches (plus its own `CODERV_LOG_OFF=1`); the log path is `CODERV_LOOP_LOG`. Every review path emits a **terminal `outcome`** so a tailing dashboard never hangs mid-review: a denied review, a plain pass, a cache-hit retry (which also emits its `commit_attempt` beat), and a reviewer that timed out or errored (emitted `unreviewed:true`, never as a genuine pass). The `flock` serialising concurrent writers is bounded (`-w 1`) and falls through to a plain append on timeout — a hung lock holder can never stall the hook. coderv-loop itself is a separate optional local app, not part of the seven-command surface.

### Changed
- **`context-gate` now triggers on an absolute token budget, not a percentage of the model's window** (ADR-012). The dumb zone (context rot) is an absolute occupancy floor (~150–200k), not a fraction of the admission limit — so on a 1M-window model the old `% of 200k` default gated ~5× too early, and the naive fix (window = 1M) would have gated at 750k, deep into rot. The gate now blocks at `min(CODERV_CTX_BUDGET, CODERV_CTX_WINDOW × CODERV_CTX_SAFETY_PCT/100)` and warns at 0.75× that, comparing **absolute tokens** (removing the round/bucket/hysteresis bugs that scaled badly at large windows). Occupied context is read from the transcript's last main-chain call (uncached input + cache read + cache creation; sidechains excluded, never summed). New config: `CODERV_CTX_BUDGET` (default 180000), `CODERV_CTX_WINDOW` (default 1000000), `CODERV_CTX_SAFETY_PCT` (default 90); the old `CODERV_CONTEXT_WINDOW` is still honoured as a window fallback (`CODERV_CTX_WARN_PCT`/`CODERV_CTX_BLOCK_PCT` are superseded by the absolute budget).
- **`/before` spec is now immutable and stamped** (ADR-009). The per-task spec is always OVERWRITTEN (never appended) and carries a `Base:` commit stamp + ISO date. One spec = one task; the stamp is what arms the drift-hunter, and an appended history would leave stale baselines a later review could hunt against by mistake.
- **`/ship` gate-deny handling becomes a discussion** (ADR-009). On a codex-review-gate deny, Claude may rebut a finding to Codex ONCE (same stdin channel, one round) before deciding. Codex is a peer reviewer, not a boss: Claude's call is final, and every finding — fixed, rejected, or rebutted-and-held — is surfaced to the user, who is the final authority.

## [0.9.0] — 2026-07-17

### Added
- **`codex-review-gate`** (PreToolUse on Bash, 4th anti-dumb-zone gate). Implements the machine gate of the two-model workflow (owner's `AI-WORKFLOW-PLAN.md`): before any commit-creating git command runs, the outgoing working-tree diff is piped to Codex CLI for adversarial review (correctness, edge cases, security, data integrity). Findings block the commit once — the agent adjudicates, must surface rejected findings to the owner (transparency rule), and the same-diff retry passes via a 24h hash cache; a changed diff is reviewed afresh. Never blocks: non-commit commands, non-git dirs, empty or docs-only diffs. Codex missing/auth-lapsed/timeout → commit allowed WITH a loud warning (fail-loud, never fail-shut, never silent). Requires `codex` CLI logged in via ChatGPT sub. Kill switches: `CODEX_REVIEW_OFF=1` or `CODERV_GATES_OFF=1`. `install.sh` wires/unwires it like the other gates.
- **Gap-scan hardening of `codex-review-gate`** (same-day ultra scan, 174 agents, 24 confirmed findings; scan output is owner-local, gitignored as `docs/GAP-SCAN-*.json`): (1) *critical* — allow paths no longer emit `permissionDecision: "allow"`, which was auto-approving the whole Bash command past the user's permission prompt; they now emit only `systemMessage` + `additionalContext` and defer to the normal permission flow. (2) Commit detection is a command-position regex covering `git -C <dir>`/`-c`/long global flags and the merge / cherry-pick / revert / rebase subcommands; quoted strings are scrubbed first, so `echo "git commit"` and commit messages no longer trigger reviews. (3) Untracked files are included in the reviewed diff (and the docs-only check), closing the new-file-only bypass. (4) Diffs over 150KB now say LOUDLY in every outcome that only the first 150KB was reviewed instead of certifying the full diff. (5) `codex exec` runs with `-s read-only` so the reviewer cannot execute commands. (6) Missing `jq` warns on commit-like commands instead of silently bypassing. (7) `cd` dir resolution handles quoted paths and a leading `~`; `git -C <dir>` wins over `cd`.
- **First live deny rounds hardened the gate further** (the gate reviewed its own commit across five deny rounds and kept finding real gaps — the fifth round's findings were all rejected with evidence, converging via the review cache; fixed before shipping, verified by a 14-case stubbed-codex suite): (1) `merge` / `cherry-pick` / `revert` / `rebase` integrate commits the gate cannot see — clean worktree now allows with a loud "NOT reviewed" warning instead of a silent skip, and dirty worktree labels every outcome (even LGTM) with "incoming commits UNREVIEWED". (2) `-C <dir>` repo resolution is tied to the commit-creating git invocation itself: `git -C /other status && git commit` no longer reviews the wrong repo, and `git -c k=v -C /repo commit` resolves correctly (flags may surround `-C`). (3) The 24h review cache keys on repo path + HEAD + diff, so an identical diff in a different repo is reviewed afresh. (4) The jq-missing warning triggers on all commit-creating subcommands, not just the literal word "commit". (5) Value-taking long flags in separate-argument form (`--git-dir X`, `--work-tree X`, …) no longer bypass detection (dir resolution for those exotic forms falls back to cd/cwd — documented). Accepted (documented in the hook header): compound commands committing in several repos review only the first matched invocation's repo; staged-hunk-with-reverted-worktree in mixed commits (previously adjudicated).
- **`/ship` commits through the gate** (ADR-008). The scorecard pause is unchanged — nothing is committed before the user's "approve" — but after approval the agent runs `git commit` itself via Bash, so every /ship commit passes through `codex-review-gate`. The old "show the command, the user runs it" rule let commits typed in an outside terminal bypass the machine reviewer entirely.
- `install.sh install_gate_hook` accepts an optional per-hook `statusMessage` (used by the codex gate: "Codex adversarial review...") so the installed settings entry matches the live one.

### Why bump 0.8.0 → 0.9.0
Minor bump: a new runtime component (the 4th gate hook + its Bash/PreToolUse wiring) plus a behavior change to `/ship` (it now runs the commit through the gate, ADR-008). All additive; existing installs upgrade non-breaking with `./install.sh --force`. The gate is opt-out (`CODEX_REVIEW_OFF=1` / `CODERV_GATES_OFF=1`) and degrades to a loud warning when Codex is absent, so an install without the `codex` CLI keeps working.

## [0.8.0] — 2026-07-15

### Added
- **The anti-dumb-zone system** (ADR-006). Three always-on Claude Code hooks that turn "don't hallucinate, don't ignore the docs" from advice into mechanism:
  - **`grounding-gate`** (PreToolUse on Edit/Write/MultiEdit/NotebookEdit) — blocks the session's first *code* edit in any project with a doc system (CLAUDE.md + docs/) until `/before` has written a grounding receipt (or a conscious skip is declared with a reason). Docs-only edits, non-doc-system repos, `~/.claude`, and temp paths are never blocked.
  - **`compact-rehydrate`** (SessionStart, matcher `compact`) — after compaction (the #1 source of "shipped ✅" fiction), injects a live git/versions snapshot with the standing rule: when the summary and the snapshot conflict, the snapshot wins.
  - **`context-gate`** (Stop) — measures real context usage from the transcript (last main-chain API call; sidechains excluded; never summed). Warns the user at 60% (once per 5% bucket), hard-blocks the agent once per session at 75% (re-arms after compaction): the only sanctioned moves are finishing the atomic step, writing an evidence-pasted handoff, and asking for a fresh session. `CODERV_CONTEXT_WINDOW` / `CODERV_CTX_WARN_PCT` / `CODERV_CTX_BLOCK_PCT` configure; `CODERV_GATES_OFF=1` disables all gates.
- **`/coderv` — the 7th command, the front door** (ADR-007). Classifies a natural-language request (feature / bug / question / wrap-up / docs-health), checks project state from facts (lint freshness stamp, dirty git, newest handoff), assembles the pipeline (`/lint` when docs are stale → `/before` → work → `/ship`), shows it once, and drives the whole chain on a single yes — pausing only at plan approval and scorecard approval. The six commands a human had to remember become one.
- **Verification scorecard in `/ship`.** Approval becomes a glance: `VERIFICATION SCORE: 100% (9/9 gates)` — computed from pass/fail gates (receipt, spec items verified in diff, build, tests, citations, quote matches, reviewer verdict, nothing-unrequested, no secrets), each line with its real command output pasted. 100% requires every gate green with evidence; unrunnable checks score ✖ with the reason, never silently dropped. Human-judgment items are listed separately, never folded into the number. The score is computed, never self-rated — "no hallucination" is expressed as its checkable form: *0 unverified claims*.
- **Fresh-context reviewer in `/ship`.** One subagent with a clean context audits the actual diff against the spec checklist `/before` wrote to disk — adversarial brief, runs build/tests, quotes evidence verbatim; the primary machine-verifies every quote (string match at cited file:line) before believing a finding.

### Changed
- **`/before`** now writes two disk artifacts after stating the plan: the grounding receipt (which docs were actually read — unlocks the gate) and the spec checklist (the request as 3–5 checkable lines — the reviewer's ground truth for intent). Skips declare themselves to the gate with a reason.
- **`/session`** handoffs gain a mandatory "State evidence (verbatim)" block: state claims are pasted command output, never prose — a degraded session can misremember, it can't mis-paste.
- **`/lint`** runs its sweep in a subagent (the most context-hungry skill no longer pushes the main session toward the dumb zone), machine-verifies finding quotes before reporting, checks for stale coderlap artifacts (leftover specs/receipts from shipped tasks), and stamps a freshness state file that `/coderv` reads.
- `install.sh` installs/wires/uninstalls the three gate hooks for the Claude target (same idempotent settings.json merge + marker protection); final banner shows 7 commands + the gates and kill switch.

### Why bump 0.7.0 → 0.8.0
Minor bump: a new command, three new hooks, and verification steps across four skills. All additive; existing installs upgrade with `./install.sh --force`. Design rationale — including what was deliberately rejected (an always-on LLM auditor, a standing panel of per-doc expert agents) — is in ADR-006/ADR-007.

## [0.7.0] — 2026-07-13

### Added
- **`/lint` — the 6th command** (ADR-005). The toolkit's missing third operation (ingest → query → **lint**): audits `CLAUDE.md` + `docs/` for contradictions (rules that flip-flopped with no current-status line), stale claims ("NOT committed" from last week, versions that drifted from package manifests), dead references (citations past EOF, links to deleted files, documented commands that no longer exist), and rot (STALE-bannered drafts, orphan docs). Findings are severity-ranked with `file:line` + the reality they conflict with; fixes are offered (mechanical in one approved batch, judgment calls one question at a time) and history is never deleted. Reason for adding: field use showed docs that lie are worse than no docs — and nothing owned catching the lies.
- **`release.sh` — the release ritual as a machine gate.** Verifies semver VERSION, CHANGELOG top-entry match + ISO date, clean tree, tag availability, and TRIGGER/SKIP on every skill; then tags, pushes, syncs the website (site.ts bump + rebuild + commit via `CODERV_SITE_DIR`), and prints the one human step (`gh release create`). `--check` mode verifies without acting. Reason: "VERSION + CHANGELOG + tag + site move together" was enforced by memory and got missed (the site sat at 0.5.0 while the toolkit shipped 0.6.0) — machine gates over prose rules.
- **coderv-router:** HIGH/LOW intent patterns + description line for `/lint` ("audit the docs", "is there a gap in the docs?", "docs are lying" → HIGH; "are the docs up to date?" → LOW). Docify's generate-intent patterns untouched.

### Changed
- **`/session` now rotates:** past ~20 entries, everything but the newest 10 moves to `docs/SESSIONS-ARCHIVE.md` — byte-identical, append-only, pointer left behind. The live file is read at every session start (skills + the project-context hook), so it must stay cheap; archives keep history greppable forever.
- CLAUDE.md surface rule updated 5 → 6 commands with the ADR-005 justification recorded and the bar for slot 7 set explicitly.

### Why bump 0.6.0 → 0.7.0
Minor bump: a new command (first since the original five), a new repo-level tool (release.sh), and expanded router surface. All additive; existing installs upgrade with `./install.sh --force`.

## [0.6.0] — 2026-07-13

### Added
- **`project-context` hook** — a `SessionStart` hook for Claude Code that injects a live project map into every new session: one line per project under the projects root (newest `docs/SESSIONS.md` entry + last-touched date, sorted by recent activity) plus a standing rule to Read the real CLAUDE.md/SESSIONS/DECISIONS/KNOWN-ISSUES before working. Lives at `hooks/project-context.sh`, installed to `~/.claude/hooks/` and wired into `settings.json` (SessionStart) automatically on `--claude`. Projects root configurable via `CODERV_PROJECTS_DIR` (default `/home/appuser/apps`, fallback `~/apps`); silently injects nothing on machines without documented projects. Reason for adding: the session-start ritual ("read the docs first") lived in agent memory and user reminders — both skippable. A SessionStart hook runs in the harness every session and reads the actual files at start time, so it can neither be forgotten nor go stale.

### Changed
- `install.sh` — installs/uninstalls both hooks for the Claude target with the same idempotent settings.json merge and `<!-- claude-docs-toolkit -->` marker protection; header documents the two hooks.

### Why bump 0.5.0 → 0.6.0
Minor bump: adds a second runtime component (new hook + new settings.json event wiring). Existing installs upgrade non-breaking — `./install.sh --force` adds the new hook alongside the router.

## [0.5.0] — 2026-04-28

### Added
- **`coderv-router` hook** — a `UserPromptSubmit` hook for Claude Code that scans every prompt for intent patterns and injects a reminder into Claude's context when it matches one of the 5 skills. Lives at `hooks/coderv-router.sh` in the toolkit, installed to `~/.claude/hooks/coderv-router.sh` and wired into `~/.claude/settings.json` automatically. Two confidence tiers: HIGH (clear intent, offer firmly) and LOW (ambiguous, check intent first). Reason for adding: skill descriptions are guidelines the model can miss mid-task; the hook runs in the harness and can't be forgotten.
- **Multi-host install targets** — `install.sh` now supports `--claude` (default), `--codex`, `--gemini`, and `--all`. The 5 SKILL.md files port verbatim to Codex CLI (`~/.codex/skills/`) and Gemini CLI (`~/.gemini/skills/`) since both hosts adopted the same skill format. The `coderv-router` hook is Claude-Code-specific and only installs when the Claude target is selected.
- README section explaining the router with a phrase-to-skill mapping table, plus FAQ entries on Codex/Gemini support and why the router exists.

### Changed
- `install.sh` rewritten with per-host install/uninstall functions; idempotent settings.json merge that never duplicates the hook entry; `--uninstall` now scoped to whichever target(s) the user selected, with the same `<!-- claude-docs-toolkit -->` marker check that protected unrelated skills before — now applied to the hook script too.

### Why bump 0.4.1 → 0.5.0
Minor bump, not patch: this introduces a new install target (the hook + Codex/Gemini support), changes the public surface of `install.sh` (new flags), and adds a runtime component (the hook) that didn't exist before. Existing `./install.sh` with no flags behaves identically to v0.4.1 for skills, plus auto-installs the router — so the upgrade is non-breaking but the surface area grew.

## [0.4.1] — 2026-04-26

### Changed
- **All 5 skills now lead terse, expand on request.** v0.4.0 introduced friendly tables but the default output was still 30+ lines. v0.4.1 leads with a 3–6 line answer + recommendation; the full table breakdown only renders when the user asks ("details", "show me more", "show checklist", "show git", etc.).
  - `/before` — default plan is one-sentence summary + recommendation. "details" reveals the full check table, file list, and heads-up.
  - `/ship` — default is the commit message + key signals + recommendation. "details" reveals the full pre-commit checklist with status table.
  - `/session` — wrap-up prompt and confirmation are 2–3 lines each. "show git" reveals the full git diff/log.
  - `/decision` — ADR-creation prompt is one block of 5 short bullets. "example" reveals a worked sample.
  - `/docify` — pre-flight plan and post-generation report each lead with 4–5 lines. "details" reveals the file-by-file breakdown.

### Added
- **`coderlap:rule:terse-by-default`** in `CLAUDE.md` (both repos): lead with the answer + recommendation in 2–4 lines; offer details on request. Reason: most replies don't need the full audit — the audit only helps when the user disagrees.

### Why bump 0.4.0 → 0.4.1
Same skill contract, same friendly voice, just shorter by default. Patch-level — anyone using v0.4.0 sees the same skills behave more concisely; nothing breaks.

## [0.4.0] — 2026-04-25

### Changed
- **All 5 skills now speak in plain words, not jargon.** Skill output sections rewritten with friendly, scannable tables — emoji per row, `✅` / `❌` contrasts, plain-English labels. Replaces the prior dense plan-blocks that read like architecture documents.
  - `/before` — plan output now uses a "What I checked / What I found" table and ends with **a recommendation** instead of "approve to proceed?".
  - `/ship` — pre-commit report uses a status table with friendly labels (📦 Files staged, 📚 Doc updates, 🔗 Doc references, 🐛 Bug-prevention, 🔐 Secrets), ends with a recommendation on whether to ship as-is, hold, or split.
  - `/session` — wrap-up prompt and confirmation use plain-English column headings, anchor on git facts (verified, not recalled).
  - `/decision` — ADR creation prompt uses a friendly fields table (🎯 problem, ✅ what you picked, 🤔 alternatives, ⚖️ trade-off).
  - `/docify` — pre-flight plan and post-generation report use scannable tables with one emoji per row + a "heads-up" section for TODOs the user should review.

### Added
- **`coderlap:rule:always-recommend`** in `CLAUDE.md` (both repos): when the user asks "what should I do?", commit to a path first; offer alternatives only as one-line footnotes. Reason: the user came to a tool to do the thinking — menus push the work back to them.
- **`coderlap:rule:friendly-voice`** in `CLAUDE.md` (both repos): codifies the new plain-words style with concrete jargon → plain swaps (e.g. "stale citations" → "doc references that no longer match the code").
- **`coderlap:rule:commit-style`** in `CLAUDE.md` (both repos): commit messages are plain text, no `Co-Authored-By: Claude`, no robot emoji, no AI attribution — overrides any default git templates. Promoted to a top-level "Never" item in both repos so it can't be skimmed past.

### Fixed
- v0.3.9's two commits (toolkit + website) had `Co-Authored-By: Claude` lines that violated the user's stated preference. Both repos amended; toolkit force-pushed with retagged `v0.3.9`. The new `commit-style` rule prevents recurrence.

### Why bump 0.3.9 → 0.4.0 (minor, not patch)
This is a meaningful UX change to the user-facing voice of every skill. Anyone who memorised the old output format will see different output. Worth a minor bump — not a breaking change, but more than a patch.

## [0.3.9] — 2026-04-25

### Added
- **First real docs for CoderLap itself**, generated via `/docify` and approved. Both repos (toolkit + website) now have:
  - `CLAUDE.md` at root with project-specific rules + shared `<!-- coderlap:rule:* -->` markers.
  - `docs/` folder with citation-backed reference docs. Toolkit: `overview.md`, `architecture.md`, `skills.md`. Website: `overview.md`, `architecture.md`, `components.md`, `content.md`, `styles.md`, `deployment.md`. Every claim cites a source file with line ranges so future drift can be caught by `/ship`.
  - Empty scaffolds for the three living docs: `DECISIONS.md` (ADR log), `KNOWN-ISSUES.md` (recurring bugs + prevention rules), `SESSIONS.md` (handoff log).
- **4 ADRs in `docs/DECISIONS.md`** capturing design decisions made today:
  - **ADR-001** — `/session` must verify ship claims from git, not from prompt context. Prompted by a real failure where a compaction summary asserted v0.3.9 had shipped when it hadn't.
  - **ADR-002** — Curate the skill surface. Keep CoderLap's 5 commands legible amid third-party plugin skills; resist adding a 6th.
  - **ADR-003** — Verification mechanics. Two-tier verification (git when present, filesystem snapshot when not), session-anchored time windows, multi-repo support, separate handling of staged/unstaged/committed state.
  - **ADR-004** — Verification is a toolkit-wide principle, not a `/session` patch. Every durable artefact any skill writes must cite a verifiable source.
- **Self-documented session handoffs.** `docs/SESSIONS.md` in both repos pre-seeded with the `/docify` approval session and an honest "not yet shipped" status — fixed mid-session when the prior handoff was discovered to have lied (see ADR-001).

### Note
- ADRs ship as design intent, not implementation. ADR-001/003/004 describe how `/session` and the other skills *should* verify; the actual code changes to `skills/*/SKILL.md` are deferred to a future release.

## [0.3.8] — 2026-04-24

### Added
- **Open Graph preview image** (`/og.png`) — 1200×630 branded card that renders whenever anyone shares `coderv.dev` on Twitter, WhatsApp, Slack, Discord, LinkedIn, Google SERPs. Matches the hero visual style: dark + violet blobs, gradient text on "extremely clear", version pill, CoderLap logo mark, context-aware tagline.
- **`/og` Astro route** that renders the card at exact 1200×630 dimensions with full theme tokens. Headless Chromium screenshots this route to produce the final PNG.
- **`scripts/regen-og.sh`** — one-command regeneration whenever the hero design changes.
- OG + Twitter card meta tags wired into `BaseLayout.astro`: `og:image`, `og:image:width/height/alt`, `og:site_name`, `twitter:card=summary_large_image`, `twitter:image`, `twitter:image:alt`. Applies to every page, not just the home.

## [0.3.7] — 2026-04-24

### Changed
- **/docify TRIGGER expanded to catch plain words "docs" / "doc" / "documentation" / "README".** Previous trigger list required phrases like "write docs"; single-word mentions were often missed. Also added phrases like "make a full docs", "docs are missing", "docs outdated". Added ambiguity guard: on short single-word mentions, the skill asks whether the user means generation or a single-file edit before running.

## [0.3.6] — 2026-04-24

### Changed
- "Used in production by" list updated: CareShifa link now points at the production site (`careshifa.com`). Yokisa entries expanded to name the individual products (Streak, Anime, TV, Hub, Billing, Achievements). Removed private internal tools from the public list.

## [0.3.5] — 2026-04-24

### Added
- **README badges** on both repos: latest release, GitHub stars, GitHub forks, licence, "built for Claude Code". Strangers visiting the repo immediately see it's alive, released, and has traction.
- **"Used in production by" section** in toolkit README listing real deployments. Trust signal beats raw download numbers.
- **"Star on GitHub" CTA** on the homepage replaces the plain "View on GitHub" button — yellow star icon, call-to-action framing, hover scales the icon.

### Changed
- Hero authority strip label: "Built by Abdullah Hadi" → **"Used in production by"** (sharper positioning — these are users, not just a bio).

## [0.3.4] — 2026-04-24

### Changed
- Contact email updated from `GGAbdulalah@gmail.com` to **`support@coderv.com`** across:
  - `LICENCE` (both repos) — §1 Definitions, §4 Requesting Permission, footer contact
  - Website footer, `/licence` page, hero email CTA, meta tags
  - `README.md` (both repos)
  - `src/config/site.ts` — single source of truth propagates to every page

## [0.3.3] — 2026-04-24

### Changed
- **Licence — warmer tone.** Section 3 ("Reserved Rights") now opens with a preamble clarifying that personal/evaluation use is already free, and that the restrictions exist to track commercial/redistribution use at scale. Section 4 ("Requesting Permission") now opens with "a short email is fine; do not overthink it". No change to the legal rights themselves.
- **Website licence page redesigned.** Previous layout was one dense legal wall after the at-a-glance card. New layout:
  - At-a-glance card split into two columns (free-no-permission vs email-first) alongside a prominent email CTA.
  - New "Frequently approved" FAQ block with 6 typical scenarios (day job, fork, blog, paid course, product bundling, SaaS clone) showing what usually gets a yes.
  - Full legal text restructured as 11 individual cards with a sticky sidebar table of contents on desktop. Section 2 gets emerald accent (permitted), Section 3 gets amber (reserved), Section 4 gets violet (contact). Each has a small icon badge.

## [0.3.2] — 2026-04-24

### Added
- **Magic Triggers**: every skill's YAML description now includes `TRIGGER` and `SKIP` blocks listing natural-language phrases that should surface the skill without requiring the slash prefix. Claude Code's skill picker uses these to suggest the right tool when users describe their intent in plain English.
- **`coderlap:rule:suggest-followups`** rule in `templates/CLAUDE.md` rewritten as a phrase → skill → suggested-reply map. Reinforces the trigger pattern in every project that runs `/docify`.
- VERSION file + CHANGELOG at repo root.

### Changed
- Installer trailer message lists the current toolkit version.

## [0.3.0] — 2026-04-23

### Added
- **`/docify`** — scans any codebase and generates `CLAUDE.md` + 6 docs (overview, architecture, api, components, database, integrations). Every claim cited back to a source file. Drafts-first safety model. Preserves existing CLAUDE.md rules via `<!-- coderlap:rule:* -->` markers.
- Smart **`/ship`** — detects new routes / components / schema changes and offers to update the relevant doc itself (not just ask). Citation validator walks `docs/**.md` and flags stale `<!-- src: -->` markers on every commit.
- **`/before`** now suggests follow-up commands (`/decision`, `/ship`, `/session`) inline at the right moments, without auto-running.

### Changed
- `templates/CLAUDE.md` adds rule markers (`<!-- coderlap:rule:* -->`) so `/docify` can re-add missing rules without clobbering custom ones.

## [0.2.0] — 2026-04-23

### Changed
- **Trimmed from 10 commands to 4 focused commands**: `/before`, `/decision`, `/ship`, `/session`. Removed `/docs`, `/doc-init`, `/doc-new`, `/gap`, `/repeat`, `/trace` — their roles either absorbed into the 4 kept commands or moved to CLAUDE.md rules.
- `/before` auto-skips tiny edits (typos, one-liners, same-session undos) and auto-runs on bigger tasks (refactor, rename, first touch of a module).

## [0.1.1] — 2026-04-23

### Added
- One-line installer: `curl -fsSL https://coderv.dev/install.sh | bash`
- `--project` flag installs skills into `./.claude/skills/` instead of user-global.

## [0.1.0] — 2026-04-23

### Added
- Initial public release with 10 slash commands: `/doc-init`, `/docs`, `/before`, `/gap`, `/doc-new`, `/decision`, `/ship`, `/session`, `/repeat`, `/trace`.
- Installer (`install.sh`) + templates (`MASTER-INDEX.md`, `DECISIONS.md`, `KNOWN-ISSUES.md`, `SESSIONS.md`).
- CoderLap Source-Available Licence v1.0.
