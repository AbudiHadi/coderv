# <PROJECT NAME> — Master Documentation Index

> **Purpose:** Single source of truth for all project documentation. Connects every doc, explains what each is for, and tells Claude (and humans) how to add, update, and retire docs without creating parallel truths.
>
> **Last Updated:** YYYY-MM-DD
> **Maintained by:** Every contributor (Claude included) — if you touch a doc, update this index in the same commit.

---

## How to Use This Index

1. **Starting a task?** Use `/docs <task>` to map the task to the right docs.
2. **Adding a feature?** After shipping, `/ship` walks through the update checklist.
3. **Adding a new doc?** Use `/doc-new` — it registers the doc here automatically.
4. **Tracking gaps?** Use `/gap` for missing-feature tracking.
5. **Logging a decision?** Use `/decision` for ADRs.

### Slash Commands

| Command | When to use |
|---|---|
| `/docs [task]` | Any non-trivial task — loads this index and tells you what to read |
| `/before <task>` | Enforced read-before-code: runs doc checklist + greps repo for patterns |
| `/gap [area\|close N\|new area]` | List, drill, close, or create gap docs |
| `/doc-new <type> <title>` | Create a new doc + auto-register here |
| `/decision <title>` | Log an ADR in `docs/DECISIONS.md` |
| `/ship` | Pre-commit checklist: tests, docs, gap closures, changelog |
| `/session` | Write an end-of-session handoff note for the next session |
| `/repeat <symptom>` | Check `docs/KNOWN-ISSUES.md` before debugging |
| `/trace <symptom>` | Root-cause walk from symptom back through the code |

---

## Doc Registry

Status legend: `current` = live truth • `reference` = stable knowledge • `historical` = frozen snapshot • `plan` = not yet built • `archive` = superseded

### Core

| Doc | Purpose | Status |
|---|---|---|
| [`docs/MASTER-INDEX.md`](./MASTER-INDEX.md) | This file — doc registry | current |
| [`docs/DECISIONS.md`](./DECISIONS.md) | ADR log — why we chose X over Y | current |
| [`docs/KNOWN-ISSUES.md`](./KNOWN-ISSUES.md) | Recurring bugs + their fixes | current |
| [`docs/SESSIONS.md`](./SESSIONS.md) | End-of-session handoff notes | rolling log |

### Add more rows as the project grows

Examples:

| Doc | Read when you're touching… | Update when you… |
|---|---|---|
| `docs/architecture.md` | Service layer, request flow | Rename a service, change request flow |
| `docs/api.md` | Any API route | Add/change/remove an API route |
| `docs/database.md` | Schema, models | Run a migration |
| `docs/<AREA>-GAPS.md` | A domain with known missing features | Close or add a gap |

---

## Task → Doc Map

| Task | Read in this order |
|---|---|
| Add an API route | `docs/api.md` → similar existing route |
| UI component | `docs/components.md` → similar component |
| DB schema | `docs/database.md` → schema file |
| External API | `docs/integrations.md` → existing integration |
| Bug fix | `docs/KNOWN-ISSUES.md` → `docs/DECISIONS.md` |
| Design choice | `docs/DECISIONS.md` (add ADR if new) |

---

## Docs to Update on Feature Changes

| Change | Docs to update |
|---|---|
| New API route | `docs/api.md` |
| New component | `docs/components.md` |
| Schema migration | `docs/database.md` |
| External API added | `docs/integrations.md` + CLAUDE.md Integrations Registry |
| Shipped a gap | `docs/*-GAPS.md` — mark `shipped YYYY-MM-DD (commit: <hash>)` |
| New design decision | `docs/DECISIONS.md` — add ADR |
| Fixed a recurring bug | `docs/KNOWN-ISSUES.md` — add entry |

---

## Gap Tracking

Gap docs track what's missing. Format: `docs/<AREA>-GAPS.md`. Each entry has:

- **Status:** `missing` / `partial` / `broken` / `shipped YYYY-MM-DD` / `wontfix YYYY-MM-DD — <reason>`
- **Priority:** P0 (blocker) → P3 (polish)
- **Impact:** who suffers
- **Effort:** S / M / L
- **Dependencies:** what blocks it
- **Acceptance criteria:** how we know it's done

Closing a gap = change status to `shipped YYYY-MM-DD`, keep everything else for history. Never delete.

**Current gap docs:** _(none yet — use `/gap new <area>` to start tracking)_

---

## Decision Log (ADRs)

See [`docs/DECISIONS.md`](./DECISIONS.md). Log every choice that will be second-guessed later: library picks, patterns, trade-offs, scope cuts. Use `/decision <title>` to add one.

---

## How to Add a New Doc

Use `/doc-new <type> <title>`. The skill creates the file with the required header and registers it here.

Required header for any new doc:

```markdown
# <Title>

> **Purpose:** one-line
> **Audience:** who reads this
> **Last Updated:** YYYY-MM-DD
> **Status:** current | reference | plan | historical
```

---

## Self-check (run before ending a task)

- [ ] New doc? → registered here
- [ ] Shipped a gap? → marked `shipped YYYY-MM-DD (commit: <hash>)`
- [ ] New design choice? → ADR in `DECISIONS.md`
- [ ] Found/fixed a recurring bug? → entry in `KNOWN-ISSUES.md`
- [ ] Phase/milestone done? → update project status wherever it lives
- [ ] User-facing strings changed? → both locale files (if i18n)
- [ ] Schema changed? → `docs/database.md` + all services reading changed fields
