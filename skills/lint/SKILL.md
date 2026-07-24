---
name: lint
description: |
  Audit a project's docs for contradictions, stale claims, dead references, and rot — the health check that keeps CLAUDE.md + docs/ honest. Docs that lie are worse than no docs: agents and humans act on them. Run it every ~5 sessions, before a release, or whenever docs feel "off".

  TRIGGER — suggest this skill (even without /lint prefix) when the user says: "lint the docs", "audit the docs", "are the docs up to date?", "do the docs match the code?", "docs are lying", "doc rot", "check for contradictions", "is there a gap in the docs?", "stale docs", "clean up the docs", "docs health check", "verify the docs".

  SKIP — when the user wants to GENERATE fresh docs (that's /docify), edit one specific doc by hand, or is mid-task with uncommitted work (lint after shipping, not during).
user-invocable: true
argument-hint: "[optional: docs subfolder or single file to audit]"
---

# Lint — the docs health check

/docify writes docs. /before and /session read them. **Nothing checks them** — claims go stale, rules get superseded twice, TODO lists outlive their plans. This skill is the missing third operation: ingest → query → **lint**.

**Run the sweep in a subagent.** Lint is the most context-hungry skill in the
toolkit (every doc + the code it cites); doing it inline pushes the main
session toward the very dumb zone this toolkit guards against. Spawn one
subagent to execute Steps 1–2 and return findings only. Its brief must demand:
**every finding carries verbatim quotes from BOTH sides** — the doc line and
the conflicting reality — each with `file:line`. Then, before reporting
anything to the user, **machine-verify each quote**:

```bash
sed -n '<line>p' <file>   # must contain the quoted text
```

A quote that fails the string match = fabricated finding → drop it, note
"1 finding dropped (quote didn't verify)", never present it as fact. (Small
scope — one file — may skip the subagent and run inline; the quote rule still
applies.)

## Step 1 — Inventory (read, don't fix yet)

Read `CLAUDE.md` (all of them if a monorepo) and every file in `docs/` (or the scope the user gave). While reading, collect four lists:

1. **Rules** — every ALWAYS / NEVER / "rule:" line, plus any line containing *superseded*, *retired*, *un-superseded*, *back in force*, *OBSOLETE*, *replaced by*.
2. **Claims about state** — "NOT committed", "NOT restarted", "NOT published", "pending", "blocked on", "OWNER TODO", "next session should", "waiting for", version numbers, dates, URLs, file paths, command invocations.
3. **References** — `<!-- src: path:lines -->` citations, inter-doc links, named files/functions.
4. **Structure** — `*.draft.md` files, STALE banners, docs no other doc links to.

## Step 2 — Cross-check against reality

For each list, verify the cheap way — greps and file checks, not guesswork:

| Check | How |
|---|---|
| 🔴 **Contradictions** | Two rules that can't both hold; a rule whose supersede chain has 2+ status flips with no single line stating the CURRENT status. |
| 🟠 **Stale claims** | "NOT committed/restarted/published" older than ~7 days → check `git log` / the running process; TODOs whose plan changed; versions in docs vs `package.json`/`pubspec.yaml`; dead URLs skipped (report only). |
| 🟠 **Dead references** | Cited file gone, or line range beyond the file's length (`wc -l`); links to docs that don't exist; documented commands missing from `package.json`/`scripts/`. |
| 🟡 **Rot** | Draft files with STALE banners older than the last real doc update; orphan docs; empty sections; KNOWN-ISSUES prevention rules that never landed in CLAUDE.md or a test. |
| 🟡 **Stale coderlap artifacts** | This project's spec + receipt under `~/.claude/coderlap/` (keyed by project-root path, `/` → `-`): spec describes a task that already shipped (its outcomes appear in `git log`) → offer cleanup. A leftover spec misleads the next `/ship` reviewer into auditing against last week's task. |
| 🟠 **Stale architecture review** | The newest `docs/ARCH-REVIEW-*.md` carries a `> Base commit:` stamp — if source files changed since it — committed (`git diff --name-only <base>..HEAD -- <top-level source dirs>` non-empty) **or** still in the working tree (`git status --porcelain -- <top-level source dirs>` non-empty) — its findings may describe code that's since changed. (A `+dirty:` list on the stamp records uncommitted files WITH their blob SHAs — content the audit already saw; only files outside that list, or whose current `git hash-object` no longer matches, count — including files later committed unchanged, whose committed blob still matches the stamped hash.) Flag it "may be stale — re-run the 🏛 audit". (A commit stamp orders correctly even for same-day commits, which a date-only filename can't.) No stamp → fall back to comparing the filename date against the last structural commit date, and flag the missing stamp itself. Don't flag the findings' content (that's the audit's job, not lint's) — only its freshness. |

Don't flag style. Don't flag history (SESSIONS/DECISIONS entries are records, not claims — only their *unresolved* forward-looking statements count).

## Step 3 — Report (terse by default)

```markdown
🩺 Doc lint: <N> findings — 🔴 <a> contradictions · 🟠 <b> stale · 🟡 <c> rot

Top issues:
1. 🔴 <file:line> — <one line: what contradicts what>
2. 🟠 <file:line> — <claim> (reality: <what's actually true>)
3. 🟡 <file> — <rot in one line>

👉 **My recommendation: <fix the 🔴 now | all clear — docs are honest>.**

*Full findings table + suggested edits? Say "details".*
```

Every finding needs `file:line` and the **reality** it conflicts with — a lint that says "seems stale" is itself a lie.

## Step 4 — Offer the fixes (never auto-apply)

- Mechanical fixes (update a version string, mark a resolved TODO, add the missing "CURRENT status" line to a flip-flopped rule, refresh a citation) → offer to apply in one batch, show the diff plan first.
- Judgment calls (which of two contradicting rules wins) → ask, one question per conflict, with a recommendation.
- **Never delete history.** Superseded content gets a status line, not removal. Archives are append-only.

## Step 5 — Close the loop

After fixes are applied: one-line entry in `docs/SESSIONS.md` ("doc lint: N findings, M fixed"). If a finding revealed a *recurring* failure mode, suggest `/decision` (why the rule flip-flopped) or a KNOWN-ISSUES prevention rule — that's how the same rot stops coming back.

Finally, stamp the freshness state file — `/coderv` reads it to decide whether
a pipeline needs a lint first:

```bash
ROOT=$(pwd); while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/CLAUDE.md" ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/CLAUDE.md" ] || ROOT=$(pwd)   # key by project root, same as all coderlap artifacts
mkdir -p ~/.claude/coderlap/state
date +%F > ~/.claude/coderlap/state/lint-$(printf '%s' "$(cygpath -w "$ROOT" 2>/dev/null || printf '%s' "$ROOT")" | tr '/\\' '--' | tr -d ':')
```
