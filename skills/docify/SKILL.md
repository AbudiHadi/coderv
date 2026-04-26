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

## Step 2 — Build the plan (terse default)

**Default response — short:**

```markdown
🔍 Detected: <Stack name> · <N routes> · <M models> · <K components> · <X external services>.

Will write **N drafts** in `docs/` + merge **<M> missing rules** into your CLAUDE.md (your custom rules stay untouched). All claims cite source files. Drafts only — nothing real until you `/docify approve <name>`.

Takes ~5 min.

👉 **My recommendation: approve and let me run it.**

Reply `go` to start, or say "details" to see the full file list and what each will contain.
```

**On request ("details"), expand to the full breakdown:**

```markdown
**What I found:**

| Detected | Found |
|---|---|
| 🏗️ Stack | <stack> |
| 📦 Package manager | <npm/yarn/pip/etc.> |
| 🛣️ API routes | <N> in `<path>` |
| 🗄️ Database models | <M> in `<path>` |
| 🧩 Components | <K> in `<path>` |
| 🔌 External services | <list> |

**What I'd write (all drafts, you approve before promotion):**

| File | What it'll contain |
|---|---|
| 📜 `CLAUDE.md` | <X> missing rules merged · <Y> custom rules untouched |
| 📘 `docs/overview.draft.md` | What the project is + how to run it |
| 🏛️ `docs/architecture.draft.md` | Request flow, layers, services |
| 🛣️ `docs/api.draft.md` | All <N> routes |
| 🧩 `docs/components.draft.md` | <K> components with props |
| 🗄️ `docs/database.draft.md` | <M> models + relationships |
| 🔌 `docs/integrations.draft.md` | External services |
| 📋📝🐛 Empty scaffolds | DECISIONS, SESSIONS, KNOWN-ISSUES |

**Won't touch:**
- Existing files I didn't generate.
- Your custom CLAUDE.md rules (no `coderlap:rule:*` marker → not ours).
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

**Default response — short:**

```markdown
✨ Generated <N> drafts + merged <M> rules into CLAUDE.md (your custom rules untouched).

⚠ <K> spots I couldn't verify cleanly — marked `<!-- TODO: verify -->` in the drafts.

👉 **My recommendation: skim the drafts (especially the TODOs), then `/docify approve overview` first** — overview is the highest-stakes intro doc. Rest can follow in any order.

*Want the file-by-file breakdown + the list of TODO locations? Say "details".*
```

**On request ("details"), expand:**

```markdown
| File | Size | Source references |
|---|---|---|
| 📘 docs/overview.draft.md | <N> lines | <X> source refs |
| 🏛️ docs/architecture.draft.md | <N> lines | <X> source refs |
| 🛣️ docs/api.draft.md | <N> lines | <N> routes, <X> source refs |
| 🧩 docs/components.draft.md | <N> lines | <N> components, <X> source refs |
| 🗄️ docs/database.draft.md | <N> lines | <N> models, <X> source refs |
| 🔌 docs/integrations.draft.md | <N> lines | <N> services, <X> source refs |
| 📋📝🐛 DECISIONS / SESSIONS / KNOWN-ISSUES | empty | ready for use |

**TODOs flagged** (worth a 30-second look before approve):
| File | Line | What's unclear |
|---|---|---|
| <file> | <line> | <one-line description> |

**To approve drafts:**
```bash
/docify approve overview                         # one at a time
/docify approve overview architecture api        # or batch
```

**To commit when happy:**
```bash
git add CLAUDE.md docs/ && git commit -m "docs: initial docify run"
```
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
