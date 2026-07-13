# Session Handoffs — toolkit

> End-of-session notes for the toolkit repo. Newest at top.

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
