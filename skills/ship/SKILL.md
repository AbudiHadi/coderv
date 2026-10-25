---
name: ship
description: |
  Pre-commit checklist. Reads the diff, offers to update docs itself (not just ask you), validates citations in docs haven't gone stale, drafts a why-focused commit message. Runs before every commit that touches multiple files.

  TRIGGER — suggest this skill (even without /ship prefix) when the user says: "commit", "git commit", "commit this", "push it", "push this", "push up", "create a commit", "make a commit", "ready to ship", "I'm done", "all done", "wrap up this change", "finalize", "let's commit", "commit and push", "ready to merge", "draft commit message", "write commit message".

  SKIP — when the user is only asking about git status without intent to commit (e.g. "what changed?", "show me the diff").
user-invocable: true
argument-hint: "(optional: --security for the deep adversarial review; default is the quality gate)"
---

# Ship — Smart Pre-commit

Goal: docs stay fresh + honest, with minimum friction.

## Flags — `--security` (ADR-022)

`/ship --security` runs the whole flow in **DEEP SECURITY REVIEW** mode: the
Step 4.5 fresh-context reviewer gets the full adversarial brief (fuzzing,
parser hardening, adversarially-crafted input) and `[hardening]` findings
block. This is the explicit opt-in for a security pass; use it when the owner
asks for one.

**Default (no flag) = engineering QUALITY GATE mode.** Realistic
correctness / regression / data-loss / reachable-security defects block as
always; exotic adversarially-crafted-input findings are tagged `[hardening]`
and land in a non-blocking **"Non-blocking debt"** section instead of
blocking — a normal dev commit converges in ONE round. Surface any debt
findings to the owner verbatim (transparency rule); they never block and never
oblige another round.

<!-- coderlap:rule:practical-impact -->
### The practical-impact rule (ADR-028)

> Ignore atomic, theoretical, defensive, or extremely low-impact findings that
> do not materially affect the user. Do not block a commit or release for
> issues that have no realistic user-facing impact, do not affect correctness
> in normal use, do not risk data loss or corruption, do not create a
> security/privacy issue, do not break compatibility, release integrity, or
> core contracts, or are only speculative hardening, cosmetic debt, comment
> wording, micro-cleanup, or unlikely edge cases.

Every finding is declared **`BLOCKER`** or **`DEBT`**:

| | Meaning | Effect |
|---|---|---|
| 🚫 **BLOCKER** | Material impact on **users, data, security/privacy, correctness, compatibility, or release integrity** — and it must NAME which one | Blocks |
| 📋 **DEBT** | Small, defensive, theoretical, cosmetic, or low-probability | Never blocks |

If the reviewer cannot identify a realistic material harm in one of those six
categories, the finding is **DEBT by construction**. When only DEBT remains the
review is **done** — report it and stop; do not go looking for smaller issues.
Practical impact is the stopping rule, not theoretical perfection.

**The label never overrides the severity.** `[debt]` on a real defect does not
demote it, and a `[blocker]` that names no category still blocks as malformed —
so the classification cannot be used to smuggle a bug past the gate, in either
direction.

**Only what this diff caused blocks (ADR-030).** A defect the base code
already had, which this diff neither changes nor newly makes reachable, is
`[debt][pre-existing]` — real, reported, offered for `docs/KNOWN-ISSUES.md`,
but not this commit's to fix. That is a question of cause, not a softer label,
and it needs proof (see `reviewer-loop.md`). With `--security`, old
security/data-loss findings still block.

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

### If the diff resolves an open question on an active effort map

- [ ] Active map naming this topic (`grep -l '^Status: active' docs/PLAN-*.md`)?
  Move the resolved question out of *Open questions*, add the ADR link to
  *Decisions so far*, and if that emptied the frontier run the map's Done
  lifecycle — per the effort-map run-book in the `coderv` skill. This is the
  `/ship`-time update `/before` Step 3 promises; without it the map's frontier
  goes stale.

### If a milestone hit

- [ ] Update `CLAUDE.md` status section if the project tracks phases there.

## Step 4.5 — Converge with the reviewer BEFORE the commit (the pre-commit loop)

Run the full pre-commit reviewer loop in `reviewer-loop.md` beside this file.
Do not proceed to Step 5 until the loop reaches one of its end states as
defined there (CONVERGED, CAP-STOPPED, or REVIEW-UNAVAILABLE).

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

## Step 7 — The Verification Scorecard (the approval moment)

Build and present the scorecard exactly as specified in `scorecard.md` beside
this file. **Never commit without the user's explicit approval**, and commit
exactly the snapshot Step 4.5 certified.

## Step 8 — Suggest follow-ups

Before exiting, suggest (one line each, only if applicable):

- Non-obvious design choice made? → *"Worth logging with `/decision`?"*
- Session winding down? → *"Run `/session` to leave a handoff."*
- Bug prevention rule added? → *"Consider adding a test that enforces this."*
- Stale citations flagged? → *"Run `/docify --refresh <file>` when you have 5 minutes."*
