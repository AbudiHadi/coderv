---
name: doc-new
description: Create a new documentation file at the correct path with the required header and auto-register it in docs/MASTER-INDEX.md. Use when the user wants to add a new doc, write up a design, or capture a spec. Prevents unregistered "orphan" docs that future Claude cannot find. Works in any project initialised with /doc-init.
user-invocable: true
argument-hint: "<type> <title> — e.g. 'reference auth-flow', 'business pricing-model', 'gap billing', 'audit project-2026-05-01', 'plan voice-input'"
---

# Create a New Doc

You've been asked to create a new doc. Follow `docs/MASTER-INDEX.md` §"How to Add a New Doc" — don't freelance.

## Step 1 — Sanity check

```bash
ls docs/MASTER-INDEX.md 2>/dev/null
```

If missing: tell the user to run `/doc-init` first. Stop.

## Step 2 — Load the rules

```
Read docs/MASTER-INDEX.md
```

## Step 3 — Decide if a new doc is warranted

**Default answer is NO.** Check first:
- Can an existing doc absorb this? `grep -l "<keyword>" docs/`
- Is this just notes that belong in a PR description?
- Is this a gap → should be `/gap new <area>`?
- Is this a decision → should be `/decision`?
- Is this a known bug → should be an entry in `docs/KNOWN-ISSUES.md`?

Proceed only if none of the above fit.

## Step 4 — Parse the argument

Expected: `<type> <title>` where type is one of:

| Type | Path pattern | Naming |
|---|---|---|
| `reference` | `docs/<kebab-case>.md` | technical reference, lowercase-kebab |
| `business` | `docs/<UPPER-KEBAB>.md` | business/journey, UPPERCASE-KEBAB |
| `gap` | `docs/<AREA>-GAPS.md` | delegate to `/gap new <area>` |
| `audit` | `docs/PROJECT-AUDIT-YYYY-MM-DD.md` | dated snapshot, **immutable** |
| `plan` | `docs/plans/<feature>.md` | incubation, not-yet-greenlit |

If ambiguous, ask.

## Step 5 — Write the file

Every new doc **must** have this header:

```markdown
# <Title>

> **Purpose:** one-line description
> **Audience:** who reads this (engineers, partners, QA, leadership…)
> **Last Updated:** YYYY-MM-DD
> **Status:** current | reference | plan | historical

---

<body>
```

Type-specific additions:

- **gap**: follow `MASTER-INDEX` §"Gap Tracking" contract — delegate to `/gap new <area>` instead.
- **audit**: include "Scope" and "Branch/commit" in the header. File is **immutable** once committed.
- **plan**: include "Decision required by", "Decision owner", and "Next steps if greenlit".
- **reference**: include "See also" at bottom with links to related docs.
- **business**: include "Last reviewed with stakeholders" + date.

## Step 6 — Register in MASTER-INDEX (non-negotiable)

Edit `docs/MASTER-INDEX.md` §"Doc Registry" and add a row in the right section:

- `reference` → Core section
- `business` → Product & Business section (create if missing)
- `gap` → Gap Tracking section
- `audit` → Audits section (create if missing)
- `plan` → Plans section (create if missing)

Row format must match existing rows: path, one-line purpose, status.

## Step 7 — If this replaces an older doc

1. Mark the old doc `archive` in MASTER-INDEX.
2. Add a banner to the top of the old doc:
   ```markdown
   > ⚠️ **Archived YYYY-MM-DD.** Superseded by [<new>.md](./<new>.md). Kept for history — do not use for current work.
   ```
3. Grep for links pointing at the old doc and update them.
4. **Never `git rm`** the old file.

## Step 8 — Confirm

Before ending:
- [ ] File created at the correct path
- [ ] Required header present with today's date
- [ ] Registered in MASTER-INDEX §"Doc Registry"
- [ ] (If replacement) old doc has archive banner

## Output format

```
## Created: <path>

**Type:** <type>
**Registered:** docs/MASTER-INDEX.md §<section>
**Replaces:** <none | path>

**Next:** <fill out body | review with team | commit>
```
