---
name: ship
description: |
  Pre-commit checklist. Reads the diff, offers to update docs itself (not just ask you), validates citations in docs haven't gone stale, drafts a why-focused commit message. Runs before every commit that touches multiple files.

  TRIGGER — suggest this skill (even without /ship prefix) when the user says: "commit", "git commit", "commit this", "push it", "push this", "push up", "create a commit", "make a commit", "ready to ship", "I'm done", "all done", "wrap up this change", "finalize", "let's commit", "commit and push", "ready to merge", "draft commit message", "write commit message".

  SKIP — when the user is only asking about git status without intent to commit (e.g. "what changed?", "show me the diff").
user-invocable: true
argument-hint: "(no args — reads git diff and staged files)"
---

# Ship — Smart Pre-commit

Goal: docs stay fresh + honest, with minimum friction.

## Step 1 — Look at the diff

```bash
git status
git diff --stat
git diff --stat --cached
```

Categorise changes:
- Routes (`app/api/**`, `routes/**`, `controllers/**`)
- Components (`components/**`, `src/components/**`)
- Schema (`*.prisma`, `migrations/**`, `db/**`, `schema.*`)
- Services (`lib/services/**`, `services/**`)
- Env / config (`.env.example`, `next.config.*`, `package.json` deps)
- Docs (`docs/**`, `CLAUDE.md`, `README.md`)
- Tests
- Locale / i18n

Report in 3–5 bullets.

## Step 2 — Smart doc update (NEW — the core upgrade)

Based on the categories, **offer to update docs yourself** (not just ask the user):

### If routes changed

```bash
# Find added/changed route files
git diff --name-only --diff-filter=ACM | grep -E 'app/api/.*route\.(ts|js)$|routes/.*\.(py|rb|go)$'
```

For each added/changed route:
1. Read the file.
2. Read `docs/api.md` if it exists.
3. Generate the section that should be in `docs/api.md` (method, path, auth, request, response, citation).
4. Show user a preview:

```
Route added: POST /api/partner/[id]/invite

docs/api.md doesn't mention this route. I can add this section:

  ### POST /api/partner/[id]/invite
  Auth: partner role, session.user.partnerId === id
  Request: { phoneNumber: string, role?: string }
  Response: { success: true, invitation: { ... } }
  <!-- src: app/api/partner/[id]/invite/route.ts:12-58 -->

Add it? (y/n/edit)
```

On `y` — append to the relevant section in `docs/api.md`. On `edit` — let the user refine first.

If route **changed** (not added): find its existing section by citation, show a diff of what would change.

If route **deleted**: offer to remove its section from `docs/api.md` (but keep a historical note: `<!-- removed YYYY-MM-DD: POST /api/old-endpoint -->`).

### If components changed

Similar flow: detect new components, check `docs/components.md`, offer to add a short entry (name, path, one-line purpose, props summary, citation).

### If schema changed

```bash
git diff prisma/schema.prisma 2>/dev/null
git diff --name-only | grep -E 'migrations/|schema\.'
```

Detect added/removed/changed models. Offer to update `docs/database.md` sections. Flag backfill concerns for NOT NULL columns.

### If new external dependency added

```bash
git diff package.json | grep -E '^\+' | grep -E 'stripe|twilio|openai|@100mslive|firebase|aws-sdk|...'
```

Offer to add a section to `docs/integrations.md` (what it's used for, env vars, provider docs link).

### Always

Never auto-write without approval. Always show a preview. Default to asking.

## Step 3 — Citation validator (NEW)

Walk every `docs/**.md` file. For each `<!-- src: path:start-end -->` marker found:

```bash
# For each citation "src: lib/auth.ts:42-58"
test -f "lib/auth.ts" || echo "BROKEN: file gone"
wc -l < "lib/auth.ts" # line count must be >= end
```

If the cited file is gone or the line range is out of bounds → flag:

```
Stale citations found:

  docs/api.md:87 cites lib/auth.ts:42-58 but the file is gone.
  docs/architecture.md:15 cites lib/services/video.ts:100-120 but file has 85 lines.

These docs may be lying. Want me to:
  1. Mark the affected sections with <!-- stale: verify -->
  2. Regenerate with /docify --refresh <file>
  3. Skip for now
```

Don't block commit on stale citations — warn, let user decide.

## Step 4 — Adaptive checklist (ask only what applies)

Skip items that don't apply. No bloat.

### Always

- [ ] Anything in the diff you didn't mean to include? (debug logs, commented code, unrelated files)
- [ ] Any helpers / refactors / extras the user didn't ask for? If yes, revert or justify.
- [ ] Does this commit do one thing? If bundled, suggest splitting.

### If code changed

- [ ] Run test suite (check `package.json` or equivalent).
- [ ] Run type checker / linter if configured.

### If API / public interface changed

- [ ] `docs/api.md` — covered by Step 2. Did the auto-update run?
- [ ] Breaking change? Say so in commit message.

### If design choice was made

- [ ] Worth logging with `/decision`? (Ask if it's a trade-off future-you would second-guess.)

### If non-obvious bug was fixed (>15 min to root-cause, or subtle cause)

- [ ] Add to `docs/KNOWN-ISSUES.md` with:
  - Symptom
  - Root cause (1–3 sentences, the actual mechanism)
  - Fix (file paths + line ranges)
  - **Prevention rule** — the test/type/lint/checklist item that would catch it next time

Offer to draft the entry yourself from the diff.

### If a tracked gap (`docs/*-GAPS.md`) was shipped

- [ ] Mark the relevant section: `Status: shipped YYYY-MM-DD (commit: <hash>)`
- **Never delete** the section. Preserve history.

### If a milestone hit

- [ ] Update `CLAUDE.md` status section if the project tracks phases there.

## Step 5 — Draft the commit message

Read last 5 commits to match style:

```bash
git log -5 --pretty=format:"%s%n%b%n---"
```

Draft:

```
<type>: short summary in imperative mood

Why: <1-2 sentences — the business or technical reason>
What: <terse list if multi-file>

Closes: <issue ref if any>
```

Explain **why**, not just what. No AI attribution unless the project already uses it.

## Step 6 — Final sanity

- [ ] `git diff --cached` one last time
- [ ] No secrets / API keys / `.env` leaking
- [ ] No large binaries or generated files staged

## Step 7 — Output

```
## Ship checklist — ready

Checked: N of M
Doc updates offered: <count> (applied: <count>)
Stale citations flagged: <count>
Still open:
- <anything blocking>

Suggested commit:
<type>: <summary>
<body>

To commit:
git add <files>
git commit -m "…"
```

**Do not run the commit.** User copies and runs themselves.

## Step 8 — Suggest follow-ups

Before exiting, suggest (one line each, only if applicable):

- Non-obvious design choice made? → *"Worth logging with `/decision`?"*
- Session winding down? → *"Run `/session` to leave a handoff."*
- Bug prevention rule added? → *"Consider adding a test that enforces this."*
- Stale citations flagged? → *"Run `/docify --refresh <file>` when you have 5 minutes."*
