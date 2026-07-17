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

## Step 4.5 — Fresh-context reviewer (the independent audit)

The session that wrote the code cannot be trusted to grade it — accumulated
context drifts. Spawn ONE reviewer subagent with a clean context. Give it:

- the actual diff (`git diff` output, not your description of it),
- the spec checklist written by /before — the ground truth for intent. Its
  name is keyed by project root:
  ```bash
  ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
  cat ~/.claude/coderlap/specs/$(printf '%s' "$ROOT" | tr '/' '-').md
  ```
- an adversarial brief: **"Find what's wrong. For each spec item, verdict
  pass/fail with the diff lines proving it, quoted verbatim with file:line.
  Run the build and tests if the project has them; paste raw output. Flag
  anything in the diff the spec never asked for."**

When the reviewer returns, **machine-verify its quotes before believing it**:
each quoted line must literally exist at its cited location —

```bash
sed -n '<line>p' <file>   # must contain the quoted text
```

A quote that fails the string match = fabricated evidence → drop that finding,
note it, and re-ask the reviewer for that item. Reviewer findings that survive
become scorecard gates below.

No spec file exists (work done without /before)? Say so — the "spec verified"
gate scores ✖ and the scorecard caps below 100%.

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

The score is **computed, never felt**: gates passed / gates total, each gate a
pass/fail check with its real output shown. The model's job is to run checks
and show receipts — not to estimate confidence. Rules:

- **100% requires every gate ✅ with evidence attached.** A check that can't
  run (no tests configured, no spec file) scores ✖ with the reason — never
  silently dropped from the denominator, never rounded up.
- Claims quote their evidence: "committed" shows the `git log` line; "tests
  pass" shows the runner's summary line. **No pasted output → no claim.**
- Human-judgment items (a trade-off, a design choice) are listed under
  "Judgment items" — NEVER folded into the percentage.

The gates (drop only those meaningless for the project — say which and why):

| # | Gate | Evidence shown |
|---|---|---|
| 1 | Grounding receipt exists for this session | receipt path + mtime |
| 2 | Spec checklist: every item verified in the diff | per-item verdict + quoted diff line |
| 3 | Build passes | last line of build output |
| 4 | Tests pass | runner summary ("N passed, 0 failed") |
| 5 | Doc citations valid (Step 3) | "N/N checked" |
| 6 | Reviewer quotes machine-verified | "N/N string-matched" |
| 7 | Fresh-context reviewer: no open objections | reviewer's verdict line |
| 8 | Nothing unrequested in the diff | reviewer + your own check |
| 9 | No secrets / large binaries staged | check output |

**Default response:**

````markdown
🚢 Ready to ship — <N> files, <one-line summary>.

**VERIFICATION SCORE: <P>% (<passed>/<total> gates)**

✅ 1 Grounding receipt        → <path> (<date>)
✅ 2 Spec verified 4/4        → [say "evidence" to see per-item proof]
✅ 3 Build                    → "✓ built in 4.2s"
✖ 4 Tests                    → no test runner configured in this repo
… (all gates, one line each, pasted evidence or the reason it can't run)

Unverified claims: <0, or list them>
Judgment items for you: <none, or one line each>

**Suggested commit message:**
```
<type>: <short summary>

<2-3 sentences on WHY>
```

**On "approve" I run:** `git add <files> && git commit -m "<message>"` — the codex-review-gate reviews the outgoing diff before it lands.

👉 **My recommendation: <approve — 100% | fix gate N first | ship at <P>% because <reason>>.**
````

Below 100%, the failing gate line already says exactly what to fix — the user
should never have to ask "why not 100?".

**On request ("details" / "show checklist"), expand:**

```markdown
**Full pre-commit checklist 🚢**

| Area | Status |
|---|---|
| 📦 Files staged | <N files: one-line summary> |
| 📚 Doc updates offered | <N offered, M applied, K skipped> |
| 🔗 Doc references checked | <✅ all good | ⚠ N stale> |
| 🐛 Bug-prevention notes | <✅ logged | ✅ not needed> |
| 🔐 Secrets / large files | <✅ clean | ⚠ <list>> |
| 🧪 Tests / typecheck | <✅ passed | ⚠ skipped | ⚠ failed> |

**Open issues:**
- <blocker, or ✅ none>
```

**Never commit without the user's explicit approval.** Show the command and
wait for "approve". Then run the commit yourself via the Bash tool — that
routes the diff through the codex-review-gate (the machine reviewer). A
commit the user runs in their own terminal would silently bypass that gate.
If the gate denies: adjudicate each finding, fix the real ones, list any
rejected ones to the user with your reason, then retry.

## Step 8 — Suggest follow-ups

Before exiting, suggest (one line each, only if applicable):

- Non-obvious design choice made? → *"Worth logging with `/decision`?"*
- Session winding down? → *"Run `/session` to leave a handoff."*
- Bug prevention rule added? → *"Consider adding a test that enforces this."*
- Stale citations flagged? → *"Run `/docify --refresh <file>` when you have 5 minutes."*
