---
name: docify
description: |
  Generate a professional docs/ folder from an existing codebase. Scans the project, detects the stack, and writes CLAUDE.md + architecture.md + api.md + components.md + database.md + integrations.md + overview.md — all grounded in file+line citations so docs never lie. Preserves custom CLAUDE.md rules when it already exists.

  TRIGGER — suggest this skill (even without /docify prefix) when the user says the words "docs", "doc", "documentation", "readme", "README" — OR any of these phrases: "write docs", "write documentation", "create docs", "generate docs", "make docs", "make a doc", "make a full docs", "need docs", "no docs exist", "this project has no README", "document this project", "explain the codebase", "document what we have", "make docs for X", "I need docs", "our docs are outdated", "fresh docs", "bootstrap docs", "docs are missing", "docs outdated".

  SKIP — when the user wants to edit ONE specific existing doc file by hand ("fix a typo in api.md", "add a line to architecture.md"), OR when "docs" means something clearly unrelated like "the docs page on our website" or a doctor / document of another kind.

  On ambiguous single-word mentions ("docs?", "about docs"), briefly clarify intent before running — "do you mean generate a full docs folder (/docify), or edit an existing doc file?"
user-invocable: true
argument-hint: "[--refresh <file>] — omit for first-time generation"
---

# Docify — Generate Real Docs From Your Project

Stops the "blank CLAUDE.md" problem. Reads your code, writes docs that actually reflect it.

## Safety rules (non-negotiable)

1. **Never hallucinate.** Every factual claim in a generated doc MUST cite a file and line range: `<!-- src: path/to/file.ts:42-55 -->`. If you can't cite it, write `<!-- TODO: verify -->` and move on.
2. **Never overwrite existing docs** without explicit approval. Default is skip.
3. **Never silently modify `CLAUDE.md`.** Merge logic below handles it safely.
4. **Show a plan first.** Big file-generating operations require explicit user approval.
5. **Drafts first.** Generated docs land as `docs/<name>.draft.md`. User promotes via `/docify approve <file>` to make them real. (Safer than directly writing final files.)

## Step 0 — Mode check

### `/docify` (no args) → first-time generation

Proceed to Step 1.

### `/docify --refresh <file>` → regenerate one doc

Re-scans the relevant parts of the codebase and rewrites just that doc. Citations re-validated.

### `/docify approve <file>` → promote a draft

`docs/api.draft.md` → `docs/api.md`. The old file (if any) gets renamed to `docs/api.md.bak-YYYY-MM-DD`.

### `/docify --help` → show usage

## Step 1 — Scan the project

```bash
ls -la
cat package.json 2>/dev/null | head -60
cat pyproject.toml 2>/dev/null | head -40
cat Cargo.toml 2>/dev/null | head -40
cat Gemfile 2>/dev/null | head -20
cat go.mod 2>/dev/null | head -20
ls .env.example 2>/dev/null && echo "--- env ---" && cat .env.example
find . -maxdepth 3 -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next \) -prune -o -type d -print 2>/dev/null | head -40
```

Detect:
- **Stack** (Next.js / Rails / Django / Express / FastAPI / Go / etc.)
- **Package manager + commands** (build, test, dev, lint)
- **Entry points** (main, index, app, server files)
- **Routing folder** (`app/api/`, `routes/`, `controllers/`, `pages/api/`)
- **Schema / ORM** (Prisma, Sequelize, Drizzle, SQLAlchemy, ActiveRecord, etc.)
- **Components folder** (`components/`, `src/components/`, `app/components/`)
- **External services** (from `.env.example`, imports of `stripe`, `twilio`, `openai`, etc.)
- **Existing docs** in `docs/` (never clobber)
- **Existing `CLAUDE.md`** and its contents

## Step 2 — Build the plan

Output a concrete plan like this:

```
## Docify plan

Detected:
- Stack: Next.js 16 + Prisma + PostgreSQL
- Package manager: npm
- Routing: app/api/** (47 routes found)
- Schema: prisma/schema.prisma (18 models)
- Components: components/** (23 files)
- External: Stripe, Twilio, 100ms (from .env.example)

Will generate:
- CLAUDE.md              (merge: 3 missing rules to add, 12 existing rules untouched)
- docs/overview.draft.md       [NEW]
- docs/architecture.draft.md   [NEW]
- docs/api.draft.md            [NEW — covers 47 routes]
- docs/components.draft.md     [NEW — covers 23 components]
- docs/database.draft.md       [NEW — covers 18 models]
- docs/integrations.draft.md   [NEW — covers 3 external services]
- docs/DECISIONS.md            [NEW — empty, ready for /decision]
- docs/KNOWN-ISSUES.md         [NEW — empty, ready for /ship entries]
- docs/SESSIONS.md             [NEW — empty, ready for /session]

Will NOT touch:
- docs/custom-business.md (already exists)
- Your 12 custom CLAUDE.md rules (no markers → not ours)

Estimated: ~5 minutes
Approve? (y/n)
```

Wait for approval. Do not proceed on silence.

## Step 3 — CLAUDE.md merge logic

### If missing
Create `CLAUDE.md` from template. Every rule the toolkit owns includes a marker:
```markdown
<!-- coderlap:rule:loop -->
## The loop (every task)

1. Start of session: **`/session last`** — read the last handoff.
2. Before coding: **`/before <task>`** — Claude reads docs, plans, waits for approval.
…
```

### If exists
1. Grep for `<!-- coderlap:rule:* -->` markers.
2. For each rule the toolkit ships, check if its marker is present.
3. Collect missing rules.
4. Show the user exactly what would be added:

```
CLAUDE.md already exists (234 lines).

Our rules already present (skipped):
  ✓ coderlap:rule:loop
  ✓ coderlap:rule:never-delete-history
  ✓ coderlap:rule:absolute-dates

Our rules missing — would be added at the end:
  + coderlap:rule:suggest-followups
  + coderlap:rule:prevention-rules
  + coderlap:rule:validate-citations

Your existing rules (untouched):
  • 12 lines of your custom project rules

Approve adding the 3 missing rules? (y/n)
```

5. On approval, append `## Rules (added by /docify YYYY-MM-DD)` section with the missing rules. Never edit existing content.

### Rule markers we ship

```
coderlap:rule:loop               — the /before → /ship → /session loop
coderlap:rule:principles         — SR, DRY, CC, SoC
coderlap:rule:never-unrequested  — don't add scope
coderlap:rule:never-delete-history — mark status instead
coderlap:rule:absolute-dates     — YYYY-MM-DD only
coderlap:rule:suggest-followups  — suggest /decision /ship /session at the right moment
coderlap:rule:prevention-rules   — non-obvious bug fixes get prevention rules in KNOWN-ISSUES
coderlap:rule:validate-citations — docs must cite src: lines; verify on /ship
coderlap:rule:claude-md-stable   — CLAUDE.md edits are explicit, not auto
```

## Step 4 — Generate each doc (draft form)

Every generated doc starts with this header:

```markdown
# <Title>

> **Generated by `/docify` on YYYY-MM-DD from commit `<hash>`.**
> **Draft.** Promote with `/docify approve <filename>`.
> **Regenerate this file only:** `/docify --refresh <filename>`.
>
> Every factual claim cites a source. Look for `<!-- src: -->` comments.
```

### docs/overview.draft.md
- What the project is (one paragraph, from README / package.json description)
- Stack summary
- How to run it (from scripts in package.json)
- Directory map (top-level folders + one-line purpose each)
- Where to go next in the docs

Every claim cited. If no README exists, write `<!-- TODO: verify -->` for the "what it is" paragraph.

### docs/architecture.draft.md
- Request flow (entry → routing → service → data layer)
- Layering (where business logic lives vs routes vs persistence)
- Core services discovered by reading `lib/services/` or equivalent
- Cross-cutting concerns (auth, logging, error handling) — only if found

One sentence per service, with citation.

### docs/api.draft.md
- For each route found:
  - Method + path
  - Auth requirement (read the handler for `auth()`, `session`, middleware)
  - Request shape (read the Zod/Joi schema if any)
  - Response shape (read the `return` statements)
  - Errors (read `catch` blocks)
  - Source citation `<!-- src: app/api/foo/route.ts:1-45 -->`

Group by folder. Skip routes Claude can't parse confidently — mark them `<!-- TODO: verify -->`.

### docs/components.draft.md
- For each component found (top 30 by size / reuse):
  - Name, path, props interface
  - One-line purpose (from JSDoc or inferred)
- Grouped by folder
- "Patterns" section: any reusable patterns (CC, composition, etc.)

### docs/database.draft.md
- Every model/entity with fields + types
- Relationships (1:1, 1:N, N:N)
- Indexes that matter
- Migration history (list files in `prisma/migrations/` or equivalent)
- Citation per model

### docs/integrations.draft.md
- Every external service found in:
  - `.env.example` (env var names)
  - `package.json` dependencies (known SDK names)
  - Imports in services
- For each: what it's used for (read the service file), env vars needed, link to provider docs

### docs/DECISIONS.md, KNOWN-ISSUES.md, SESSIONS.md
- Empty headers + usage hint. Created as real files (not drafts) since they have no content to verify.

## Step 5 — Citation format

All citations use HTML comments so they survive markdown rendering:

```markdown
This route validates input via Zod. <!-- src: app/api/invite/route.ts:12-38 -->
```

Line ranges allowed (`42-58`), not just single lines. Use the smallest range that supports the claim.

## Step 6 — Report what was generated

```
## Docify complete (draft mode)

Generated:
  docs/overview.draft.md       (58 citations)
  docs/architecture.draft.md   (22 citations)
  docs/api.draft.md            (47 routes, 141 citations)
  docs/components.draft.md     (23 components, 89 citations)
  docs/database.draft.md       (18 models, 54 citations)
  docs/integrations.draft.md   (3 services, 18 citations)
  docs/DECISIONS.md            (empty — ready for /decision)
  docs/KNOWN-ISSUES.md         (empty)
  docs/SESSIONS.md             (empty)

CLAUDE.md:
  3 missing rules added under "Rules (added by /docify 2026-04-23)"
  Your 12 custom rules untouched.

TODOs flagged: 4
  docs/overview.draft.md:3 — project description
  docs/api.draft.md:217 — /api/webhook/stripe auth unclear
  docs/api.draft.md:304 — /api/legacy/export response shape
  docs/database.draft.md:88 — User.metadata JSON shape

Next steps:
  1. Review the drafts (grep for "TODO: verify" to find weak spots)
  2. Promote each: /docify approve overview / architecture / api / ...
  3. Commit: git add CLAUDE.md docs/ && git commit -m "docs: initial docify"
```

## Step 7 — `/docify approve <file>` behavior

1. Check `docs/<file>.draft.md` exists.
2. If `docs/<file>.md` exists (real version), rename to `docs/<file>.md.bak-YYYY-MM-DD`.
3. Rename draft to real: `docs/<file>.draft.md` → `docs/<file>.md`.
4. Report:
```
Promoted: docs/api.md
Backup saved: docs/api.md.bak-2026-04-23 (if prior version existed)
```

## Step 8 — `/docify --refresh <file>` behavior

1. Re-scan only the parts of the codebase the doc covers.
2. Read the existing (real or draft) doc for comparison.
3. Generate a new draft with updated content + citations.
4. Don't overwrite the real file — create `docs/<file>.draft.md`.
5. Show the user a diff summary: "+12 new routes, -3 removed routes, 4 citations updated."
6. User promotes via `/docify approve <file>`.
