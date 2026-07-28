# Changelog

All notable changes to the CoderLap Docs Toolkit.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [0.16.0] — 2026-07-28

> No hook changes — no reinstall of `~/.claude/hooks/` needed. Re-run
> `install.sh` only to refresh the skill copies under `~/.claude/skills/`.

### Added
- **`docs/CONTEXT.md` — the project vocabulary (ADR-025).** New `templates/CONTEXT.md`; `/docify` now generates `docs/CONTEXT.draft.md` (term → meaning → code anchor, normal drafts-first flow), `/before` reads it right after CLAUDE.md and surfaces term conflicts instead of silently picking a side, and `/lint` checks it deterministically: anchored terms get the standard citation check, the "Domain-only terms" section is anchor-exempt by design. Adapted from mattpocock/skills' ubiquitous-language idea.
- **Two new CLAUDE.md rule markers shipped to every project** (`templates/CLAUDE.md` + docify's marker list): `coderlap:rule:tests` — expected values come from an independent source of truth, never recomputed the code's way; vertical slices by default with regression/characterization tests as named exceptions — and `coderlap:rule:design` — deep modules, the deletion test, accept-dependencies-don't-create-them, one-adapter-hypothetical/two-real; scoped to core logic with adapters/handlers/glue as named exceptions.
- **Fowler smell baseline in `/ship`'s fresh-context reviewer brief** — 12 smells (name → fix) matched against every diff as labelled judgement calls; advisory notes only, never scorecard gates; repo-documented standards override. The baseline is adopted from mattpocock/skills' code-review; the skill around it was rejected (ADR-025) — an ungated second review loop is what the codex-review-gate exists to bound.
- **`skills/coderv/bug-diagnosis.md` run-book** for the 🐛 shape (sibling of `architecture-review.md`): a red-capable repro command is mandatory *before* any hypothesis — then minimise, 3–5 falsifiable hypotheses shown to the user, tagged instrumentation, regression test at a correct seam, prevention rule via KNOWN-ISSUES.
- **Prototype-first planning in `/before`** — when an open design question blocks the plan, it may include a throwaway prototype step (marked, one command to run, no persistence); the verdict lands via `/decision`, the prototype never lands on main. `/before`'s detailed plan also names the **seam** each change goes through.
- **🗺 Effort maps — multi-session planning without a tracker (ADR-026).** New `/coderv` shape driven by `skills/coderv/effort-map.md`: a loose idea too big for one session gets one `docs/PLAN-<topic>.md` (`Status: active|done`) holding the destination, the open decision questions, the fog, and links — never copies — of resolved decisions (ADRs stay the single home). Chart mode creates it; work-through mode resolves one question per session; `/before` reads the active map as prior art, `/session` hands off the frontier, `/lint` flags a stale active map, and bare `coderv` proposes the next question. Adapted from mattpocock/skills' wayfinder, on local markdown.
- **Grill mode in `/before` (opt-in, Step 4.5).** For requests with open *decisions*: one question per message, each with a recommended answer; facts are looked up, never asked; answers land in the spec checklist. Adapted from mattpocock/skills' grilling.
- **`coderlap:rule:merge-conflicts`** in `templates/CLAUDE.md` — resolve conflicts from primary sources; preserve both intents where compatible, the merge's stated goal where they clash; never invent behaviour. (Updates ADR-025's line-item: the skill stays rejected, its distilled rule is adopted — ADR-026.)

## [0.15.2] — 2026-07-25

> **Heads-up — reinstall required.** The commit gate's hook changed. Re-run
> `install.sh` after pulling so `~/.claude/hooks/` gets the new copy.

### Fixed
- **The last gate block that could trap the owner is closed (ADR-024).** The commit gate fails CLOSED (hard deny) when a commit uses a `<<` heredoc and the `awk` command-scrub can't run — a safety fallback, since a heredoc body could otherwise hide an unreviewed commit line. But that deny fired before the owner-escape checks, so on a host with no working `awk` an owner who said "ship it" had no in-band way past it — the one spot the gate could overrule the owner. It now honours the owner's gates-off flag (`~/.claude/coderlap/gates-off`) at that point, so the owner is never trapped. The per-diff `--approve` marker is deliberately *not* consulted here: when the scrub fails the target repo can only come from the very command that failed to parse, and a cwd-keyed guess would wrongly pass a `git -C /other-repo commit` decoy — so the global gates-off switch (which needs no target) is the only safe escape. With no flag present the path still denies (unchanged). Suite: 255 checks, 0 failed.

### Changed
- **Corrected stale references to the superseded `CODERV_GATE_OWNER_OVERRIDE`.** A hook reads that variable from the session's launch environment, so an env-prefix on a retried commit never reaches it — ADR-023's `--approve` is the mechanism that actually works in-band. Fixed the misleading in-code comments (the CAP-ride branch), the `two-brain-convergence.md` CAP-STOPPED escape wording, and the `context-gate` block message (which overstated a one-shot Stop nudge as the "only sanctioned move" — continuation is allowed, and the user is the final authority).

## [0.15.1] — 2026-07-24

> **Heads-up — Windows users must reinstall.** The grounding gate and the
> coderlap slug formula changed. Re-run `install.sh` after pulling.

### Fixed
- **The grounding gate permanently locked every drive-rooted Windows project (`D:\...`).** The receipt filename was built by replacing path separators with dashes, which left the drive colon in place (`D:-...`) — and `:` is illegal in Windows filenames, so no receipt could ever be written or matched: the gate was mechanically unsatisfiable and blocked all code edits forever. Found live on a Windows machine (the agent proved it two independent ways). The slug is now legal on every OS: both separators (`\` and `/`) become dashes and `:` is stripped — a byte-for-byte no-op on Linux, so existing receipts/specs keep matching.
- **Writer/reader slug agreement on Windows.** Git Bash sees `/d/...` while the hooks see `D:\...`, so even a legal slug could disagree between the `/before` receipt writer and the gate reader. Every slug snippet (`/before` receipt + spec, `/ship` spec lookups, `/lint` state, `/coderv`, and the commit gate's drift-hunter spec path) now canonicalises through `cygpath -w` first (a no-op on Linux, where cygpath does not exist) and applies the same `tr`/strip formula, so all nine slug sites resolve to the identical string on both OSes. Suite re-run after the change: 249 checks, 0 failed.

## [0.15.0] — 2026-07-23

> **Heads-up — reinstall required.** The commit gate's hook changed again.
> Re-run `install.sh` after pulling so `~/.claude/hooks/` gets the new copy.

### Added
- **Owner authority is now mechanically enforceable: `codex-review-gate.sh --approve <repo-dir> "<the owner's words>"` (ADR-023).** When the gate denies a diff and the owner explicitly says "approved" in chat, the agent records that decision and retries the identical commit — it passes immediately, without waiting for the round cap, riding the retry cache, or asking the owner to run terminal commands. The approval is keyed to the **exact current outgoing diff** (repo@HEAD + worktree delta + untracked, hashed by the same functions the review path uses, so writer and reader can never diverge): one changed byte = a different key = normal review, and the gate stays fully armed for every other diff. It takes **top precedence** — checked before the round cache, cap, ceiling, and security-escalation states, and before any Codex call — because the gate exists to block autonomous agent decisions, never an explicit owner decision. Single-use (consumed on the pass), auditable (the marker stores the owner's quoted words + timestamp), loud (the allow quotes the approval and restates that open findings must still be surfaced), and logged (`approval_recorded` / `owner_approved_diff` events). Every deny message now teaches this exit. Regression-locked by tests T74–T75 (suite now **249 checks**), including: stale approvals never leak onto a changed diff, and a fresh approval outranks even a ceiling `[security]` escalation.
- **`~/.claude/coderlap/gates-off` — emergency mid-session off-switch (secondary; ADR-023).** The env kill switches are read from Claude Code's environment, frozen at session launch, so they can't honour a mid-session owner decision. Touching this file skips ALL commit reviews — loudly, with a `gate_skipped/owner_gates_off` event per skip — until it is removed or expires 24h after creation. Explicitly NOT the primary owner exit (that is the per-diff `--approve` above); owner's explicit in-chat decision only.

### Fixed
- **The gate's documented owner-override was a dead end for everyone (ADR-023).** Deny messages instructed re-running the commit with `CODERV_GATE_OWNER_OVERRIDE=1`, but the hook only reads that variable from its own environment — frozen at session launch — so an env prefix typed in the command string never reached it, whether the agent ran it or the owner did via `!`. The variable check remains as a legacy launch-env pass, but the deny messages now point at the working, scoped `--approve` exit instead.

## [0.14.0] — 2026-07-23

> **Heads-up — reinstall required.** The commit gate's hook changed (the
> ADR-022 review-policy split plus the security fix below). Re-run `install.sh`
> after pulling so `~/.claude/hooks/` gets the new copy; until then the old
> behaviour (and the bypass below) is still live on your machine.
>
> *(This entry also carries everything staged as an unreleased "0.13.1" —
> that version was never tagged; its lexer hardening ships here.)*

### Changed
- **The default commit-gate review is now an engineering QUALITY GATE, not a per-commit penetration test (ADR-022).** The round-8/9 lexer saga below proved the old policy could not converge: every exotic shell-grammar corner was tagged `[security]`, `[security]` could never be marginal, so real-but-unreachable hardening gaps blocked commits exactly like reachable auth bypasses — an infinite surface, reviewed one blocking round at a time. The policy now splits on **reachability + impact, never craftedness or rarity**:
  - A new MARGINAL severity `[hardening]` marks a security-relevant weakness with NO credible reachable high-impact path (the shell-grammar-corner-in-a-self-authored-commit-message class). It is FORBIDDEN when a realistic attacker can reach the path — real injection is crafted input and still blocks.
  - In default mode a marginal-only review (`[hardening]`/`[edge]`/`[theoretical]`) **allows in ROUND 1** — not cap-gated — with every finding surfaced under a labeled **"Optional Security Review (non-blocking)"** section (transparency rule preserved: surfaced, never dropped). A normal dev commit with no realistic-impact defect converges in ONE round.
  - An impact-subordination governing rule binds ALL marginal tags: a rare-but-reachable data-loss/security/wrong-result defect must take a MATERIAL tag — `[edge]`/`[theoretical]` can no more downgrade it than `[hardening]` can.
  - Realistic `[security]`/`[data-loss]`/`[correctness]` findings, untagged findings, prose replies, the round cap/ledger/ceiling machinery, and the ceiling security escalation are all UNCHANGED — real bugs block exactly as before.
  - Honest note: the delimiter-lexer hardening below **stays in-tree and active**; its findings class just no longer blocks by default.

### Added
- **`CODERV_GATE_SECURITY=1` — the explicit deep-security opt-in (ADR-022).** Flips the reviewer to the full adversarial brief (fuzzing, parser hardening, exotic shell grammar, adversarially-crafted input) AND makes `[hardening]` block like material, restoring the pre-0.14.0 cap-gated semantics for the run. `/ship` gained a `--security` flag that exports it for the whole pre-commit loop and the commit itself — the documented path when the owner asks for a security pass. The review MODE is part of the gate's cache identity: an allow earned under the default quality gate (`lgtm`/`optional` marker) can never satisfy a `--security` rerun of the identical diff — the opt-in always gets its own fresh adversarial review (caught by this release's own pre-commit Codex round). And because a PreToolUse hook inherits Claude Code's environment — NOT an env-prefix written inside the command string — the gate also recognizes `CODERV_GATE_SECURITY=1` as a command prefix on the commit itself (the /ship `--security` form), and every verdict names the mode when the deep review ran, so a transport failure can never silently masquerade as a security pass (caught by this release's own fresh-context audit).
- New `tests/gate-cap.sh` cases T65–T73 (suite now **237 checks**): hardening-only allows round 1 with the Optional section and a caveat-preserving retry, all-marginal mix allows, `[security]`/`[correctness]` still block, the opt-in makes `[hardening]` block, mixed correctness+hardening denies on the material finding while re-listing the hardening one verbatim under the Optional section, the reviewer prompt provably flips between the two briefs, and a mode flip on an identical diff always re-reviews (no cross-mode marker ride), and the command-string flag transport provably flips the mode. The legacy T1–T64 suite runs pinned to security mode, proving the pre-0.14.0 machinery unchanged.

### Security
- **Closed a family of review-target hijacks in the commit gate: message text containing `; git -C <dir> commit ...` could redirect the review to a clean decoy repo (empty diff → silent allow) while the real repo's diff committed UNREVIEWED.** Four vectors, each end-to-end verified then regression-locked (the finder round was the toolkit's own two-brain review: Codex + a fresh-context audit each caught vectors the first fix missed):
  - `-m "..."` **message injection** — the `-C <dir>` extraction (`GITC_RE`) matched the RAW command while commit detection (`GIT_RE`) matched the quote-scrubbed one, so quoted message text steered target resolution; it also fired *accidentally* (commit messages here routinely quote git commands). `GITC_RE` now matches the scrubbed command, same as `GIT_RE`.
  - **Heredoc message injection** — a message fed via `git commit -F - <<'EOF'` is unquoted stdin data, so an embedded decoy line survived the quote scrub. Heredoc BODIES are now scrubbed out like quoted strings (the operator line survives, so heredoc commits are still detected; the delimiter word is parsed the way the shell reads it — a single shell word built from any mix of unquoted, single-quoted, double-quoted (escape-aware, so `<<"END\"MSG"` resolves to `END"MSG`) and backslash-escaped segments, so `<<'END@MSG'`, `<<E'OF'` and `<<'E'O"F"` all resolve to their true terminator instead of a short prefix that would swallow a later commit; multiple heredocs on one line are queued so the *second* body can't slip through; operators count only at unquoted, uncommented positions, so a quoted `"<<EOF"` or a `# <<EOF` comment — including one opened right after a control operator like `true;# <<EOF` or `case x in x)# <<EOF` — can't queue a bogus delimiter that would eat a later real commit line; `<<<` herestrings untouched).
  - **Delimiter-lexer completion (round 9) — full Bash quote-removal so no crafted delimiter escapes the body scrub.** The prior pass treated `#` and backtick as word boundaries and had no ANSI-C / locale-quote / literal-`$` handling, so an adversarial delimiter could resolve to the wrong word and let the body (with an injected decoy) survive. The lexer now matches bash exactly: `#` and backtick are ordinary characters *once the word has begun* (`<<EOF#TAG` terminates on `EOF#TAG`, ``<<`X` `` on `` `X` ``) while a `#` at word start is a comment (no heredoc); `$'...'` ANSI-C segments are decoded with the full escape set (`\t\n\r` &c., octal `\nnn`, hex `\xHH`, control `\cX` over the whole ASCII range incl. `\c?`→DEL, and `\u`/`\U`→UTF-8); `$"..."` is a double-quote segment; a bare `$` is a literal delimiter char (`<<E$F`); `\$` and `` \` `` are removed inside `"..."`; an empty delimiter (`<<''`) queues (its terminator is the first blank line); a decoded NUL (`\c@`, `\x00`, `\000`) **truncates** the delimiter exactly as bash does, so the computed terminator matches instead of carrying a stray zero byte that would swallow a later commit. The main scanner now tracks `$'...'` state and carries single/double/ANSI-C quote state **across newlines**, so a fake `<<EOF` hidden inside a multi-line quoted string can't queue a bogus heredoc that hides a later real commit. The scrub awk runs under `LC_ALL=C` (byte-exact emission) and uses decimal numeric literals so it behaves identically on gawk and mawk.
  - **Fail-closed when the command can't be sanitized.** awk-missing/failing with **no** heredoc still falls back to the raw command (quote scrub applies, detection never silently disabled); but if a heredoc (`<<`) is present and the scrub pass can't run, a body could smuggle an unreviewed decoy past the scrub — there is no safe fallback, so the gate now DENIES loudly (mirroring the jq-missing path) instead of reviewing unsanitized text.
  - **Escaped-quote spill** — inside `"..."` a `\"` does not close the string, but the naive quote pairing thought it did, letting the message tail (decoy included) escape the `QUOTED` sentinel. The scrub is now escape-aware for the forms that support backslash escapes (`"..."`, `$'...'`); plain `'...'` cannot contain an escaped quote, so its naive rule is exact.
  - **`QUOTED`-sentinel collision** (introduced by the first fix, caught in the same review) — a quoted `-C` value scrubs to the literal token `QUOTED`, which then resolved as a *relative path ahead of the session cwd*: a plantable clean repo named `QUOTED` became a decoy. A candidate that is exactly `QUOTED` (or a `QUOTED/...` artifact) is now discarded; a real path merely *containing* the word (e.g. `/srv/QUOTED-project`) keeps its review — over-discarding would have silently skipped it (also caught in review).

  Accepted trade-off (documented in the hook): a *quoted* `-C` path no longer resolves — extraction degrades to `cd`/session-cwd, the same repo in the common case; protecting `-C "..."` from the scrub would itself be spoofable by message text, reintroducing the bypass. Regression-locked by new `tests/gate-cap.sh` cases T37–T64 — the message/quote/heredoc vectors (T37–T53) plus the round-9 delimiter-lexer family (T54–T64: mid-word `#`, backtick delimiter, `$'EOF'`, the full ANSI-C decode family incl. octal/hex/control/`\c?`/`\u` and invalid-escape-kept-literal, control on punctuation, mawk-parity of the decoder, `<<"END\$MSG"` `\$`-escape, `$"EOF"` locale quote, literal-`$` delimiter, fake `<<EOF` inside `$'...'`, empty `<<''` delimiter, fake `<<EOF` inside a multi-line `"..."` string, NUL-truncation of the delimiter (`\c@`/`\x00`/`\000` end the string as bash does), and awk-fail-with-heredoc fail-closed) — **213 checks at the time of the lexer pass** (the suite now totals 237 with the ADR-022 policy cases above); every attack case was proven to FAIL against its pre-fix gate before the fix landed. Honest scope note: the scrub is a regex/line-based pass, not a full shell parser (it does not model command/arithmetic substitution, and quote state is line-approximate except for the delimiter-hiding cases hardened above) — the gate stays a guardrail against accidental and casual redirection, not a sandbox against a determined adversarial shell author.

### Added
- **The commit gate is now the ONLY sanctioned Codex diff-review loop — hand-run `codex exec` on a diff is banned (ADR-021).** All the anti-loop machinery (findings ledger, round counter, cap, ceiling) lives *inside* the gate and only counts rounds that go through it. A hand-driven `codex exec` review touches none of it — no memory, no cap — so it reproduces the pre-ADR-019 uncapped trickle by hand and never self-terminates (the human ends it, every time). The rule now lives in `two-brain-convergence.md` ("THE ONE RULE THAT MAKES THE CAP REAL"), `~/.codex/AGENTS.md`, and the `codex-AGENTS.md` template: route every diff review through `/ship` or the commit gate; if you catch yourself typing `codex exec` on a diff, stop and run `/ship`. A new real finding per round is *expected* — the CAP, not a perfect first review, ends the loop. *(Shipped in commit `d8ea45f` just after `v0.13.0` was tagged; its note was mistakenly retro-added to the released [0.13.0] entry below and has been moved here, restoring [0.13.0] to its tagged content.)*
- **KI-003 logged:** the `/ship` Step 4.5 and `/before` Step 5.6 convergence loops cap their rounds in PROSE only — contrary to ADR-019's wording they don't share the gate's counter/ledger state files. The commit-time gate still bounds what can land; the pre-commit token burn is what's unbounded. Wiring the skills to the gate's rounds/ledger files is deferred to its own design session.
- The global `~/.claude/CLAUDE.md` (owner-local, not in this repo) gained the ADR-021 ban so sessions in *other* repos — where the KI-002 loop actually happened — load it too.

## [0.13.0] — 2026-07-21

> **Heads-up — reinstall required.** The commit gate's behaviour changed. Your
> currently *installed* hook keeps the old behaviour until you `git pull` this
> toolkit and re-run `install.sh`, which re-copies the hook to
> `~/.claude/hooks/`. Until you reinstall, ADR-019 is not live on your machine.

### Added
- **The commit gate now has memory, project context, and a convergence ceiling — so the Claude↔Codex review loop self-terminates on genuine agreement instead of escalating routine code to you (ADR-019).** The old gate reviewed a *cold diff* on every recommit through a fresh, memoryless `codex exec` that could see only the diff — so it re-raised findings you had already resolved and invented false ones the real code disproves, and the round cap only ever *escalated to the human*, making you the loop's off-switch on every project. That was the token bleed. Four inputs fix it:
  - **Findings ledger (memory).** A per-(repo, HEAD) ledger beside the round-counter records each finding's fingerprint + text and feeds them back into the next round's prompt, so Codex stops re-raising a finding you already fixed unless the current code still shows it.
  - **Project context.** The review runs read-only *from the repo directory* with the changed-file list, so Codex reads the real surrounding code and false findings die. On a directory-access failure it falls back to a diff-only review from a throwaway empty directory — never reading an unrelated tree.
  - **Convergence pressure.** A finding first appearing in a later round is tagged `[LATE]`; "converged" is defined as an LGTM reached *with* the prior findings and real code in view, not merely "no new finding this round".
  - **Ceiling.** Above the soft round cap (default 3, `CODERV_GATE_ROUND_CAP`) sits a hard ceiling: `CODERV_GATE_ROUND_MAX` (default 5) and `CODERV_GATE_DIFF_BUDGET` (default 800000 transmitted bytes). Below the cap every material finding blocks as before. Between the cap and the ceiling, material findings are ordinary retry-denies (no escalation) so the loop can actually reach the ceiling. At the ceiling, **only a still-open security or data-loss finding blocks** (the durable owner escalation — the gate refusing to auto-merge a security hole); every other residue self-terminates as an allow-with-caveat with the findings surfaced verbatim.
- **The Claude↔Codex argument now happens *before* the commit, in `/ship` (ADR-018).** `/ship` gains a pre-commit convergence loop: it assembles the diff exactly as the gate does (including untracked files), runs one exhaustive Codex pass, and batch-fixes without committing — so by the time the commit-time gate runs, it is a fast confirmation of an already-agreed diff rather than the place the argument starts. `/ship` never writes the gate's trust marker (that would silently disarm the backstop); the gate stays the sole author of its own marker.

### Changed
- **The round-state file gained a 4th field** (transmitted bytes per round) for the ADR-019 byte-budget ceiling. Legacy 3-field records written by an older gate are still counted toward the round total (contributing zero bytes), so an in-place upgrade never miscounts.
- **The gate's denied cache-marker gained an `escalated={0,1}` flag** so an ordinary/middle-tier deny retries per the adjudicate-then-retry contract while a ceiling security block stays escalated; an `escalated=1` marker is the top precedence key and can never be overwritten by a later allow of the same diff. Legacy flag-less markers are read conservatively (escalated when at/above the cap, ordinary below it).

## [0.12.1] — 2026-07-20

### Fixed
- **System-map cards now size to their content instead of a fixed width.** Each card measures its widest row and clamps to it (170–340px), so long service names and deep file paths no longer overflow the box; overflow text is truncated code-point-safely (emoji never split) with the full value on hover, rows are re-spaced so text no longer crowds, and the author grid scales from the origin so wider cards get room without losing negative coordinates.
- **System-map: labels nudged clear of cards can no longer be clipped by Fit.** The bounds were framed before the label-collision nudge ran (it runs in a later animation frame), so a nudged label could fall outside the viewport. Bounds are now re-measured and re-framed one frame after the nudges settle.
- **System-map: confirmed parallel reversed edges (A→B and B→A) do not stack their labels.** The edge's bow direction already flips with its endpoints, so the existing fan sign keeps forward and reversed edges on distinct sides — verified by render; no change was needed (the earlier concern was a false positive).

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
