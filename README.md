# Claude Docs Toolkit

Ten slash commands that make Claude Code a disciplined programming partner. Works in any project.

> **What it solves:** Claude without structure drifts. It re-asks settled questions, re-introduces fixed bugs, skips docs, and scope-creeps. This toolkit enforces a lightweight discipline — read-before-code, ADRs for decisions, gap tracking for missing features, known-issues for recurring bugs, session handoffs, and a pre-commit checklist. No frameworks. No dependencies. Just markdown + skills.

---

## Install

```bash
git clone https://github.com/<you>/claude-docs-toolkit
cd claude-docs-toolkit
./install.sh
```

That's it. Skills land in `~/.claude/skills/` and are available in every project you open with Claude Code.

To update:
```bash
cd claude-docs-toolkit
git pull
./install.sh --force
```

To uninstall:
```bash
./install.sh --uninstall
```

---

## Quick Start in a New Project

```
cd my-project
claude                        # open Claude Code
```

Then in Claude:

```
/doc-init
```

This scaffolds `docs/MASTER-INDEX.md`, `docs/DECISIONS.md`, `docs/KNOWN-ISSUES.md`, `docs/SESSIONS.md`, and either creates or appends to `CLAUDE.md`. Idempotent — safe to re-run.

From then on:

```
/before <task>      # before writing code
/ship               # before committing
```

That's the whole loop.

---

## The 10 Commands

| Command | What it does | When to use |
|---|---|---|
| `/doc-init` | Bootstrap the doc system in a fresh project | Day 1, or introducing the toolkit to an existing repo |
| `/docs [task]` | Orient Claude around your project's docs; maps task → files to read | Start of any non-trivial task |
| `/before <task>` | Enforced pre-code checklist: reads CLAUDE.md + task docs, greps prior art, checks ADRs & known issues, states a plan | Before writing code on any task bigger than a one-liner |
| `/gap [area\|close N\|new area]` | Track missing features; list / drill / close / create gap docs | When the user asks "what's missing" or you ship a tracked feature |
| `/doc-new <type> <title>` | Create a new doc with the required header + auto-register in MASTER-INDEX | Any time a new markdown file belongs in `docs/` |
| `/decision <title>\|list\|topic` | Log/retrieve ADRs in `docs/DECISIONS.md` | Every design choice with trade-offs; every library pick |
| `/ship` | Pre-commit checklist: tests, docs, ADRs, gap closures, commit message | Before every commit that touches multiple files |
| `/session [title\|last]` | Write an end-of-session handoff; or read the last one | End of a session with in-flight work; start of a new session |
| `/repeat <symptom>\|add` | Check / add entries in `docs/KNOWN-ISSUES.md` | Before debugging (check first) and after fixing non-obvious bugs |
| `/trace <symptom>` | Structured root-cause walk: reproduce → localise → identify → fix → prevent | When debugging a non-trivial bug |

---

## The Four Files the Toolkit Maintains

Once `/doc-init` runs, your project has these living docs:

| File | What it holds |
|---|---|
| `docs/MASTER-INDEX.md` | Registry of every doc, with purpose and when to read/update. Single source of truth. |
| `docs/DECISIONS.md` | ADRs — architectural decisions with context + alternatives + consequences. Newest at top. |
| `docs/KNOWN-ISSUES.md` | Non-obvious bug fixes with symptom, root cause, fix, and prevention rule. |
| `docs/SESSIONS.md` | Rolling log of end-of-session handoffs. Helps the next session pick up cleanly. |

Plus on demand:

| File | Created by |
|---|---|
| `docs/*-GAPS.md` | `/gap new <area>` |
| `docs/PROJECT-AUDIT-YYYY-MM-DD.md` | `/doc-new audit <title>` |
| `docs/plans/<feature>.md` | `/doc-new plan <feature>` |

---

## Typical Session Flow

```
/session last              # read last handoff
/docs new API route        # orient around relevant docs
/before add rate limit to /api/invite
                           # Claude states a plan, waits for your OK
<you approve, Claude codes>
/ship                      # pre-commit checks
<commit>
/session rate-limit-shipped
                           # leave a handoff for next time
```

---

## Why These Commands Exist (The Gaps They Close)

| Pain | Gap | Toolkit answer |
|---|---|---|
| Claude re-asks settled design choices | No shared memory of decisions | `/decision` logs ADRs |
| Docs lie because nobody updates them | Silent doc rot | `/ship` forces a doc-update check |
| "What's still missing?" has no answer | Untracked gaps | `/gap` with status history |
| Same bug re-introduced in different sessions | Ephemeral debugging knowledge | `/repeat` + `/trace` log prevention rules |
| Claude adds unrequested helpers/refactors | No scope discipline | `/before` + `/ship` catch unrelated changes |
| Claude dives in without reading | No pre-code checklist | `/before` is enforced |
| Commit messages don't explain *why* | No post-ship discipline | `/ship` drafts a "why" commit |
| New session has no idea what happened | No session continuity | `/session` handoff notes |
| Fresh project has nothing to start from | Bootstrap friction | `/doc-init` scaffolds everything |
| New docs get orphaned (Claude can't find them) | Unregistered files | `/doc-new` auto-registers |

---

## Design Principles

- **Markdown only.** No database, no server, no framework. If you can read the files without the tool, they still work.
- **Idempotent.** Re-running `/doc-init` never overwrites. Re-running `/ship` is always safe.
- **Never delete history.** Gaps become `shipped YYYY-MM-DD`, ADRs become `superseded`, old docs become `archive`. You can always trace why.
- **Adaptive.** `/ship` only asks about what the diff actually changed. No checklist bloat.
- **Project-agnostic.** No hardcoded paths, no language assumptions. Works in any repo.

---

## Project Structure

```
claude-docs-toolkit/
├── README.md              # this file
├── install.sh             # copies skills to ~/.claude/skills/
├── skills/
│   ├── doc-init/SKILL.md
│   ├── docs/SKILL.md
│   ├── before/SKILL.md
│   ├── gap/SKILL.md
│   ├── doc-new/SKILL.md
│   ├── decision/SKILL.md
│   ├── ship/SKILL.md
│   ├── session/SKILL.md
│   ├── repeat/SKILL.md
│   └── trace/SKILL.md
└── templates/             # reference templates (see below)
    ├── MASTER-INDEX.md
    ├── DECISIONS.md
    ├── KNOWN-ISSUES.md
    └── SESSIONS.md
```

Templates mirror what `/doc-init` creates. You can also copy them manually if you'd rather not run the skill.

---

## FAQ

**Does this replace CLAUDE.md?**
No. `/doc-init` adds a "Slash commands" block + "Doc System Rules" to an existing CLAUDE.md. Your project-specific rules stay.

**My project already has `docs/` with other files. Will this clobber them?**
No. `doc-init` never overwrites. It creates only the four files above if they're missing, and reports what it skipped.

**What if I don't use ADRs?**
Then don't use `/decision`. Every command is optional. The toolkit is lighter than any framework — use what helps.

**Does Claude automatically find these in subprojects / monorepos?**
The skills are installed globally. They read `docs/MASTER-INDEX.md` relative to the current working directory, so they work in whichever subproject you're in.

**Can I customise the templates?**
Yes — edit `templates/*.md` in the toolkit repo, then `./install.sh --force`. Or edit the files directly in your project after `doc-init` runs.

---

## Licence

CoderLap Source-Available Licence v1.0 — see [LICENCE](./LICENCE).

Free to read. Free for personal evaluation. **All other use — commercial, redistribution, hosting, incorporation, modification-then-sharing — requires written permission from Abdullah Hadi (GGAbdulalah@gmail.com).**

Docs and details: https://coderv.dev/licence
