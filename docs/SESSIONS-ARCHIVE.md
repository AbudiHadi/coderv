# Session Handoffs — toolkit (ARCHIVE)

> Rotated out of `SESSIONS.md` on 2026-07-19 to keep it under the ~500-line threshold. Newest at top. Append-only — content byte-identical to the originals.

---

## 2026-07-19 (later 7) — SHIPPED later-6's work: 3 commits, gate caught 6 real bugs en route

Resumed the "later 6" handoff and ran `/ship`. The three changes landed as three
commits by concern — but the codex-review-gate did serious work first, denying
repeatedly and each time surfacing a **new, distinct, real** defect (never the
same finding twice — this was convergence, not a loop):

1. **`cada876`** — `install.sh` gate-roster fold (LGTM first try on its own diff).
2. **`e86b853`** — `/coderv` autonomy. Gate-caught & fixed before it landed:
   - **/verify skill gap** — the pipeline referenced a `/verify` skill the toolkit
     doesn't ship → reworded to an inline **verify** step (drive the flow, observe).
   - **config-not-exempt** — "skip verify for docs/config-only" was too broad;
     config (hooks/CI/manifests) usually has a validation path → only pure
     docs/prose diffs skip now.
   - **handoff scan too shallow** — `grep -m1 '^## '` returned only the heading, not
     the "next session should…" body → replaced with an **awk that extracts the
     whole newest DATED entry**, then hardened twice more: **fence-aware** (a `##`
     pasted inside a ``` code block no longer miscounts) and **no truncating cap**
     (an earlier `head -40` clipped the actionable tail at offset 43 — now `head
     -300` runaway-guard only).
3. **this commit** — `codex-review-gate.sh` duration_ms + file/line emit
   (committed together with this SESSIONS entry). Gate-caught & fixed:
   - **leading-zero line** (`foo.js:08`) is invalid JSON for `--argjson` on jq 1.6
     → base-10 normalise `$((10#…))` before jq (jq 1.7 tolerates it; downloaders on
     1.6 wouldn't).
   - **endpoint false-match** — the file:line regex matched `127.0.0.1:3000` and
     `example.com:8080` as source anchors → require a **known source extension**
     (SRC_EXT allowlist), not just any dotted token.

One gate finding was **rejected with proof** (transparency rule): "the date
fallback breaks under `set -e`" — the script has no `set -e` (only `set -o
pipefail`, line 52); simulated a failing `date`, hook reached the end with
`duration_ms=null`. The gate also flagged "SESSIONS.md is protected
source-of-truth documentation" — that rule IS real (`~/.codex/AGENTS.md` #2) but
it binds **Codex the reviewer**, not the conductor: the same rule says "writing
them is the conductor's job." Claude (the writer) editing this handoff is exactly
what it prescribes — role confusion, not a violation. Both findings were the gate
reviewing the whole working tree, not the staged subset.

**Still deferred (owner's call — changes live behaviour):**
- **Re-install the gate hook** (`install.sh` re-run, or copy `hooks/codex-review-gate.sh`
  → `/root/.claude/hooks/`) so the live gate emits the new duration/anchor fields.
- **`sudo -u appuser pm2 restart coderv-loop`** so PROD (:3130) serves the new viewer.
- ~~Log /coderv autonomy as an ADR~~ — **DONE this session: ADR-013** (extends
  ADR-007; records bare-scan-propose + scout-when-confused + always-verify, and
  the six gate-caught defects as evidence the reviewer earns its latency).

---

## 2026-07-19 (later 6) — 3 features built, ALL VERIFIED, ALL UNCOMMITTED (context gate)

**What was built this session (nothing committed — see evidence block):**

1. **install.sh gate-roster dedup + fold** (`install.sh`) — the install & uninstall gate rosters were typed twice (orphaned-config bug). Now ONE `GATE_ROSTER` array both paths iterate; folded `install_router_hook`+`install_context_hook`+their uninstall twins into the generic `install_gate_hook`. **−197 net lines.** Delimiter is `^` (non-whitespace, so `read` keeps empty fields — a tab silently collapses them; I hit that bug and fixed it). VERIFIED: install→settings.json byte-identical to a captured baseline, uninstall→`{}`, idempotent, foreign-hook survival all pass. shellcheck clean.

2. **/coderv autonomy** (`skills/coderv/SKILL.md`) — bare `coderv` (no args) now auto-scans state (Step 0) and PROPOSES the single most likely next task; ambiguous requests spawn a read-only `Explore` scout to find the real target (Step 1) instead of guessing; an inline verify step (drive the flow, observe it works) is now mandatory on code changes before `/ship` (Steps 3–4). Worded as plain **verify**, not a `/verify` skill invocation — the toolkit ships no verify skill, so a skill reference would dangle on a clean install (codex-review-gate caught this during /ship). Description block + argument-hint updated. TRIGGER/SKIP intact, frontmatter valid. **This is an ADR candidate (see follow-up).**

3. **coderv-loop two-brain viewer upgrade** (`/home/appuser/apps/coderv-loop/` — NOT git) — the page on 9130→3130. Added: project chip (which repo), session summary bar (commits/passed/denied/findings), relative "2m ago" timestamps (live-tick), "took 8.2s" review duration, structured findings with `file:line` anchor chip (click=copy) + collapsible "see details", liveness heartbeat, expand/collapse-all, favicon 204. Gate (`hooks/codex-review-gate.sh`) extended to EMIT the new fields: `duration_ms` on verdict + `file`/`line` on findings — both pure side-effects, never touch allow/deny. VERIFIED end-to-end with Playwright headless against a synthetic log: project followed saadk, counts 2·1·1·2, `server.mjs:62` anchor, durations 8.2s/13s, collapse toggle, heartbeat stale, live-append streamed non-replay. Zero console errors.

**In flight (not shipped):**
- **Nothing mid-edit** — all three are at rest and verified. Blocker is only the context gate.
- **coderv-loop PROD (PM2 on 3130) still runs OLD code** — edits are on disk only. To see the new viewer: `sudo -u appuser pm2 restart coderv-loop` then tunnel 9130→3130.
- **Gate edit is in the TOOLKIT SOURCE only** — the installed live hook `/root/.claude/hooks/codex-review-gate.sh` is the OLD copy. New fields won't populate the real log until `install.sh` is re-run (or the hook copied). Left uninstalled deliberately (owner's call — changes live behavior).

**State evidence (verbatim):**
```
$ git -C /root/claude-docs-toolkit status --short
 M docs/SESSIONS.md
 M hooks/codex-review-gate.sh
 M install.sh
 M skills/coderv/SKILL.md

$ git -C /root/claude-docs-toolkit log --oneline -3
b1816dc Release 0.10.1: sharper session handoff + doc-lint cleanup
f8a0314 Release 0.10.0: live-loop event log + coderv-loop dashboard
260ec4c Complete the live-loop event log: terminal outcomes + bounded flock

$ cat /root/claude-docs-toolkit/VERSION
0.10.1

$ git -C /home/appuser/apps/coderv-loop rev-parse --is-inside-work-tree
fatal: not a git repository (or any of the parent directories): .git
  (coderv-loop is NOT under version control — server.mjs + public/index.html edited on disk, 12:28–12:31)
```

**Gotchas the next session should know:**
- `coderv-loop` has **no git** — you can't `git diff` it; the disk IS the source of truth. Don't look for a commit.
- The gate's new jq-arg injection uses bash **arrays** (`DUR_ARG=(...)`, `LINE_ARG=(...)`), NOT `$(fn)` string-splitting — that was a deliberate shellcheck-clean refactor. Don't "simplify" it back.
- `file:line` parse requires a **known source extension** (`SRC_EXT` allowlist — js/ts/py/sh/… `foo.mjs:62`), NOT just any dotted token, so prose times (`12:30`) AND host/IP:port endpoints (`127.0.0.1:3000`, `example.com:8080`) don't false-match. (Tightened from "any dotted extension" after the gate caught the endpoint case — see later 7.)
- Playwright's bundled chromium isn't installed; drive headless via `executablePath: /usr/bin/chromium-browser` and wait on `domcontentloaded` + `.beat` (NOT `networkidle` — SSE keeps the connection open forever).

**Next session should probably:**
- **`/ship` the toolkit changes** (install.sh + coderv + gate) — suggest 3 separate commits by concern. Then decide on re-installing the gate hook + `pm2 restart coderv-loop` to make the viewer live.
- Log the **/coderv autonomy** design as an ADR (`/decision`) — bare-scan-propose + scout-when-confused + always-verify, alongside ADR-007.

---

## 2026-07-19 (later 5) — v0.10.1 shipped: session-handoff sharpening + doc-lint cleanup (gate denied TWICE, converged)

**What shipped (v0.10.1, tag pushed, website synced):**
- `skills/session/SKILL.md` — handoff close-out now prints the absolute repo path + queued items inline with the `/session last` pointer (owner's queued item from "later 3").
- Doc-lint fixes: `architecture.md` "three gate hooks"→"four" (+ADR-008); three `/docify` provenance banners (overview/architecture/skills) note hand-maintained + last-verified-2026-07-19 vs `f8a0314`; `DECISIONS.md` ADR-008 "pending owner veto" trailer corrected.
- `docs/SESSIONS.md` rotated 587→383 lines, 7 oldest entries → new `docs/SESSIONS-ARCHIVE.md` (byte-identical), and its stale HOW-TO-RESUME preamble refreshed to current reality.
- `VERSION` 0.10.0→0.10.1, `CHANGELOG [0.10.1]` cut. `release.sh` tagged/pushed/website-synced.

**State evidence (verbatim):**
```
$ git log --oneline -3
b1816dc Release 0.10.1: sharper session handoff + doc-lint cleanup
f8a0314 Release 0.10.0: live-loop event log + coderv-loop dashboard
260ec4c Complete the live-loop event log: terminal outcomes + bounded flock
$ git status --short
(clean)
$ cat VERSION
0.10.1
$ git tag --points-at HEAD
v0.10.1
$ git status -sb
## main...origin/main   (in sync)
```

**Gotchas the next session should know:**
- **The codex-review-gate denied this commit TWICE before LGTM — both times correctly.** Round 1: caught a REAL self-contradiction in the rotated HOW-TO-RESUME block ("no remote"/"shellcheck not installed" vs later entries proving the opposite) → fixed at root. Round 1 also raised 3 DRIFT findings that were FALSE — the drift-hunter was comparing against the **stale v0.10.0 spec** (base `260ec4c` = parent of the shipped v0.10.0). Rejected with proof + refreshed the `/before` spec to this task's base `f8a0314`. Round 2: caught a premature "v0.10.1 shipped" claim + my own stale self-report number — both fixed. Lesson: **a stale `~/.claude/coderlap/specs/` file makes the gate hunt drift against last release** — refresh or clear it at the start of a new release task.

**Next session should probably:**
- Tackle the parked `install.sh` cleanup — **start with #2** (gate roster typed twice, `install.sh:651-654` vs `675-678` — orphaned-config bug), **then #1** (fold router/context installers into generic `install_gate_hook`). Open with `/before` — it's the riskiest file (runs on every `git clone`).
- Optional: `gh release create v0.10.1` (and v0.10.0) for GitHub Release pages — `release.sh` printed the exact command.

---

## 2026-07-19 (later 4) — Doc lint: 5 findings, 4 fixed + SESSIONS rotated

Ran `/lint` (subagent sweep, all quotes machine-verified, 0 dropped). Findings & resolution:
- 🟠 #1 `architecture.md:28` — "three gate hooks" → **four** (+ADR-008). Fixed.
- 🟠 #2 three `/docify` provenance banners stamped `fbb1954` (v0.3.8) but bodies describe v0.10.0 → added "hand-maintained since — last verified 2026-07-19 against f8a0314". Fixed (overview/architecture/skills).
- 🟠 #3 `DECISIONS.md:255` ADR-008 marked `accepted` yet trailer said "pending owner veto" (self-contradiction; shipped in 0.9.0) → trailer replaced with "shipped in v0.9.0, no owner veto raised". Fixed.
- 🟡 #4 SESSIONS.md 587 lines > ~500 threshold → **rotated** 7 oldest entries (2026-07-17 gap-scan back to 2026-04-24 docify) into new `SESSIONS-ARCHIVE.md`, byte-identical, pointer left at bottom, and the stale HOW-TO-RESUME preamble refreshed. SESSIONS now ~383 lines / 10 dated entries — back under the ~500 threshold.
- 🟡 #5 KI-001 prevention rule "not landed" → **no change** — it's an owner-accepted *open* follow-up with documented fix path, not resolved-rot. Correctly declined.

All uncommitted; folds into the pending `/ship` → v0.10.1.

---

## 2026-07-19 (later 3) — Findings #4/#3/#5 fixed & released as v0.10.0; README now documents coderv-loop

Closed out the three open findings from "later 2", released the toolkit, and ran an architecture review.

**1. Fixed the 3 real Codex findings in one batched diff** (`hooks/codex-review-gate.sh`, commit `260ec4c`):
- **#4** `review_failed` (fail-open) now emits a terminal `outcome` `{result:"passed", unreviewed:true}` — the dashboard no longer hangs on "reviewing…" forever. `unreviewed:true` keeps it from ever reading as a genuine pass.
- **#3** cache-hit retry emits a `commit_attempt` beat BEFORE its cached `outcome` (writer wire-pulse visible on a same-diff retry).
- **#5** `flock -w 1` (bounded) + fall-through to plain append on timeout — a hung lock holder can never stall the hook.
- All three EXERCISED end-to-end (not just read): both paths emit a terminal outcome; every line valid JSON; flock proven to return in ~1019ms under a held lock instead of stalling 10s. Fresh-context reviewer clean, its quotes machine-verified 6/6.

**2. Re-installed the fixed gate** (`/root/.claude/hooks/codex-review-gate.sh`, backup `.bak-findings-fix`, `log_event` count 12→14) and **restarted `coderv-loop`** (env `CODERV_LOOP_LOG` confirmed in `/proc/PID/environ`). The commit that shipped the fix produced a COMPLETE closed loop on the dashboard (`commit_attempt → outcome:passed` on the cache-hit retry — fix #3 firing live).

**3. Released v0.10.0** (commit `f8a0314`, tag pushed): README gained a "Watch the two brains work (coderv-loop)" section (the dashboard was previously undocumented), CHANGELOG `[Unreleased]`→`[0.10.0]`, VERSION 0.9.0→0.10.0. Shipped via `./release.sh` (tag + push to `origin`/GitHub + website site.ts synced to 0.10.0).

**4. Ran `/improve-codebase-architecture`** — report at `/tmp/architecture-review-20260719.html` (not in repo). 5 candidates; top = #2 (install/uninstall gate rosters typed twice → orphaned-config bug). PARKED, see RESUME block.

**Gate live-fire note:** the freshly-installed gate denied 5× this session — all stale-spec / phased-work false positives (SESSIONS.md drift, "framework not implemented" when it was in the prior commit, jq-guard already upstream). Each rejected with machine proof and surfaced (transparency rule). The fix for the recurring stale-spec deny: **overwrite the `/before` spec to describe the CURRENT task** before committing a follow-up whose base moved — the drift-hunter hunts against whatever spec is on disk.

**State evidence (verbatim):**
```
$ git log --oneline -4
f8a0314 Release 0.10.0: live-loop event log + coderv-loop dashboard
260ec4c Complete the live-loop event log: terminal outcomes + bounded flock
9bd849c Gate on an absolute token budget, not a percentage of the window
9ad03ae Smart install: detect Codex and complete the two-brain setup
$ git status --short
 M docs/SESSIONS.md
$ git ls-remote --tags origin v0.10.0
d8e09d43707e21ad6f67801fec10c14c4a8c7e4b	refs/tags/v0.10.0
$ cat VERSION
0.10.0
$ grep -c log_event /root/.claude/hooks/codex-review-gate.sh
14
```

**Gotchas the next session should know:**
- `docs/SESSIONS.md` is intentionally uncommitted (dual-state handoff — never rides a code commit; the gate skips docs-only anyway).
- One human step the release printed and did NOT auto-run: `gh release create v0.10.0 …` — do it if you want a GitHub Release page (tag+push already done).
- shellcheck 0.9.0 is now installed (was absent at session start) and the hooks came back clean — see the shellcheck section below.

**shellcheck pass — DONE this session, result CLEAN.** Installed shellcheck 0.9.0 and ran it on all 6 hooks + install.sh + release.sh: **0 errors, 0 warnings**, 4 notes — all adjudicated as false-positives-in-context (codex-review-gate.sh:84 intentional `bash -c` single-quote; two SC2012 `ls`-counts of controlled dir names; release.sh:94 SC2015 with a non-failing middle command). **No fix needed → no v0.10.1.** The live-fire discipline held up under static analysis.

**Next session should probably:**
- **Path — `cd /root/claude-docs-toolkit` first** (this is the toolkit repo; branch `main`, remote `origin` = `git@github.com:AbudiHadi/coderv.git`). Everything below runs from there.
- **UNCOMMITTED: `skills/session/SKILL.md`** — sign-off template changed (owner request) so every handoff closes with the project path: `👉 Next session: start fresh (your project path: <abs path>), run /session last…`. Edited in both source and installed copy. `/ship` it → gate review → cut **v0.10.1** (skill-description change).
- Optional: `gh release create v0.10.0 …` for a GitHub Release page (tag+push already done). Then the parked arch candidates #2→#1 (see RESUME block), or `/lint` the docs (last ran 2026-07-15).
- Housekeeping: `docs/SESSIONS.md` is now 582 lines (>~500 rotation threshold, 17 entries <20 count) — consider rotating older entries to `docs/SESSIONS-ARCHIVE.md` per /session Step 3.

---

> **Older entries** (2026-07-19 later-2 back through 2026-04-24 docify) rotated to [`SESSIONS-ARCHIVE.md`](./SESSIONS-ARCHIVE.md) on 2026-07-19. Nothing is ever deleted.

<!-- New sessions above this line, newest first -->
## 2026-07-19 (later 2) — Viewer made TRULY live: gate installed + log-path bug fixed + 3 real open findings

Continues the "later" entry below. Owner tunnelled in (Termius local port-forward 9130→server:3130) and confirmed the dashboard renders. Then:

**1. Installed the updated gate (now LIVE).** Copied repo `hooks/codex-review-gate.sh` → `/root/.claude/hooks/codex-review-gate.sh` (backup at `.bak-preloop`). Verified: IN SYNC, `bash -n` OK, marker preserved, 12 `log_event` calls. Real reviews now emit events.

**2. Fixed a real "shows seed not real data" bug (log-path mismatch).** Root cause: Claude Code (and the hook) run as **root** → real events write to `/root/.claude/coderlap/loop-events.jsonl`. But the dashboard runs as **appuser** and was reading appuser's home → only ever saw the 10 seeded lines. Two files that never met. FIX: added `CODERV_LOOP_LOG=/root/.claude/coderlap/loop-events.jsonl` to `coderv-loop/ecosystem.config.js` (`/root` is world-readable `drwxr-xr-x`, so appuser can tail it). pm2 delete+start to load env; VERIFIED the running proc now reads root's log and serves the REAL denied review (5 findings) instead of seed.

**3. Codex reviewed my Piece A code again (installed gate, real run) and raised 3 GENUINELY REAL findings — STILL OPEN, fix next session:**
- **#4 [BUG] — WORST, user-visible:** `review_failed` emits NO terminal `outcome`. Because the gate fails-open on a Codex timeout/error, the dashboard stays stuck on "reviewing…" forever. Fix: emit `outcome` (e.g. `result:"passed", unreviewed:true`) on the `review_failed` path too.
- **#3 [BUG]:** the cache-hit retry path emits `outcome` but no `commit_attempt`, so a same-diff retry shows no writer beat / no wire-pulse. Fix: emit a `commit_attempt` before the cached `outcome`.
- **#5 [BUG]:** `flock` in `log_event` has no `-w`/`-n` timeout → a hung lock holder could stall the hook indefinitely, violating the pure-side-effect contract. Fix: `flock -w 1` (or `-n`) and fall through to plain append on failure.
- #1 (Piece B absent), #2 (SESSIONS.md) = same phased-plan / unrelated-file false positives, rejected & surfaced (transparency rule).

**State evidence (verbatim):**
```
$ git status --short          (toolkit)
MM docs/SESSIONS.md
 M hooks/codex-review-gate.sh
$ diff installed-vs-source gate → IN SYNC ✓   (gate is now LIVE)
$ coderv-loop running proc env → CODERV_LOOP_LOG=/root/.claude/coderlap/loop-events.jsonl
$ wc -l /root/.claude/coderlap/loop-events.jsonl → 9   (REAL review: commit_attempt, review_started, verdict(5), 2×drift + 3×bug findings, outcome denied)
$ grep CODERV_LOOP_LOG ecosystem.config.js → CODERV_LOOP_LOG: '/root/.claude/coderlap/loop-events.jsonl',
```

**Access recap (works today):** Termius → Port Forwarding → Local, listen `9130`, destination host `localhost`, destination port `3130`, over the server → open `http://localhost:9130`. (Any local port works; `9130` chosen to avoid a clash on the PC.) The `ubuntu` account is **password-locked (`!` in shadow)** — key-only; a new ed25519 key was generated on the owner's PC (`g2w@g2w`) but NOT yet added to the server (Termius connection made the manual key moot).

**Next session — DO FIRST (fresh context):**
1. Fix findings #4, #3, #5 in `hooks/codex-review-gate.sh` (batch into ONE diff), re-run the installed gate on a real diff to confirm, **re-install** the fixed gate (copy to `~/.claude/hooks/`), restart `coderv-loop`.
2. Then `/ship` the toolkit change (`hooks/codex-review-gate.sh` ONLY — NOT the dual-state `docs/SESSIONS.md`). Expect codex-review-gate to re-review; #4/#3/#5 fixed should clear it.
3. coderv-loop app has no git remote (local-only) — nothing to commit there.

---

## 2026-07-19 (later) — Live two-brain viewer: gate emits JSONL events + new `coderv-loop` dashboard app (BOTH UNCOMMITTED)

**Goal (user's words):** "turn all this to MCP" so users *see the real integration between Codex and Claude working together* — a **live** view of the two-brain review talking, working on localhost AND for headless-Linux users. Clarified: MCP is plumbing with no UI; what they want is a **live web dashboard**. Approved design = **split** (keeps toolkit KISS intact): Piece A logs (bash-only, in toolkit) + Piece B viewer (separate app). Data source = **real live runs**. Look = **designed showpiece** (frontend-design + polish).

**What shipped (TWO repos, NOTHING committed yet):**

**Piece A — `hooks/codex-review-gate.sh` (toolkit repo, UNCOMMITTED):** added a `log_event()` helper + call sites that append one JSON line per event to `~/.claude/coderlap/loop-events.jsonl`. Event types: `commit_attempt` (claude), `review_started` (codex; diff_bytes, drift_checked, truncated), `verdict` (codex; lgtm|findings + count), `finding` (codex; tag bug|drift|note + full multi-line text), `review_failed` (system; rc), `outcome` (system; result passed|denied [+cached on retry path]). **CONTRACT: pure side-effect** — never changes allow/deny, never errors the hook, honours `CODERV_LOG_OFF=1` + jq-missing → no-op. flock-serialised writes. This was VERIFIED (unit + e2e + concurrency).

**Piece B — `/home/appuser/apps/coderv-loop/` (NEW app, NOT a git repo — local-only like coderv-docs):**
- `server.mjs` — zero-dep Node; tails the JSONL, streams SSE at `/events` (replays last 200 on connect, flagged `_replay`, then live-tails via fs.watch + 1s poll + byte-offset, handles truncation/rotation). Binds `127.0.0.1` only.
- `public/index.html` — self-contained showpiece "the wire": vertical spine at 38% (intentional asymmetry — reviewer gets the wide right column), writer=violet `#a78bfa` docks left / reviewer=fuchsia `#d946ef` docks right (same tokens as coderv.dev index.astro), findings clamp to spine as rose `[BUG]`/amber `[DRIFT]` slabs, travelling wire-pulse on hand-off, breathing idle state, live status pill, reconnect state. Reuses coderv.dev colour language. prefers-reduced-motion + mobile (spine→22px) handled.
- `ecosystem.config.js` — PM2 `coderv-loop`, appuser, port 3130, loopback.
- `README.md` — access instructions incl. SSH-tunnel for headless.

**Codex gate fired TWICE on Piece A during the build (the system working).** 10 findings raised across 2 rounds; adjudicated:
- FIXED (6 real): `outcome` event type mismatch (spec said `outcome`, code emitted `passed`/`denied` — now `type:outcome, payload.result`); multi-line findings truncated to first line (now awk folds continuation lines, NUL-delimited straight into read loop — do NOT capture NULs in `$(...)`, it strips them); nested indented `-`/`*` bullets split from parent (now only top-level markers start a finding); concurrent-append interleave (added flock); cache-hit retry path exited before logging (now emits `outcome:passed,cached:true`).
- REJECTED (2, surfaced per transparency rule): "Piece B absent" ×2 = **false positive**, Piece B is phased-later in the same approved plan, not drift.
- The stray `docs/SESSIONS.md` change in `git status` (the ADR-012 handoff below) is UNRELATED prior work — Codex correctly flagged it; it must NOT ride in Piece A's commit.

**Verified this session:** gate `bash -n` OK; log_event unit test (shape/default-payload/kill-switch/JSON-valid); e2e gate paths (empty-diff silent allow, docs-only allow, non-commit allow, kill-switch); flock 20× concurrent big-payload writes → 20 valid lines, 0 interleave; multi-line + nested-bullet parser → correct fold; server e2e (index 200, SSE replay+`_synced`+3 live frames in order); **live browser test** — appended event rendered on open page (10→11 beats), 0 console errors; 2 screenshots reviewed (composition rebalanced after polish). coderv-loop survives pm2 restart; all files appuser-owned (fixed a root-owned slip).

**State evidence (verbatim):**
```
$ git status --short          (toolkit)
MM docs/SESSIONS.md
 M hooks/codex-review-gate.sh
$ git log --oneline -3
9bd849c Gate on an absolute token budget, not a percentage of the window
9ad03ae Smart install: detect Codex and complete the two-brain setup
5fc6455 Encode the gate-deny anti-loop rule into the workflow, not memory
$ cat VERSION                 → 0.9.0   (NOT bumped)
$ bash -n hooks/codex-review-gate.sh → OK
$ diff installed-vs-source gate → Files DIFFER  (installed ~/.claude/hooks copy is OLD — logging NOT live yet)
$ pm2 (coderv-loop)           → online restarts=1 pid=1672460
$ ss :3130                    → LISTEN 127.0.0.1:3130 (node, appuser)
$ curl localhost:3130/        → 200
$ ls coderv-loop/             → README.md ecosystem.config.js public/ server.mjs  (all appuser:appuser)
$ SERVER-MAP row              → | 3130 | coderv-loop (live two-brain viewer) | appuser | apps/coderv-loop | localhost only — no nginx |
$ wc -l loop-events.jsonl     → 10   (seeded DEMO exchange; safe to delete/overwrite — regenerated by real reviews)
```

**Gotchas the next session MUST know:**
- **Logging is NOT live yet.** The gate SOURCE has it but the INSTALLED hook `/root/.claude/hooks/codex-review-gate.sh` is the OLD copy. Real reviews won't populate the log until you re-run `install.sh` or copy the hook. Left uninstalled deliberately (changes live behavior — owner's call).
- **`docs/SESSIONS.md` is DUAL-state (`MM`)** — do NOT `git add` it into Piece A's commit; it carries the unrelated ADR-012 handoff (staged) + this handoff (unstaged). Piece A commit = **`hooks/codex-review-gate.sh` ONLY**.
- **coderv-loop has NO git remote and is not even `git init`'d** — it's local-only like coderv-docs. "Shipping" it = nothing to commit there; PM2 already serves it.
- The demo log's 10 lines are fake seed data for the screenshot — real reviews append/replace freely.

**Next session should probably (pick with owner):**
- (a) **install the updated hook** so events go live (`install.sh` or copy the hook), then attempt a real code commit somewhere to watch the wire populate for real; and/or
- (b) `/ship` **only** `hooks/codex-review-gate.sh` in the toolkit (docs-aware: this touches a load-bearing gate; the codex-review-gate will re-review it — expect it to pass now that findings are fixed);
- (c) optional follow-ups the user deferred (out of scope this session): action buttons (trigger review / accept-reject findings), coderv.dev public scripted-replay demo, wiring `/before` + `/ship` events (gate-only for now).

---

## 2026-07-19 — context-gate rewritten to an absolute token budget (ADR-012, committed `9bd849c`)

**What shipped (committed `9bd849c`, 6 files, +150/−48):**
- **`hooks/context-gate.sh` rewritten** to gate on ABSOLUTE occupied-context tokens, not a % of the model's window (ADR-012). Block at `min(CODERV_CTX_BUDGET default 180000, CODERV_CTX_WINDOW default 1000000 × CODERV_CTX_SAFETY_PCT default 90 / 100)`; warn at 0.75× that; all comparisons in absolute tokens (killed the round()/50k-bucket/100k-hysteresis bugs). Occupied context = transcript's last main-chain call, `input + cache_read + cache_creation + output_tokens`, sidechains skipped, never summed. Fail-safe env parsing; `CODERV_CTX_SAFETY_PCT` clamped to 100; old `CODERV_CONTEXT_WINDOW` honoured as window fallback; `CTX_WARN_PCT/CTX_BLOCK_PCT` superseded/ignored.
- **ADR-012** added (refines ADR-006 trigger math, not its design); ADR-006 status carries a pointer. README, skills.md, install.sh comments, CHANGELOG (`[Unreleased]`) synced.
- **Why:** on Opus 4.8 (1M window, standard) the old `% of hardcoded 200k` default fired ~5× too early; the naive fix (window=1M) would gate at 750k, deep in rot. The dumb zone is an absolute floor (~150–200k), not a fraction of the admission limit.

**Verified:** `bash -n` clean; 12+ payload scenarios (block/warn/silent, re-arm, stop_hook_active, kill switch, clamp, fail-safe env, malformed input) + output_tokens threshold checks — all pass. Fresh-context reviewer + Codex gate.

**The gate rounds (honest):** the commit took **5 codex-review-gate rounds** before LGTM. Rounds 2–5 caught GENUINELY DISTINCT real issues my own verification missed: (2) `SAFETY_PCT` uncapped → clamp to 100; (3) `usage`-on-payload claimed primary but was dead code → reframed; (4) that payload `usage` might be cumulative → **removed the fast-path entirely** (transcript-only); (5) `output_tokens` omitted from occupancy → now counted. Round 1 (SESSIONS.md scope) rejected as out-of-scope. Round 5 ALSO re-raised the payload point in the OPPOSITE direction of round 4 (contradiction) — per the anti-loop rule I stopped fixing, corrected ADR-012 to declare transcript-only as the design (removing the contradiction's premise), owner chose "retry once then commit regardless," and the retry returned LGTM.

**State evidence (verbatim):**
```
$ git log --oneline -1        → 9bd849c Gate on an absolute token budget, not a percentage of the window
$ git status --short          →  M docs/SESSIONS.md   (this handoff; nothing else dirty)
$ git status -sb              → ## main...origin/main [ahead 1]
$ cat VERSION                 → 0.9.0   (NOT bumped — release via ./release.sh, never by hand)
$ diff repo vs installed hook → DIFFER (installed ~/.claude/hooks/context-gate.sh is still the OLD % version)
```

**Gotchas the next session should know:**
- **The fix is committed but NOT installed.** `~/.claude/hooks/context-gate.sh` is still the old percentage-of-200k version — which is why a gate fired "81% of 200,000" during this session (a false alarm; real occupancy was ~16% of 1M). To make the fix live: re-run `install.sh` (or copy the hook) so the new absolute-budget gate replaces the old one.
- **`git stash pop` created conflicts this session** — the stash held stale pre-commit copies of files already committed in `9bd849c`. Resolved with `git checkout HEAD -- <files>`; stash dropped. Lesson: don't stash-pop pre-commit snapshots back over post-commit files.
- **VERSION still 0.9.0** — the ADR-012 CHANGELOG entry sits under `[Unreleased]`; `release.sh` promotes it + bumps VERSION + tags + syncs the website's `site.ts` at release time.
- **Unsettled fact (benign):** whether the Stop payload carries a per-call vs cumulative `usage` was never empirically confirmed. We sidestepped it by staying transcript-only, so correctness is unaffected — but that's the fact to verify before ever adding a payload fast-path.

**Next session should probably:**
- Install the new hook (re-run `install.sh`) so the gate fix is actually live on this box.
- When ready to release: `release.sh` (bumps VERSION 0.9.0→next, promotes CHANGELOG, tags, pushes — repo is 1 ahead of origin), then re-sync the website `site.ts`.
- Commit or hand off `docs/SESSIONS.md` (this entry) — it's the only dirty file.

---

## 2026-07-17 (later 2, context gate) — Smart installer completes the two-brain setup (ADR-011)

**What shipped (committed `9ad03ae`, 3 files, +334/−3):**
- **`install.sh` is now one smart install** that completes the whole two-brain workflow: detects Codex state (`codex_state()` → absent / installed / authed), installs portable reviewer rules to `~/.codex/AGENTS.md`, and prints an honest status line per state (two-brain ON / run `codex login` / `npm i -g @openai/codex && codex login`). Reviewer-rules status reported for EVERY state; never claims installed when the template is missing.
- **New `templates/codex-AGENTS.md`** — portable reviewer rules (universal role + discipline + hard rules; VPS specifics genericised so it ships). The live `~/.codex/AGENTS.md` on this box was left as-is.
- **Non-destructive install/uninstall** of `~/.codex/AGENTS.md`: create (with an `OWNS-FILE` sentinel) if absent, else append a `<!-- claude-docs-toolkit:agents START/END -->` marked block, idempotent. Uninstall is **line-based** — strips only the block (+sentinel), keeps all other lines incl. user edits above/below; removes the whole file only when the sentinel proves we created it AND nothing else remains. Malformed/duplicated/markerless/pre-existing-empty/user-edited all preserved.
- **ADR-011** logs it, including a **rejected finding** (line-based removal normalises CRLF→LF / adds a final newline on exotic files — accepted so post-install edits are never lost; the byte-exact truncate design was tried and destroyed post-install edits).

**Verified:** 10-case sandbox suite green (edits-above-and-below preserved, empty-file survives, created-then-edited keeps notes, idempotency=1 START, malformed left untouched, prose-mention untouched, normal round-trip byte-exact); `bash -n` clean.

**The gate rounds (honest):** the installer commit took **7 codex-review-gate rounds**. Rounds 1–6 each caught a GENUINELY DISTINCT real bug in the file surgery (empty-file deletion, post-install-edit destruction, CRLF, marker edge cases) — the gate was right every time; file surgery that must never lose user bytes has a long tail. Round 7 was a FALSE POSITIVE (Codex applied its own "don't touch source-of-truth docs" rule to Claude the conductor) — rejected with verbatim-rule evidence, ONE rebuttal used, Codex withdrew. The anti-loop escalation (same finding twice / same rationale) correctly never tripped — every round was a new finding = convergence, not a loop. I introduced the round-5 regression myself (chased byte-exactness, broke edit-preservation); the gate caught it, a sharper test suite would have too.

**State evidence (verbatim):**
```
$ git log --oneline -4
9ad03ae Smart install: detect Codex and complete the two-brain setup
5fc6455 Encode the gate-deny anti-loop rule into the workflow, not memory
b57b0e0 docs: record two-brain workflow build handoff (items 1-5 shipped, f9c0836)
f9c0836 Add two-brain design+review workflow — plan-review loop, immutable spec, drift-hunter gate
$ git status -sb        → ## main...origin/main [ahead 2]   (+ this docs/SESSIONS.md edit, uncommitted)
$ bash -n install.sh    → OK
$ ADR count             → 12 ;  SESSIONS entries → 11 (was 10)
```

**Gotchas the next session should know:**
- **`main` is ahead of origin by 2** — commits `9ad03ae` (this) + `5fc6455` (ADR-010, prior task). BOTH unpushed. Owner pushes (`git -C /root/claude-docs-toolkit push`). This repo DOES have a remote (`origin` → `AbudiHadi/coderv.git`) — the "no remote" memory note is about coderv-docs, a different repo.
- **This SESSIONS.md handoff is itself uncommitted** — commit it (docs-only, gate passes freely). It carries BOTH this entry and the ADR-010 entry below.
- **Two ADRs this session:** ADR-010 (anti-loop rule → workflow) and ADR-011 (smart installer). The anti-loop rule from ADR-010 got its first live-fire test on the ADR-011 commit — and worked.
- The `~/.codex/AGENTS.md` on THIS server is VPS-specific and NOT what ships; the shippable portable copy is `templates/codex-AGENTS.md`. Don't sync one onto the other.

**Next session should probably:**
- `git push` (2 commits) + commit this SESSIONS.md handoff — the only pending actions; nothing gates them.
- Optional: bump VERSION + CHANGELOG for a release that includes ADR-010 + ADR-011 (currently `[Unreleased]`; owner bumps at release per the stable-surface rule) — then `./release.sh`.
- Optional: add a real automated test file for the AGENTS.md install/uninstall surgery (the 10 cases were sandbox one-offs) so the round-5-style regression can't recur silently.

---

## 2026-07-17 (later) — Gate-deny anti-loop rule moved from memory into the workflow (ADR-010)

**What shipped (committed `5fc6455`, 3 files, +106/−8):**
- **`skills/ship/SKILL.md` Step 7** gate-deny block rewritten: on a deny, fix **all** real findings then commit **once** (never per-finding recommit — each recommit is a fresh diff = fresh review = the loop); reject a finding **only** with parsed, machine-verified proof; rebut to Codex **once**; then **escalate to the owner when the same unresolved finding is rejected twice on substantially the same rationale.**
- **`hooks/codex-review-gate.sh`** deny message (`REASON=`) carries the same rule so it holds even with no skill loaded. **Text-only — no control-flow change** (proven: the `REASON="..."` string spans lines 298–313; anchored grep for shell keywords at statement position returns nothing).
- **`docs/DECISIONS.md` ADR-010** records the move + the narrow escalation definition.
- **Outside this repo (already saved, not committable here):** `AI-WORKFLOW-PLAN.md` principle #8 (bounded convergence); `~/.codex/AGENTS.md` ("expect one converged retry"); memory `feedback-gate-deny-no-loop` demoted to a **pointer** + `MEMORY.md` line updated.

**Why:** owner's point — a workflow rule that only lives in memory isn't a guarantee (lost if memory is pruned or the session runs where it isn't loaded). Memory is the reinforcement layer, not the mechanism. This extends the design-phase round cap (ADR-009) to the commit path.

**"Substantially the same rationale" — defined narrowly (owner's refinement):** same underlying claim + same cited evidence + no materially new code or facts bearing on the finding. If any of the three shifts → fresh finding, escalation does NOT trip. Baked in identically at both enforcement points + ADR-010.

**Verified:** fresh-context reviewer → LGTM (7/7 spec items, 3 in-repo + 3 out-of-repo); reviewer quotes machine-verified 3/3 at cited lines; `bash -n` on the hook → OK; codex-review-gate on the commit itself → **LGTM** (the live test of the new rule passed on a single commit).

**State evidence (verbatim):**
```
$ git status -sb | head -1     → ## main...origin/main [ahead 1]
$ git log --oneline -3
5fc6455 Encode the gate-deny anti-loop rule into the workflow, not memory
b57b0e0 docs: record two-brain workflow build handoff (items 1-5 shipped, f9c0836)
f9c0836 Add two-brain design+review workflow — plan-review loop, immutable spec, drift-hunter gate
$ git remote -v                → origin git@github.com:AbudiHadi/coderv.git
```

**Gotchas the next session should know:**
- **This toolkit repo HAS a remote** (`origin` → `AbudiHadi/coderv.git`) and is **ahead 1 — the commit is UNPUSHED.** (The memory note "NO git remote" refers to *coderv-docs* the website, a DIFFERENT repo — don't conflate them.) Owner pushes when ready.
- The commit's gate review flagged **"drift NOT checked"** — the `/before` spec had no `Base:` commit stamp so only correctness was reviewed (drift was covered manually by the fresh-context reviewer). Let `/before` write the stamped spec next time to arm the drift-hunter.
- **Downloaders get the anti-loop rule automatically** (it's in `skills/ship` + `hooks/`, both installed by `install.sh`), but NOT the doctrine files: `AI-WORKFLOW-PLAN.md` #8 and `~/.codex/AGENTS.md` live in `/root`, not the repo. Full two-brain loop also needs them to install Codex CLI + `codex login` (gate fails open with a warning otherwise).

**Next session should probably:**
- Push (`git push`) when the owner is ready — it's the only pending action.
- Consider moving the two doctrine files (`AI-WORKFLOW-PLAN.md`, a Codex-rules template) INTO the repo if downloaders should get the full two-brain workflow, not just the Claude-side loop.

---

## 2026-07-17 (BUILT) — two-brain workflow shipped: plan-review loop + immutable spec + drift-hunter gate

**Items 1-5 of `docs/planning/two-brain-workflow-plan.md` are built, verified, and committed (`f9c0836`).** The two-model workflow now reviews the PLAN, not just the diff (ADR-009). Not yet pushed (see below) and NO version bump (owner: bump at release, this is `[Unreleased]`).

**What shipped:**
1. **`/before` step 5.6 — design-phase Codex loop.** Claude drafts the plan → pipes it to Codex via the gate's one-payload stdin channel → adjudicates → converges to one of **three terminal end states** (CONVERGED / CAP-STOPPED / REVIEW-UNAVAILABLE; `running` = non-terminal). FIXED-requires-VERIFIED (else UNVERIFIED-CARRIED). Timeout ≠ LGTM. Every finding surfaced to the user.
2. **Immutable stamped spec.** `/before` Step 5.5 now OVERWRITES (never appends) the spec, stamped `Base: <HEAD>` + ISO date via an **injection-safe** pattern (quoted-heredoc body + `printf` for the two trusted stamp lines).
3. **Drift-hunter gate.** `codex-review-gate.sh` reads a FRESH spec (Base is ancestor of HEAD via `git -C "$SPEC_ROOT" merge-base --is-ancestor`, AND `0 ≤ mtime < 24h`) and prepends it — findings tagged `[DRIFT]`/`[BUG]`. Stale/missing/wrong-base/future-mtime/no-stamp → generic prompt + loud "drift NOT checked" in EVERY outcome (LGTM + deny). **Both hook copies re-synced byte-identical** (sha `462a817…`).
4. **`/ship` deny → discussion.** On a gate deny, Claude may rebut to Codex ONCE (OUT assigned, VERDICT read, plan included for `[DRIFT]` rebuttals); Claude's call final; outcome surfaced.
5. **ADR-009 + CHANGELOG `[Unreleased]` + KI-001.**

**The drift-hunter's first field test was its OWN commit** — exactly as the prior handoff predicted. During the build AND at commit time, the live gate reviewed this very implementation and caught **6 real bugs**, all fixed: (1) command injection in the spec heredoc, (2) future-mtime staleness bypass (`SPEC_AGE < 0` read as fresh), (3) inert `/ship` rebuttal (`$OUT` unassigned), (4) unlabeled 4th convergence state, (5) `SPEC_ROOT`/`$DIR` divergence in the ancestor check, (6) "four vs three end-states" doc contradiction. Rejected findings (surfaced, transparency rule): the recurring "second hook copy not in diff" (proven false positive — installed copy is *outside* the git tree, sha-identical) and Codex re-raising KI-001 as must-fix (owner ruled it a follow-up).

**KI-001 (open, owner-accepted follow-up):** the fresh-spec/drift block sits AFTER the 24h review cache short-circuit, so a spec-state change on an unchanged diff reuses the cached verdict. Can't occur in normal use (`/before` writes the spec before any diff exists). Fix when addressed: fold a spec-freshness marker (Base + mtime) into the cache hash key. Full entry + prevention rule in `docs/KNOWN-ISSUES.md`.

**Verified:** drift suite 14/14 (isolated HOME + stubbed codex + scratch repos, `scratchpad/drift_test.sh`); `/verify` drove the *installed* hook end-to-end through fresh-spec (drift mode, plan reached reviewer) / no-spec (generic + "drift NOT checked") / future-mtime (correctly not armed) states.

**State evidence (verbatim):**
```
$ git log --oneline -2
f9c0836 Add two-brain design+review workflow — plan-review loop, immutable spec, drift-hunter gate
d618f39 docs: two-brain workflow design handoff (converged plan, not yet built)
$ git status -sb        → ## main...origin/main [ahead 3]
$ cat VERSION           → 0.9.0        $ git tag | grep v0.9.0 → v0.9.0
$ sha256 both hook copies → 462a817940343ecbf8dd47df6eb19c5c2a900f0e24abba5b75021c2b5287ce84 (identical)
$ drift suite           → RESULT: 14 passed, 0 failed
```

**Next session:**
- **Push:** `main` is **ahead of origin by 3** (this commit + 2 prior doc handoffs) — `git push` when ready (nothing gates it; docs+skills, gate already dogfooded).
- **Still needs a human (gh not authed here):** publish GitHub releases for v0.9.0 + backlog v0.6.0/v0.7.0/v0.8.0 (tags exist, releases never created) — carried over from the v0.9.0 handoff, independent of this work.
- KI-001 fix (cache key) whenever the cache-vs-drift edge is worth closing.

---

## 2026-07-17 (design, NOT built) — two-brain workflow plan CONVERGED, ready to implement next session

**Nothing coded. This is a design handoff — the plan is approved-in-principle by the owner and peer-reviewed by Codex to CONVERGED. Build it in a FRESH session (context gate fired at 77% before implementation started).**

**What the next session builds** (full plan: `docs/planning/two-brain-workflow-plan.md`; convergence mechanism: `docs/planning/two-brain-convergence.md` — both durable in-repo). Make the CoderLap workflow "two-brain" — Claude (writer) + Codex (reviewer) collaborate at design AND review, Claude holds final authority:
1. **`/before` design-phase Codex loop** (new step ~5.4, before presenting plan to user): Claude drafts → pipes plan to Codex via ONE serialized stdin payload (`{ printf instructions + delimiter; cat planfile; } | timeout 480 codex exec --skip-git-repo-check -s read-only -o "$OUT" -`) → adjudicates → re-sends after any substantive change → converges. NOT the current `/before` — an addition.
2. **Immutable per-task spec**: `/before` OVERWRITES (never appends) `~/.claude/coderlap/specs/<slug>.md` with a stamped plan (task+ISO date+base commit); session-unique. Fixes a latent staleness bug in the existing spec design.
3. **Drift-hunter gate**: `codex-review-gate.sh` PROMPT (hook lines 191-192) reads a FRESH spec and prepends it — "approved plan: X; find where the diff DEVIATED + any correctness/security/data bug." Stale/missing spec → fall back to current generic prompt AND say "drift not checked" (never claim a review that didn't happen).
4. **`/ship` deny-handling → discussion** (`skills/ship/SKILL.md` step 7, lines ~303-308): on gate deny, Claude may push back to Codex ONCE with a rebuttal; strong hand, Claude's call final; outcome surfaced to user.
5. **ADR-009** (two-brain design phase + immutable spec + drift gate + convergence mechanism); CHANGELOG [Unreleased]; NO version bump until release; NO new user commands (stable surface rule).

**The convergence mechanism (owner's key architectural concern — fully resolved, see `docs/planning/two-brain-convergence.md`):** termination guaranteed by the ROUND CAP alone (NOT by "disagreements shrink" — Codex disproved that; the material set can grow). "100%" := empty *verified* unresolved-material set, NEVER consensus. Four labeled end states: CONVERGED / CAP-STOPPED / REVIEW-UNAVAILABLE / running. "Material" = impact threshold (correctness/security/scope), size-independent, ties→material. EVERY finding surfaced to user with classification+reasoning (Claude cannot hide a finding by mislabeling — Codex's sharpest catch). FIXED requires VERIFIED. Disagreement is a legal end state; user is final authority.

**Live proof the loop works:** the plan (3 rounds, 7 findings, 6 fixed + 1 overruled — commit-range rejected: gate is PreToolUse, no commit exists yet) AND the convergence mechanism (4 rounds, 7 findings, all 7 accepted+fixed, ended in a genuine Codex LGTM = CONVERGED) were both run through the very loop being designed. This session IS the first field test, and it converged.

**State evidence (verbatim):**
```
$ git status --short          # clean except the docs added THIS handoff step
 (docs/planning/*.md + docs/SESSIONS.md — commit them, docs-only, gate passes)
$ git log --oneline -2
ad2064d docs: record v0.9.0 release run handoff
e7ff058 Release v0.9.0 — codex-review-gate (4th anti-dumb-zone gate)
$ cat VERSION      → 0.9.0        $ git tag | grep v0.9.0 → v0.9.0
$ codex login status → authed     (plan-review calls confirmed working, rc=0)
```
Note: v0.9.0/0.8.0/0.7.0/0.6.0 GitHub releases still unpublished (gh not authed here) — owner runs `gh auth login` + `gh release create` per prior handoff. Independent of the two-brain work.

**Next session:** fresh context → read `docs/planning/two-brain-workflow-plan.md` + `two-brain-convergence.md` → run `/before` to confirm the approach is still current → BUILD items 1-5 → it commits through the gate (drift-hunter is the first live test of the review half). Owner already approved the design in principle and green-lit the convergence mechanism.

---

## 2026-07-17 (release run) — v0.9.0 shipped: codex-review-gate

Owner said "approve" then "do it" (release). Chain ran clean:
- VERSION 0.8.0 → 0.9.0; CHANGELOG `[Unreleased]` → `## [0.9.0] — 2026-07-17` + a "Why bump" note. Release-bump commit `e7ff058` went through the codex gate: 1 finding (**rejected, surfaced**) — "keep an empty `[Unreleased]` heading above 0.9.0"; rejected because the repo's actual convention (verified against shipped 8e3ac12) keeps NO standing Unreleased heading, and `release.sh` line 34-35 requires the CHANGELOG top entry to equal VERSION exactly, which an Unreleased heading would break.
- `./release.sh --check` → all 7 gates green. `./release.sh` → tagged v0.9.0, pushed branch+tag (SSH, `8e3ac12..e7ff058`), website site.ts synced to 0.9.0, rebuilt, committed (`coderv-docs` `e5a7463`).
- **State evidence (verbatim):**
```
$ git log --oneline -1 && cat VERSION
e7ff058 Release v0.9.0 — codex-review-gate (4th anti-dumb-zone gate)
0.9.0
$ git tag | grep v0.9.0        → v0.9.0
$ grep version .../site.ts     → version: '0.9.0'
$ git -C coderv-docs log -1    → e5a7463 v0.9.0: site sync
```

**Still needs a human (gh not authed in this session):** publish GitHub releases for v0.9.0 AND the backlog tags v0.6.0/v0.7.0 (tags exist, releases never created). Commands are in the release-run chat reply; run `gh auth login` first.

**Next session:** nothing outstanding on the gate itself — it's shipped and dogfooding. Owner still to confirm ADR-008 (logged adjustable). v0.8.0 GitHub release also never published — fold it into the same catch-up if desired.

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
