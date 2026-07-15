# Session Handoffs — toolkit

> End-of-session notes for the toolkit repo. Newest at top.

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
