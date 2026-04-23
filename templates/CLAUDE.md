# Project AI Instructions

> This file tells Claude how to work in this project. It's loaded automatically every session.

## The loop (every task)

1. Start of session: **`/session last`** — read the last handoff.
2. Before coding: **`/before <task>`** — Claude reads the relevant docs, plans, waits for approval.
3. When you make a design choice: **`/decision <title>`** — log it while it's fresh.
4. Before committing: **`/ship`** — checks docs got updated, drafts a commit message.
5. End of session: **`/session`** — write a handoff for next time.

## The four living files in `docs/`

| File | What it holds |
|---|---|
| `docs/DECISIONS.md` | ADRs — why we chose X over Y. Newest at top. Never delete. |
| `docs/KNOWN-ISSUES.md` | Recurring bugs: symptom, root cause, fix, prevention rule. |
| `docs/SESSIONS.md` | End-of-session handoffs. Newest at top. |
| `docs/<AREA>-GAPS.md` (optional) | Missing features per domain. Closed gaps become `shipped YYYY-MM-DD (commit: <hash>)`. |

## Code principles

- **SR** (Single Responsibility) — one thing per function / component.
- **DRY** — shared services, not copy-paste.
- **CC** (Component Composition) — small composable pieces.
- **SoC** (Separation of Concerns) — routes → services → DB.

## Rules Claude follows

1. **Read before code.** `/before` enforces this. Don't skip docs on non-trivial tasks.
2. **Never add features, helpers, or refactors the user didn't ask for.** Even if you see something you'd do differently.
3. **Never delete history.** Closed gaps become `shipped YYYY-MM-DD`. Superseded ADRs keep their section. Archived docs get a banner, not a deletion.
4. **Log design choices as ADRs.** Via `/decision`. Don't re-litigate next session.
5. **When a non-obvious bug is fixed** (>15 min to root-cause), add an entry to `docs/KNOWN-ISSUES.md` with a **prevention rule** (a test, type, lint rule, or review checklist item that would catch it next time).
6. **Absolute dates only.** Write `2026-05-01`, never "next Thursday". Records outlive the session.
7. **Commit messages explain *why*, not just *what*.** `/ship` drafts one. Don't add AI attribution unless the project already uses it.
8. **At project boundaries (user input, external APIs, env vars) validate.** Inside the project, trust your own types.

## Never

- Skip `/before` on a task with multiple files or a new module.
- Commit without running `/ship`.
- Delete an ADR or a gap entry — update its status instead.
- Write code when the user said "plan first".

## Always

- Update the doc that describes the code you changed, in the same commit.
- Put new decisions in `DECISIONS.md` immediately, while they're fresh.
- Write a `/session` note if you leave work in flight.
