# Session Handoffs — toolkit

> End-of-session notes for the toolkit repo. Newest at top.

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
