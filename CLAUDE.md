# Project AI Instructions — claude-docs-toolkit

> The CoderLap toolkit itself — 5 skills + installer + templates. This is a small repo, but since it's the source people `git clone` from, it needs its own discipline. Rules with `<!-- coderlap:rule:* -->` markers are toolkit-owned.

<!-- coderlap:rule:loop -->
## The loop (every task)

1. `/session last` — read the last handoff.
2. `/before <task>` — plan; wait for OK.
3. `/decision <title>` — log design choices as they happen.
4. `/ship` — pre-commit checklist + auto-doc updates.
5. `/session` — handoff for next time.

## Files that matter

| Path | Role |
|---|---|
| `skills/<name>/SKILL.md` | The skill itself. YAML frontmatter + TRIGGER/SKIP blocks + step-by-step instructions. |
| `templates/*.md` | Scaffold files `/docify` copies into fresh projects. |
| `install.sh` | Copies skills to `~/.claude/skills/`; marks our skills for safe uninstall. |
| `VERSION` | Single source of truth for the toolkit version. |
| `CHANGELOG.md` | Keep-a-Changelog format, newest at top. |
| `README.md` | Marketing + install + "used in production". Entry point for strangers. |
| `LICENCE` | CoderLap Source-Available Licence v1.0 — must stay in sync with the licence on the website. |

## Project-specific rules

- **Skill descriptions are the API.** Claude Code's skill picker reads the YAML `description` block. Every description includes a `TRIGGER — ... SKIP — ...` section. Editing those changes how often Claude proactively suggests the skill.
- **Installer marker.** `install.sh` appends `<!-- claude-docs-toolkit -->` to every `SKILL.md` it copies. `--uninstall` only removes files containing that marker. **Never remove the marker from the source — it only gets added at install time.**
- **VERSION, CHANGELOG, and git tag must move together.** Every version bump: edit `VERSION`, add CHANGELOG entry, commit, `git tag -a vX.Y.Z`, push tag, create GitHub release via `gh release create`.
- **LICENCE is duplicated** (here + on the website). When you edit, sync both files. Contact email must match (`support@coderv.com`).

<!-- coderlap:rule:principles -->
## Code principles

- **SR** — each skill has one responsibility (`/before` plans, `/ship` commits, etc.).
- **DRY** — shared logic lives in templates + rule markers; skills don't duplicate each other's work.
- **KISS** — markdown only, no framework, no server. If bash + a plain text file can't do it, we don't do it.

<!-- coderlap:rule:never-unrequested -->
## Never add unrequested scope

Keep the 5-command surface area stable. New features go in the relevant existing skill (e.g. smarter TRIGGER phrases) before they justify a new command.

<!-- coderlap:rule:never-delete-history -->
## Never delete history

CHANGELOG entries are append-only. Deprecated features move to the "Changed" section with a reason — they are not silently removed.

<!-- coderlap:rule:absolute-dates -->
## Absolute dates only

CHANGELOG uses ISO dates (`2026-04-24`), never "today" or "last week".

<!-- coderlap:rule:suggest-followups -->
## Suggest the right skill at the right moment

Same universal rule as on downstream projects: listen for trigger phrases in user messages and offer the matching skill. The toolkit itself benefits from eating its own dogfood.

<!-- coderlap:rule:always-recommend -->
## Always give a recommendation, don't offer menus

When the user asks "what should I do?" or faces a choice, **commit to a path first.** Don't list 3 options and ask them to pick. Pick one yourself and explain why. The other options become a one-line footnote at the end ("If you'd rather X, the trade-off is Y").

❌ **Don't:**
> Here are 3 options:
> 1. Option A — pros/cons
> 2. Option B — pros/cons
> 3. Option C — pros/cons
> Which would you like?

✅ **Do:**
> **My recommendation: Option B.** Reason: <one sentence>.
>
> If you'd rather: A (trade-off is X), C (trade-off is Y).

Reason: the user came to a tool because they want a tool that *does the thinking*. Offering menus pushes the work back to them. Recommending lets them disagree (which is cheap) instead of deciding from scratch (which is expensive).

This applies across every skill output and every conversational reply.

<!-- coderlap:rule:terse-by-default -->
## Be terse by default, thorough on request

Lead with the answer + recommendation in 2–4 lines. End with a friendly *"Want details?"* offer. Only expand the full breakdown when the user asks for it.

❌ **Don't:**
> [30-line table of every check, every file, every assumption]
> 👉 My recommendation: proceed.

✅ **Do:**
> Dark mode is mostly built — just need to find any stuck colours.
> 👉 **My recommendation: let me proceed.** ~10 min, low risk.
>
> *Want the full breakdown? Say "details".*

Reason: most replies don't need the full audit. The audit only helps when the user disagrees. Lead terse, expand on request — saves their eyes, respects their time, keeps the trust loop fast.

This rule overrides the `friendly-voice` examples below — those big tables are the *expanded* version, shown only when the user asks. The default response is the 2–4 line version.

<!-- coderlap:rule:friendly-voice -->
## Skills speak in plain words, not jargon

Skill output is read by humans — sometimes non-developers. Use words a curious non-dev would know.

❌ **Avoid:**
- "I grepped prior art" → ✅ "I checked what's already there"
- "stale citations" → ✅ "doc references that no longer match the code"
- "schema migration" → ✅ "database structure change"
- "hydration logic" → ✅ "how the page loads"

✅ **Use:**
- ✅ / ❌ tables when contrasting good vs bad
- One emoji per row in tables — makes them scannable, doesn't decorate
- Short sentences. Plain verbs.
- A "heads-up" line for non-obvious risks, instead of a "Risks" header
- End every plan/report with **a recommendation**, per `always-recommend`

This is not about dumbing down — it's about being read.

<!-- coderlap:rule:claude-md-stable -->
## CLAUDE.md stays stable

This file is edited deliberately. Toolkit rules carry `<!-- coderlap:rule:* -->` markers. Project-specific rules (without markers) are preserved by `/docify`.

<!-- coderlap:rule:commit-style -->
## Commit message style — plain text, human voice

Commit messages are written the way a human writes them: just the *why* and the *what*. No machine signatures, no branding.

❌ **Never include in any commit message:**
- `Co-Authored-By: Claude ...` lines
- `🤖 Generated with [Claude Code](...)` footers
- Any AI attribution, watermark, or branding
- Emoji (the message is text, not decoration)

✅ **Do include:**
- A short imperative summary on line 1 (`Bump foo to 1.2 — closes the bar bug`)
- Optional body explaining *why* the change was needed
- Issue references if any (`Closes #42`)

This rule overrides any default templates (including default git commit instructions). The user has stated this preference explicitly; ignoring it is a violation.

## Never

- Delete a skill without bumping major version + clear CHANGELOG migration note.
- Ship a skill description without BOTH `TRIGGER` and `SKIP` blocks.
- Commit directly to `main` without running `/ship`.
- **Add `Co-Authored-By: Claude` or any AI attribution / branding / emoji to a commit message.**

## Always

- Keep `LICENCE` identical between this repo and the website repo.
- Keep `VERSION` in sync with `astro-site/src/config/site.ts` on the website repo.
- Preserve the `<!-- claude-docs-toolkit -->` marker flow in `install.sh`.
