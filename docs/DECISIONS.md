# Decision Log (ADRs)

> Toolkit-level architectural choices. Run `/decision <title>` to add a new ADR.
> Newest at top. **Never delete.**

---

## Template

```
## ADR-NNN: <Short title>

**Date:** YYYY-MM-DD
**Status:** accepted | superseded by ADR-MMM | deprecated
**Decider(s):** <name(s)>

### Context
What is the problem? What forces are at play?

### Decision
What did we decide?

### Alternatives considered
- **Option A** (chosen) — why
- **Option B** — why not
- **Option C** — why not

### Consequences
- Positive: …
- Negative / trade-off: …
- Revisit if: …
```

---

## ADR-004: Verification of model claims is a toolkit-wide principle, not a `/session` patch

**Date:** 2026-04-25
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-001 fixed a symptom: `/session` trusted a compacted summary that lied about shipping. ADR-003 broadened *how* `/session` verifies. But the underlying disease is bigger: **every skill in the toolkit consumes prompt context and writes durable artefacts based on it.** Each one has the same failure mode `/session` just exhibited.

- `/ship` reads "what changed" from the diff — but its commit message is drafted from the model's *narrative* of what changed, which a compaction can corrupt the same way.
- `/decision` writes ADRs from conversation context. If the model misremembers an alternative we considered, the ADR records a fiction as history. (Ironically, this very ADR is vulnerable.)
- `/docify` is the cleanest of the five — it cites source files and re-validates citations. That's the *correct* pattern. The other skills should match it.
- `/before` reads "prior art" from grep + memory; less exposed because it acts before the work, not after.

Treating verification as a `/session`-only feature leaves four of the five skills vulnerable to the same class of failure that motivated ADR-001 in the first place.

### Decision
**Establish a toolkit-wide verification principle and apply it to all five skills.**

The principle: **every durable artefact a skill writes (handoff, ADR, commit message, doc) must cite a verifiable source — a file, a commit, a diff, a directory listing — not a model recollection.** When prompt context conflicts with verifiable source, the source wins, and the conflict is recorded in the artefact.

Concrete application per skill:
- **`/session`** — verifies as per ADR-001 + ADR-003 (git or filesystem snapshot). Already covered.
- **`/ship`** — must re-read the actual `git diff` (not the model's description of it) before drafting the commit message. Citation validation already happens here for docs; extend to "the commit message's claims must match the diff."
- **`/decision`** — when an ADR cites a "prior conversation" or "we discussed", the skill should require the user to confirm or reject the recollection inline. The ADR records confirmed facts only. Unverified recollections get marked `(unverified — model recollection)`.
- **`/docify`** — already correct. Codify it as the design precedent in the toolkit's docs.
- **`/before`** — must run actual `grep` / `git log` searches for prior art, not summarise from memory. If the model says "I think we did this in `auth.ts`," the skill must `grep` `auth.ts` before stating it as fact.

### Alternatives considered
- **Toolkit-wide principle, applied per-skill** (chosen) — closes the failure mode at its actual scope. Matches the existing `/docify` pattern (which already works). Adds a unifying principle to the toolkit's design docs that future skills inherit by default.
- **Patch each skill ad-hoc as failures arise** — the path of least resistance, but it means every skill has its own failure-then-fix cycle. We just lived through one; no need to schedule four more.
- **Add a sixth "verify" skill that other skills call** — violates ADR-002 (keep the surface at 5). Verification is a *cross-cutting concern*, not a user-facing command. It belongs inside the existing five, not beside them.
- **Trust the model and accept occasional drift** — the toolkit's whole pitch is *discipline for AI-assisted dev*. Accepting that the discipline tools themselves drift is incoherent.

### Consequences
- Positive: One principle, applied five places, closes a class of bugs instead of one instance. Aligns the toolkit's internals with the citation-grounded story `/docify` already tells externally. Future skills (if any) inherit the principle by default.
- Positive: Gives the toolkit a real architectural identity — *"every claim is sourced"* — that differentiates it from prompt-template libraries that just chain LLM calls.
- Negative / trade-off: Each skill's prompt grows in size and tool-call count. Slower runs. More visible tool noise to the user. Mitigation: keep verification commands minimal and structured; don't dump verbose output back to the user unless there's a contradiction worth flagging.
- Negative / trade-off: This ADR is itself unverified (it summarises today's session from memory). The first thing the new principle would catch is *its own creation*. That's noted, not paralysing — ADRs document intent; the implementation is what enforces the principle going forward.
- Revisit if: Implementation reveals that one or more skills genuinely don't have a verifiable source for some claim. At that point, mark the unverifiable claim explicitly rather than dropping the principle.

### Related
- ADR-001 (the original failure that exposed this)
- ADR-002 (keeps the surface at 5; this ADR explains how to make those 5 trustworthy without adding a 6th)
- ADR-003 (the verification *mechanics* — this ADR is the *principle* those mechanics implement)
- `/docify`'s existing citation model — the precedent this principle generalises from.

---

## ADR-003: Verification mechanics — no-git fallback, session-anchored windows, multi-repo, and uncommitted state

**Date:** 2026-04-25
**Status:** accepted (extends ADR-001)
**Decider(s):** Hadi (CoderLap author), Claude

### Context
ADR-001 said "verify ship claims from git." Pressure-tested, that decision has four real gaps:

1. **No-git environments.** Solo writers, fresh folders, kiosks, locked-down corporate machines. CoderLap's pitch is *low-friction discipline*; failing on day one for anyone without `git init` undermines that.
2. **Time-window staleness.** The skill template uses `git log --since="6 hours ago"`. After a weekend, holiday, or sick day, that window is empty and `/session` reports "nothing shipped" while Friday's commits sit just outside the window.
3. **Uncommitted-but-real work.** Most days, the most useful handoff is *"I have changes staged but not committed; here's what's in flight."* Pure commit verification flags this as "nothing shipped" — technically true, practically wrong.
4. **Multi-repo sessions.** Today's session edited two repos in lockstep (toolkit + website). `/session` runs in one cwd; the other repo is invisible. The compaction-lied incident is a direct consequence of this — half the state was unwatched.
5. **Branches.** Work committed on a feature branch is invisible to `git log` on `main`. Same family of issue as #4.

Issue #6 (locale/timezone for "6 hours ago" interpretation) collapses into #2 once we anchor windows to the previous session's timestamp instead of wall-clock.

### Decision
**Two-tier verification, anchored to the previous session, covering staged + unstaged + committed state across all repos the user declares relevant.**

**Tier 1 — git available:**
- Window: `git log --since="<timestamp of previous SESSIONS.md entry>"`. Falls back to "24 hours" only on a fresh `SESSIONS.md`.
- Capture three states explicitly: `git diff --stat` (unstaged), `git diff --cached --stat` (staged), `git log --oneline <since-anchor>..HEAD` (committed). Each appears in the handoff with its own label, never collapsed into "what shipped."
- Branch awareness: include `git branch --show-current` and `git log --all --since=<anchor>` so work on feature branches is visible.
- Multi-repo: the user can declare related repos via a `coderlap.repos` list in `CLAUDE.md` frontmatter or a top-level `.coderlap/repos.txt`. `/session` walks each. A repo not declared is not verified — by design, to avoid surprise filesystem traversal.

**Tier 2 — no git:**
- Snapshot file: `/session` writes `.coderlap/last-session.json` at end of every run. Captures `{path, mtime, size, sha256}` for every file in the project (excluding `.gitignore`-equivalent patterns: `node_modules/`, `dist/`, `.env*`).
- Next session: diff current filesystem against the snapshot. New files, modified files, deleted files all surface. Handoff says "filesystem-verified (no git)" so the user knows verification was best-effort.
- Snapshot file is `.gitignore`-d. It's per-machine state, not project state.

**Both tiers:**
- If prompt context claims something happened that verification contradicts, the handoff records the contradiction explicitly: *"Note: prior conversation claimed X shipped; verification shows Y."* Never silently overwrite either source.
- If neither tier is available (no git, no write access for snapshot), `/session` writes the handoff with a top banner: *"⚠ Unverified — no verification mechanism available. Treat 'what shipped' as model recollection."* Better honest-and-flagged than confidently-wrong.

### Alternatives considered
- **Two-tier, session-anchored, multi-state, multi-repo** (chosen) — closes all four scoping gaps in one decision. Tier 2 makes CoderLap usable for non-developers without forcing git on them. Snapshot diffing is well-understood (rsync, restic, etc., do the same).
- **Require git, hard fail otherwise** — simpler but excludes a real audience (writers, students, kiosks). Contradicts the toolkit's "low-friction" positioning.
- **Pure mtime-based fallback (no snapshot file)** — can't detect deletions, can't detect content changes that preserve mtime, and resets across machine reboots in some filesystems. Snapshot file is a small price for correctness.
- **Auto-discover all git repos under cwd recursively** — too invasive; surprises the user when `/session` reports on a vendored submodule or a node_modules `.git` folder. Explicit declaration is the right tradeoff.
- **Wall-clock window ("last 6 / 24 hours")** — fails after weekends as documented. Session-anchoring is more work but matches actual user behaviour (work happens between sessions, not between hours).
- **Treat staged and unstaged as one bucket** — loses the "in flight vs. committed" distinction that's the whole point of a handoff.

### Consequences
- Positive: `/session` works for non-developers (Tier 2). Works after weekends (session-anchoring). Captures in-flight work (staged/unstaged tracked separately). Handles multi-repo workflows the toolkit author actually uses (ADR-001 was *itself* discovered via a multi-repo failure).
- Positive: Honest about its limits. The "⚠ Unverified" banner is a feature, not a failure — better than the current implicit-trust-in-model failure mode.
- Negative / trade-off: Two code paths in `skills/session/SKILL.md`. Snapshot file is yet another piece of per-machine state to maintain. Multi-repo declaration adds a config surface (`.coderlap/repos.txt` or CLAUDE.md frontmatter) — the toolkit's first piece of declarative configuration.
- Negative / trade-off: Snapshot diffing on large projects is slow. Mitigation: cap at ~10k files; skip directories matching common ignore patterns; offer an opt-out.
- Negative / trade-off: ADR-002 said "keep surface at 5." This ADR doesn't add a skill, but it does grow `/session`'s prompt and tool-call count significantly. Watch for the skill becoming unwieldy.
- Revisit if: A meaningful number of users hit the "no verification mechanism available" branch — that signals the tiers don't cover real workflows. Or if Claude Code adds a native filesystem-state primitive that obviates the snapshot file.

### Related
- ADR-001 (this extends it; ADR-001's git assumption is now Tier 1)
- ADR-002 (this respects "5 commands stable" by enriching `/session` rather than adding a new skill)
- ADR-004 (the *principle* this ADR's mechanics implement — verification is toolkit-wide)
- `/docify`'s citation-validation model is the design precedent for "verify against source, flag contradictions."

---

## ADR-002: Curate the skill surface — CoderLap's 5 must stay legible amid third-party skills

**Date:** 2026-04-25
**Status:** accepted
**Decider(s):** Hadi (CoderLap author), Claude

### Context
The user's environment now exposes ~50 skills: CoderLap's 5 (`/before`, `/docify`, `/decision`, `/ship`, `/session`) plus the impeccable design suite (`/critique`, `/distill`, `/audit`, `/polish`, etc.) plus framework-level skills (`/init`, `/review`, `/security-review`). Worse, the impeccable skills appear *twice* — once unprefixed (`/critique`) and once namespaced (`/impeccable:critique`) — every shared name resolves to two near-identical entries.

A new CoderLap user reading the skill picker can't tell which 5 commands *are* CoderLap. The discipline loop is the product; if it's lost in the noise, the product is lost in the noise. This is the same anti-pattern the licence page has (11 identical bricks problem) — too many same-shape items dilute the few that matter.

### Decision
1. **Treat the CoderLap 5 as a curated set with shared visual/textual identity.** Every CoderLap skill description starts with the same opening sentence pattern ("Pre-code checklist...", "Pre-commit checklist...", "Session handoff..."). Add a consistent prefix or visual marker to make them scannable as a set in the skill picker.
2. **Document the duplication, do not try to fix it.** The `impeccable:*` namespace duplication is upstream (impeccable's distribution choice), not ours. Add a one-line note to `README.md` so users aren't confused: "CoderLap ships 5 skills. Other skills you see (`/critique`, `/audit`, etc.) come from other plugins like impeccable — not us."
3. **Resist the urge to add more skills.** Per CLAUDE.md "Never add unrequested scope" — new behaviour goes into the existing 5 (smarter TRIGGER phrases, richer step lists) before it justifies a 6th command.

### Alternatives considered
- **Curate identity + document boundary** (chosen) — keeps the 5 legible without fighting upstream namespace decisions; honours the existing "stable surface area" rule in CLAUDE.md.
- **Add a `coderlap:` namespace prefix to all 5 skills** — would solve scannability, but breaks every existing user's muscle memory (`/before` → `/coderlap:before`) and every doc/screenshot in circulation. Cost > benefit at current adoption.
- **Build a `/coderlap` meta-skill that runs the 5 in sequence** — adds a 6th skill to the surface area we just said we'd keep stable. Solves nothing — users still need to know the 5 individually for the loop to work.
- **Ignore it** — accepts ongoing user confusion; the discipline loop's discoverability degrades as more third-party skills enter the picker.

### Consequences
- Positive: New users can identify the CoderLap set at a glance; the 5-skill scope stays defended against feature creep; no breaking change to existing users.
- Negative / trade-off: Requires a small editing pass across all 5 skill descriptions to enforce shared opening patterns. Doesn't *solve* the namespace duplication — only documents it.
- Revisit if: Claude Code adds a native skill-grouping or plugin-bundle mechanism that lets us declare the 5 as a coherent set without touching individual descriptions.

### Related
- ADR-001 (verification in `/session` — same theme: making the discipline loop trustworthy)
- ADR-004 (the verification principle that ADR-001 generalises into)
- CLAUDE.md rule: "Keep the 5-command surface area stable"

---

## ADR-001: `/session` must verify ship claims from git, not from prompt context

**Date:** 2026-04-25
**Status:** accepted (extended by ADR-003 and generalised by ADR-004)
**Decider(s):** Hadi (CoderLap author), Claude

### Context
Today's session hit a real failure. A compacted conversation summary asserted that v0.3.9 was "fully committed, bumped, tagged, pushed, GitHub release created" — and the prior `/session` handoff faithfully captured that claim. None of it was true. `git status` showed both repos with `CLAUDE.md` + `docs/` still untracked. `cat VERSION` still read `0.3.8`. No tag existed. No release existed.

The failure mode: Claude's compaction summarised *intent* as if it were *state*. `/session` then transcribed that intent into the handoff. A future session reading "shipped" would have skipped the actual ship steps, leaving the project in a broken half-state.

This is not a model bug — it's a design gap in `/session`. The skill writes whatever the conversation context contains. If context is wrong, the handoff is wrong. The user's whole thesis ("discipline for AI-assisted dev") collapses if the discipline tool itself can't be trusted.

### Decision
`/session` must run verification commands and source ground-truth facts from them — not from prompt context — for the "What shipped" section. Specifically:

1. Before writing the handoff, run: `git status -s`, `git log --since="6 hours ago" --oneline`, and (if a `VERSION` file exists) `cat VERSION` plus a grep for the version string in the relevant config/package files.
2. The "What shipped" bullets must reference *commit hashes* or *tracked file paths* — not prose like "fully committed". If a file is untracked, that fact appears in the handoff, not its absence.
3. If the conversation context claims something shipped that the verification commands contradict, `/session` flags the contradiction in the handoff itself ("Note: prior summary said X shipped; git shows it didn't"). It does not silently trust either source.

> **Note (added 2026-04-25):** ADR-003 extends this with a no-git fallback, session-anchored time windows, multi-repo support, and explicit handling of staged/unstaged state. ADR-004 generalises the underlying principle ("verify against source, not recollection") to all five skills. ADR-001 is the original, narrow scoping; refer to ADR-003 + ADR-004 for the current implementation contract.

### Alternatives considered
- **Verify from git, flag contradictions** (chosen) — matches the citation-grounded philosophy of `/docify`. Same principle: doc claims must be backed by source artefacts, not by model confidence.
- **Trust prompt context, ask the user to confirm** — adds friction to every `/session` invocation; users skip prompts; same failure mode survives.
- **Verify silently and overwrite contradictions** — loses the audit trail. The contradiction itself is valuable signal — future sessions should see that a prior summary lied, so they learn to verify too.
- **Do nothing; document the failure mode in CLAUDE.md** — passes responsibility to the user. The whole point of skills is that the user *doesn't* have to remember the discipline.

### Consequences
- Positive: Handoffs become trustworthy artefacts. Failure mode that just happened cannot recur silently. Reinforces the "verify from source, not from confidence" principle that already underpins `/docify`.
- Negative / trade-off: `/session` becomes slightly slower (3-4 extra commands per invocation). Skill prompt grows more complex. Extra tool calls visible to the user.
- Revisit if: A lighter-weight verification mechanism appears (e.g. Claude Code exposes git state to skills natively without explicit shell calls).

### Related
- ADR-002 (skill curation — same theme of making the discipline loop reliable)
- ADR-003 (extends this with no-git fallback and the four scoping gaps)
- ADR-004 (generalises the principle behind this decision to all five skills)
- KI-NNN: log the original incident as a Known Issue once the fix lands.
- The `/docify` citation model is the design precedent for this — every doc claim cites a source line; every handoff claim should cite a git fact.

---

<!-- New ADRs above this line, newest first -->
