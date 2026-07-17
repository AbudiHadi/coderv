# Session Handoffs — toolkit

> End-of-session notes for the toolkit repo. Newest at top.

---

## 2026-07-17 (commit approval) — gate denied its own commit twice; 4 fixes, 2 rejections, then shipped

Owner said "approve" → ran the commit per ADR-008; the codex gate live-fire denied FIVE rounds (working as designed — each fix changed the diff, triggering re-review; the all-rejected fifth round converged via the cache and the commit landed). Adjudicated 15 findings:
- **Fixed (7):** merge/cherry-pick/revert/rebase integrate commits the gate can't see — clean worktree warns loudly instead of silently skipping, dirty worktree labels every outcome "incoming commits UNREVIEWED" (even LGTM); `-C` repo resolution tied to the commit-creating invocation (`git -C /other status && git commit` no longer reviews the wrong repo) with flags allowed around `-C`; review cache keys on repo+HEAD+diff (identical diff in another repo reviews afresh); jq-missing warning triggers on all commit-creating subcommands, not just "commit"; separate-arg long flags (`--git-dir X --work-tree X commit`) no longer bypass detection.
- **Rejected, surfaced to owner (5):** "stdin may not reach codex alongside a positional prompt" — codex-cli 0.144.5 help documents piped stdin IS appended as a `<stdin>` block, and every live deny quoted diff content, proving delivery; "staged-hunk-with-reverted-worktree" / "cache keys worktree not index" / "review the index for plain commits" (the same family, raised THREE times) — the previously adjudicated accepted limitation in the hook header, plus the ADR-008 flow commits via `git add -A` so index = worktree for every gated commit, and reviewing the index instead would miss the common `add && commit` compound (PreToolUse fires before the add); "untracked binaries reviewed only as 'Binary files differ'" — an LLM cannot audit binary payload bytes, `--binary` would burn the 150KB budget on unreviewable base85, and the diff already discloses the binary's presence and path. Round 5 rejected wholesale: two "wrong capture group" claims (Codex miscounted — group 9 is correct for both SUBCMD and the `-C` dir; disproven empirically by suite cases T1/T2/T4/T5, which fail under Codex's counting) and "diff modifies CLAUDE.md/SESSIONS/DECISIONS which AGENTS.md forbids" — AGENTS.md scopes the CODEX reviewer ("writing them is the conductor's job", AGENTS.md:37-40); Claude is the conductor.
- Verified by a 14-case stubbed-codex suite (isolated HOME, scratch repos) — 14/14 pass, incl. regressions. Both hook copies re-synced byte-identical. Grounding gate also fired on this session's first edit — conscious-skip receipt declared (grounding was done: CLAUDE.md + handoffs + full hook source read first).

---

## 2026-07-17 (later) — gap-scan list worked: gate hardened, /ship routed through it, docs de-staled

**Gate activation verified (handoff item):** fresh session after restart, scratch repo, code-diff commit → gate fired and DENIED with two real Codex findings (unvalidated divisor, arithmetic-expression injection). The 4th gate is live.

**Hook hardened** (`hooks/codex-review-gate.sh`, both copies byte-identical, 10/10 pipe tests with a stubbed codex):
- Detection: command-position regex (quoted strings scrubbed first) — catches `git -C <dir>` / `-c` / long flags + merge / cherry-pick / revert / rebase; `echo "git commit"` and commit-message mentions no longer trigger.
- Untracked files included in the reviewed diff AND the docs-only check (new-file-only bypass closed).
- >150KB diffs: every outcome (LGTM, deny, context) states loudly that only the first 150KB was reviewed.
- `codex exec` now `-s read-only` (config marks /root trusted — reviewer could otherwise run commands).
- Missing jq: loud warning on commit-like commands instead of silent bypass; `cd` handles quoted paths + leading `~`; `git -C` wins over `cd` for repo resolution.
- Accepted limitations documented in the header: pre-command tree on generate-then-commit; staged-hunk-with-reverted-worktree in mixed commits; diff goes off-box to OpenAI (owner-accepted); `$VAR` paths unexpanded.

**/ship bypass closed (ADR-008):** scorecard approval pause unchanged, but after "approve" Claude runs the commit via Bash so it passes the gate. Outside-terminal commits still bypass (unfixable from inside Claude Code — documented). Installed skill copy synced, marker restored.

**Docs de-staled:** AI-WORKFLOW-PLAN.md header → OPERATIONAL/verified; MEMORY.md + reference memory (v0.6.0 pin → 0.8.0, 6 hooks/4 gates, verified claim); install.sh banner → four gates + `install_gate_hook` grew optional statusMessage (output matches live settings entry exactly); README ×3, overview ×3, skills.md gate table, CLAUDE.md header → 6 hooks/4 gates. CHANGELOG [Unreleased] documents the hardening + ADR-008. Historical entries (v0.8.0 "three gates") left untouched — append-only.

**Also:** removed `tracked.txt` (7-byte "edited" test debris at repo root, flagged by the scan). Gap-scan JSON stays LOCAL-ONLY at `docs/GAP-SCAN-2026-07-17.json` — now gitignored (`docs/GAP-SCAN-*.json`): 285KB of internal scan output incl. security-flagged evidence has no business in a repo strangers clone. All 24 confirmed findings now fixed, accepted-and-documented, or historical.

**Fresh-context reviewer round (/ship step 4.5, quotes machine-verified):** caught 2 stale "three always-on gates" lines in README's hero (fixed), 3 real detection bypasses — env-prefix `FOO=1 git commit`, quoted-text `git -C /etc` dir hijack, apostrophe scrub-order — all fixed (env-prefix regex; `-C` extraction now command-position-anchored with repo-candidate priority git-C → cd → cwd; scrub double-then-single), attached `-C<dir>` form (fixed), installer never refreshing statusMessage on already-wired hooks (fixed), mktemp leak on harness timeout (trap added). Accepted + documented: `sh -c` wrapper commits undetected. REJECTED (surfaced per transparency rule): "broken grep makes jq-warning silent" — a box without working grep can't run any toolkit hook; contrived.

**State evidence (verbatim, end of session — after reviewer-round fixes):**
```
$ git status --short
 M .gitignore
 M CHANGELOG.md
 M CLAUDE.md
 M README.md
 M docs/DECISIONS.md
 M docs/SESSIONS.md
 M docs/overview.md
 M docs/skills.md
 M install.sh
 M skills/ship/SKILL.md
?? hooks/codex-review-gate.sh          # GAP-SCAN json now gitignored
$ git log --oneline -1 && cat VERSION
8e3ac12 v0.8.0: anti-dumb-zone system — 3 gate hooks, /coderv front door, computed scorecard
0.8.0
$ bash -n hooks/codex-review-gate.sh && bash -n install.sh   # SYNTAX-OK
$ diff -q hooks/codex-review-gate.sh ~/.claude/hooks/codex-review-gate.sh   # RESYNCED, no output
$ stubbed-codex pipe suites: 10 passed 0 failed, then post-reviewer 8 passed 0 failed
```

**COMMIT PENDING APPROVAL:** /ship ran to completion — scorecard 100% (7/7 runnable gates), commit message drafted (in the /ship reply + reproducible from CHANGELOG). Context gate ended the session at the approval pause. NOT committed.

**Next session should probably:**
- Say "approve" → run `git add -A && git commit` (the codex gate will review once, ~1-3 min; adjudicate any deny per its message). Commit message: subject "Harden codex-review-gate + route /ship commits through it (ADR-008)" + why-body from this entry.
- Release run: version bump 0.8.0 → 0.9.0 (CHANGELOG [Unreleased] → dated), `./release.sh`, website site.ts sync.
- Owner to confirm ADR-008 (Claude-runs-commit-after-approve) — logged as adjustable default, veto welcome.
- NO new scans — owner explicitly said the ultra scan burned his tokens; the gap-scan work is DONE.

---

## 2026-07-17 — codex-review-gate: 4th gate, Codex adversarial review before every commit

**What shipped (to disk, NOT committed — /ship pending):**
- `hooks/codex-review-gate.sh` — PreToolUse/Bash gate: pipes the outgoing diff to Codex CLI before any `git commit`; findings deny once, agent adjudicates (rejected findings must be surfaced to owner), same-diff retry passes (24h hash cache at `~/.claude/coderlap/codex-reviewed/`). Skips: non-commit, non-git, empty/docs-only diffs. Codex down/auth lapsed → allow + loud warning. Kill: `CODEX_REVIEW_OFF=1` / `CODERV_GATES_OFF=1`.
- `install.sh` — wires/unwires it like the other gates (`install_gate_hook ... "PreToolUse" "Bash" 240`).
- `CHANGELOG.md` — entry under `[Unreleased]` (version NOT bumped yet).

**State evidence (verbatim, end of session):**
```
$ git status --short            # toolkit repo — UNCOMMITTED
 M CHANGELOG.md
 M docs/SESSIONS.md
 M install.sh
?? hooks/codex-review-gate.sh
$ git log --oneline -1 && cat VERSION
8e3ac12 v0.8.0: anti-dumb-zone system — 3 gate hooks, /coderv front door, computed scorecard
0.8.0
$ codex --version && codex login status
codex-cli 0.144.5
Logged in using ChatGPT        (login-rc=0)
$ jq -r '.hooks.PreToolUse[].matcher' ~/.claude/settings.json
Edit|Write|MultiEdit|NotebookEdit
Bash                            # ← codex-review-gate registered
```
- Pipe-tests all passed: non-commit/docs-only/empty → silent allow; planted-bug diff → deny with real Codex finding; same-diff retry → cached allow.
- Live-fire proof FAILED in this session only (no hot-reload of hook config): `git commit` in the scratch repo went through unreviewed (`[main 40992df] live gate proof`). Activation = owner opens `/hooks` once or restarts the session.

**Context:** this implements the machine gate of the owner's two-model workflow (`/root/AI-WORKFLOW-PLAN.md`; Claude implements, Codex reviews). Codex CLI 0.144.5 installed today, device-auth login done, global rules at `~/.codex/AGENTS.md`.

**Codex review of the hook itself (manual pipeline run, adjudicated):**
1. FIX — untracked files bypass review (`git diff HEAD` misses them; new-file commits skip the gate).
2. ACCEPTED LIMITATION — compound commands that generate files then commit review the pre-command tree; PreToolUse cannot see the future tree. Document it.
3. FIX — >150KB diffs are truncated for review but the hash cache marks the FULL diff reviewed; must warn loudly instead.
4. FIX — `git -C /path commit` doesn't match the "git commit" substring → skips the gate; quoted `cd` paths also unhandled.
5. FIX (trivial) — missing jq = silent bypass; emit a hand-built static JSON warning instead.

**Ultra gap-scan (174 agents, 3-skeptic panels): 24 confirmed / 32 refuted.**
Full JSON: `docs/GAP-SCAN-2026-07-17.json`. The CRITICAL one — hook's
`permissionDecision:"allow"` paths auto-approved the ENTIRE Bash command
(bypassing user permission prompts for anything containing "git commit") —
was FIXED same session in both copies: allow paths now emit only
systemMessage+additionalContext and defer to the normal permission flow.
Top remaining (overlaps Codex's own review): git -C /merge/cherry-pick
bypass detection; untracked-file commits unreviewed; 150KB truncation
certifies full-diff hash; codex exec needs explicit `-s read-only` (config
marks /root trusted); /ship's "user runs git commit" step bypasses the
hook entirely (hook fires only on Claude's Bash); doc-count staleness
("three gates"/"5 hooks" in banner/CLAUDE.md/README); MEMORY.md
"OPERATIONAL" overclaim. 14 verify agents died on session rate limit
(low-sev tail unverified). Two subagent security warnings in the scan run
— review journal before trusting those two findings' evidence.

**Next session should probably:**
- Work docs/GAP-SCAN-2026-07-17.json confirmed list top-down (critical done; high next: detection regex incl. git -C/merge, untracked files, truncation-hash, -s read-only, /ship integration decision).
- Verify the gate fires after a session restart (commit a code diff, expect Codex deny or LGTM message).
- Check the ai-workflow-gap-scan workflow results (may overlap with the findings above).
- Run /ship for this change; version bump 0.8.0 → 0.9.0 belongs to the release run.

---

## 2026-07-15 (release run) — doc lint clean + reviewer qualifiers, v0.8.0 shipped

- Doc lint (subagent sweep, quotes machine-verified): 2 findings, 0 fixed — the "stale" spec/receipt is the ACTIVE v0.8.0 task's (needed by /ship), and the context-window calibration item is already an honest open follow-up below. Freshness stamped.
- Release-run fresh-context reviewer: 4 objections, quotes verified 8/8. Fixed: "once per session" wording now carries "(re-arms after compaction)" in CHANGELOG.md, docs/skills.md, and the hook's own block message (context-gate.sh:103). Deferred: 200k window calibration (owner's recorded follow-up). Noted: release.sh --check clean-tree gate is definitional pre-commit; TRIGGER/SKIP + tag-free gates hand-verified.
- Grounding gate fired on its own repo during the fix (docs edits passed, code edit blocked) — conscious-skip receipt declared. The dogfood works.

---

## 2026-07-15 — v0.8.0 built: anti-dumb-zone system — 3 gates, /coderv, scorecard

**What shipped (to disk; commit pending scorecard approval — this entry is part of that commit):**
- 3 gate hooks, tested (13 simulated + 4 regression cases pass): `hooks/grounding-gate.sh` (PreToolUse — receipt or no code edit), `hooks/compact-rehydrate.sh` (SessionStart/compact — snapshot outranks summary), `hooks/context-gate.sh` (Stop — warn 60% / block 75% once per session, re-arms after compaction).
- `/coderv` — 7th command, the front-door router (ADR-007).
- Skill upgrades: `/before` writes grounding receipt + spec checklist (keyed by project root); `/ship` gains fresh-context reviewer + computed verification scorecard; `/session` handoffs require this verbatim evidence block; `/lint` sweeps via subagent, machine-verifies quotes, flags stale coderlap artifacts, stamps freshness.
- `install.sh` installs/wires/uninstalls the 3 gates idempotently (verified in a fake $HOME). ADR-006/007, CHANGELOG, VERSION 0.8.0, README/docs counts updated.
- Fresh-context adversarial review ran on the whole change set: 9 findings, all quotes machine-verified 9/9, 8 fixed, 1 accepted (7-day marker expiry on ancient resumed sessions).

**State evidence (verbatim, at write time):**
```
$ git log --oneline -3
1e505f0 v0.7.0: close the three gaps — /lint, session rotation, release gate
4452556 Add project-context SessionStart hook — sessions start knowing where work left off
227aaf8 v0.5.0: coderv-router hook + multi-host install (Codex, Gemini)
$ git status --short (abridged)
 M CHANGELOG.md / CLAUDE.md / README.md / VERSION / docs/{DECISIONS,architecture,overview,skills}.md
 M install.sh / skills/{before,lint,session,ship}/SKILL.md
?? hooks/{compact-rehydrate,context-gate,grounding-gate}.sh  ?? skills/coderv/
$ cat VERSION
0.8.0
$ ./release.sh --check → ok VERSION / ok CHANGELOG match / ok dated / BLOCKED working tree not clean (definitional pre-commit)
```

**Gotchas the next session should know:**
- The gates are LIVE on this machine (wired in /root/.claude/settings.json). Kill switch: `CODERV_GATES_OFF=1`. First code edit in any doc-system project now requires a /before receipt — including this repo.
- **context-gate fired on its own build session and reported 113%** — the 200,000 default in `CODERV_CONTEXT_WINDOW` underestimates this model's real window, so the gate fires late (or reports >100%). First follow-up: calibrate (set the env var in settings.json `env`, or cap the displayed pct at 100 and treat unknown windows conservatively). The firing itself was correct behavior — the session WAS deep in long-context territory.
- Hook stdin gotcha (cost a debug cycle): `python3 - <<'PY'` eats stdin for the program itself — hook JSON must travel via env var (`CODERV_HOOK_INPUT`). Pattern is in all python hooks now.
- All coderlap artifacts (receipts/specs/state) are keyed by PROJECT ROOT path (dir with CLAUDE.md), `/`→`-`, under `~/.claude/coderlap/`.
- v0.6.0/v0.7.0 GitHub releases still unpublished (tags exist); v0.8.0 will join the queue — `gh release create` is the one manual step after tagging.

**Next session should probably:**
- If commit approved: run `./release.sh` (tags, pushes, syncs website) then `gh release create v0.8.0`.
- First field test: `/coderv <task>` on a downstream project (alrafiq was queued for /lint's field test — do both in one run).

---

## 2026-07-13 — v0.7.0: the gap-closing release — /lint, session rotation, release gate

**What shipped:**
- `/lint` skill (ADR-005) — the missing ingest→query→**lint** operation; router patterns added; skills.md/README/CLAUDE.md updated to the 6-command surface.
- `/session` rotation step — >20 entries → newest 10 stay, rest to SESSIONS-ARCHIVE.md (append-only).
- `release.sh` — the VERSION/CHANGELOG/tag/website ritual as a refusing machine gate (`--check` for dry runs); CLAUDE.md ritual rule now points at it ("never tag by hand").
- Context: gaps were identified by field use on Al-Rafiq the same day (rule flip-flops, stale TODO lists, the website stuck at 0.5.0) — each gap maps 1:1 to a shipped fix.

**Gotchas the next session should know:**
- release.sh website sync builds as the site repo's OWNER (root-owned toolkit vs appuser-owned site) and needs `CODERV_SITE_DIR` when the site isn't at /home/appuser/apps/coderv-docs.
- The v0.6.0 AND v0.7.0 GitHub releases are still unpublished (owner approval pending) — tags exist.

**Next session should probably:**
- Run `/lint` on a real downstream project (alrafiq) as its first field test.

---

## 2026-04-24 — `/docify` approved on toolkit, **not yet shipped**

**What shipped (to disk, not to git):**
- `CLAUDE.md` at repo root with toolkit-specific rules + shared markers.
- `docs/` folder with 3 reference docs promoted `.draft.md` → `.md`: `overview.md`, `architecture.md`, `skills.md`.
- Empty scaffolds: `docs/DECISIONS.md`, `docs/KNOWN-ISSUES.md`, `docs/SESSIONS.md`.

**In flight (not yet shipped — real status):**
- `git status` shows `CLAUDE.md` + `docs/` as **untracked**. Nothing committed yet.
- `VERSION` still reads `0.3.8` — needs bump to `0.3.9`.
- No `CHANGELOG.md` entry for 0.3.9 yet.
- No tag, no push, no GitHub release.
- Website repo (`/home/appuser/apps/coderv-docs/`) is in the same state — its `package.json`, `src/config/site.ts` both still read `0.3.8`, and its `CLAUDE.md` + `docs/` are also untracked.

**Gotchas:**
- A prior compacted session summary claimed the v0.3.9 ship was complete. It was not — the summary captured intent, not state. Always verify with `git status` + `git log` + `cat VERSION` before trusting a "shipped" claim in a handover.
- This repo's CLAUDE.md is smaller than the website's because the toolkit is smaller — but shares the same marker system. Syncing rules across both is a manual step.
- LICENCE and the Nginx-served equivalent at coderv.dev must stay identical. When you edit one, mirror the other.
- `docs/skills.md:30` mentions `.draft.md` on purpose — it documents `/docify`'s drafts-first model. Don't "clean it up".

**Next session should probably:**
1. Bump: this repo's `VERSION` → `0.3.9`; website's `astro-site/package.json` + `astro-site/src/config/site.ts` → `0.3.9`.
2. Add `## [0.3.9]` entry to this repo's `CHANGELOG.md` ("First real docs for CoderLap itself via `/docify`").
3. Commit both repos with explicit file lists (don't `git add -A`):
   - Toolkit: `CLAUDE.md docs/ VERSION CHANGELOG.md`
   - Website: `CLAUDE.md docs/ astro-site/src/config/site.ts astro-site/package.json`
4. Tag `v0.3.9` on this repo, push both, create GitHub release.
5. Rebuild website: `cd /home/appuser/apps/coderv-docs/astro-site && npm run build && pm2 restart coderv-docs`.
6. Verify: `curl -s https://coderv.dev/ | grep -oE "v0\.3\.[0-9]+"` → `v0.3.9`.

---

<!-- New sessions above this line, newest first -->
