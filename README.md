# CoderLap Docs Toolkit

Five slash commands that help devs keep extremely clear docs — without getting tired or trying to remember.

> **The problem:** Claude without structure drifts. Re-asks settled questions. Re-introduces fixed bugs. Skips docs. Scope-creeps. The next session starts from zero. Docs rot within a week.
>
> **The answer:** five commands. One generates real docs from your code. Four keep them fresh. Markdown only. No framework. No dependency.

---

## The five commands

| Command | The tired moment it fixes |
|---|---|
| **`/docify`** | *"I need real docs but I don't want to write them."* — Scans your code, generates `CLAUDE.md` + 6 professional docs (architecture, api, components, database, integrations, overview) with source citations. Run once per project. |
| **`/before <task>`** | *"What should I even read first?"* — Claude reads the relevant docs, greps prior art, checks past decisions, states a plan, waits for your OK. Auto-skips tiny tasks. |
| **`/decision <title>`** | *"Write down why, so I never have to explain it again."* — Logs an ADR in 30 seconds while the choice is fresh. |
| **`/ship`** | *"Did I forget to update any docs before committing?"* — Reads the diff, **auto-updates api.md / components.md / database.md** from the code change, validates every citation in the docs is still accurate, drafts a why-focused commit message. |
| **`/session [last]`** | *"Pick up where I left off."* — End of session → leaves a handoff. Start of next → `/session last` reads it. |

## The loop

```
/docify                # once per project (generates CLAUDE.md + 6 docs)
                       # ↓ every task after that:
/session last          # what was I doing?
/before <task>         # Claude plans, waits for OK
<you approve, code>
/ship                  # auto-updates docs, validates citations, drafts commit
<commit>
/session               # handoff for next time
```

`/docify` once. Four commands daily. Docs stay clean + honest as a side effect of doing your work.

---

## Install

**One command:**

```bash
curl -fsSL https://coderv.dev/install.sh | bash
```

Skills land in `~/.claude/skills/` and become available in every project you open with Claude Code.

**Manual path:**

```bash
git clone https://github.com/AbudiHadi/coderv
cd coderv
./install.sh
```

**Per-project install** (skills under `./.claude/skills/`):

```bash
curl -fsSL https://coderv.dev/install.sh | bash -s -- --project
```

**Update:**

```bash
curl -fsSL https://coderv.dev/install.sh | bash -s -- --force
```

**Uninstall:**

```bash
cd coderv && ./install.sh --uninstall
```

---

## The three living files

Once you run `/before` in a fresh project, it scaffolds these:

| File | Role |
|---|---|
| `docs/DECISIONS.md` | ADRs — every design choice with context, alternatives, consequences. Newest first. Never deleted. |
| `docs/KNOWN-ISSUES.md` | Recurring bugs with symptom, root cause, fix, and the **prevention rule** that stops recurrence. |
| `docs/SESSIONS.md` | Rolling log of end-of-session handoffs. |

Plus `CLAUDE.md` at project root that tells Claude how to use them.

---

## Design principles

- **Markdown only.** No database. No framework. No runtime dependency. If the toolkit disappeared tomorrow, the files still tell you what's going on.
- **Idempotent.** Every command is safe to re-run.
- **Never delete history.** Closed items become `shipped YYYY-MM-DD`, superseded items stay with a pointer. You can always trace why.
- **Adaptive.** `/ship` only asks about docs your changes actually touched. `/before` auto-skips tiny tasks.
- **Project-agnostic.** No hardcoded paths. No language assumptions. Works in any repo.

---

## FAQ

**Does this replace `CLAUDE.md`?**
No. `/before` will offer to create `CLAUDE.md` if it's missing, using a standard template. Your project-specific rules stay.

**My project already has `docs/` with other files. Will this clobber them?**
No. Nothing overwrites. `/before` only creates the four files if they're missing.

**What if I don't want to log ADRs?**
Don't run `/decision`. Every command is optional. The toolkit is lighter than any framework — use what helps.

**Why not just hooks / automation?**
Discipline needs to survive "tired". Hooks fail silently, prompts don't. These run when you invoke them and do their job visibly. That's the point.

---

## Licence

CoderLap Source-Available Licence v1.0 — see [LICENCE](./LICENCE).

Free to read. Free for personal evaluation. **All other use — commercial, redistribution, hosting, incorporation, modification-then-sharing — requires written permission from Abdullah Hadi (support@coderv.com).**

Full licence: https://coderv.dev/licence
