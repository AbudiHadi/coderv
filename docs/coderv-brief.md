# CoderLap — Honest Technical Brief

> Written for an expert reviewer weighing whether to support the project.
> Sourced from the repository (`claude-docs-toolkit` @ v0.11.0), not the marketing site.
> Claims trace to `skills/*/SKILL.md` and `hooks/*.sh`; limitations trace to the
> `codex-review-gate.sh` "accepted limitations" block and each hook's fail-open handling.

## The one-paragraph verdict

An LLM coding agent is competent but undisciplined. Left alone it re-asks settled
questions, re-introduces fixed bugs, skips the docs, quietly widens scope, and grades
its own work generously. CoderLap's thesis is narrow: **you cannot fix this with better
prompts, because a prompt is advice and advice gets skipped mid-task.** So the
interesting half isn't the seven commands — it's the six **hooks**, which run in the
harness where the model can't route around them.

What makes it special is one design move applied consistently: **turn each good habit
into a mechanism the agent physically cannot skip.** "Read the docs first" becomes a
locked door. "Don't trust a degraded session's memory" becomes a snapshot that outranks
the summary. "No commit lands unreviewed" becomes a second model reading every diff.
"Never grade your own homework" becomes a computed scorecard with pasted evidence.

The honest counterweight: the gates are Claude-Code-specific, one depends on a second
vendor's CLI (OpenAI Codex), and they **fail open** — a broken gate never locks you out,
which also means it's a silent gap: the review gate warns loudly when its tools are
missing, but a gate missing `python3` simply no-ops with no warning at all. None of that
is hidden; the code documents its own limits.

---

## The seven skills

| Command | The tired moment it removes | The mechanism that makes it real |
|---|---|---|
| **`/coderv`** | "I don't want to remember which command comes next." | Classifies the request, checks project state from live commands (not memory), assembles the pipeline, drives it on one yes. Bare `/coderv` scans and proposes the next move; a vague target spawns a read-only scout first. |
| **`/docify`** | "I need real docs but won't write them." | Scans the codebase, writes CLAUDE.md + reference docs. **Every claim must cite a `file:line`** or be marked `TODO: verify`. Lands as drafts you promote — never overwrites. |
| **`/before`** | "What should I even read first?" | Reads docs, greps prior art, states a plan, **waits for approval.** Writes a grounding *receipt* + a checkable *spec* to disk — both become ground truth for later reviewers. Auto-skips trivial edits. |
| **`/decision`** | "Write down why, so I never re-explain it." | Logs an ADR — context, alternatives, trade-off, decider — at the top of a never-deleted log. Supersede, don't erase. |
| **`/ship`** | "Did I miss a doc? And is it really done?" | Auto-updates api/components/database docs, validates every citation, spawns a **fresh-context reviewer** that audits the diff against the spec, prints a **computed scorecard** (gates passed/total with pasted evidence). You approve at 100%. |
| **`/session`** | "Pick up where I left off." | Writes a handoff whose state claims are **pasted command output, not prose**. Rotates old entries to an archive so the live file stays cheap. |
| **`/lint`** | "Can I still trust these docs?" | Audits docs for contradictions, stale claims, dead references. **Every finding is machine-verified** — a quote that fails a literal `sed` string-match is dropped, not reported. |

### The daily loop

```
/docify                # once per project → CLAUDE.md + 6 cited reference docs

# every task after that — /coderv drives it:
/session last          # what was I doing?
/lint                  # only when docs are stale
/before <task>         # ◆ you approve the plan
<code>                 # hooks guard grounding + context silently
verify                 # drive the flow, observe it works
/ship                  # ◆ you approve at 100%
/session               # handoff, state as pasted evidence
```

You're stopped only at the two `◆` points, where human judgment is genuinely required.

### The architecture audit (new in v0.11.0)

Ask `/coderv` for an architecture review and it runs a *shape*, not an eighth command
(the surface a human memorizes stays at seven — a deliberate cap). The pipeline: a
read-only scout, then seven parallel review dimensions (layering, coupling, duplication,
module boundaries, dead code, integration wiring, service liveness), then **every finding
is adversarially verified by the second model** before it reaches the scored P0–P3 report
(when that model is unavailable, findings ship explicitly marked "unverified" — never
silently promoted).
Reports are timestamped, stamped with the exact commit they audited, and never
overwritten; findings have a lifecycle (open → fixed / withdrawn / superseded, closed only
on evidence) and open P0/P1s follow you through the other commands — `/ship` warns when a
diff touches a hot-spot file, `/session` carries them into the handoff, `/before` reads
the newest report as prior art. Where the server registry or process list isn't available,
the wiring/liveness dimensions report "NOT checked" instead of faking coverage. The audit
advises; it never auto-fixes.

---

## The six hooks

This is the differentiator. A skill description is a guideline the model can miss under
load; a hook runs in the harness and **can't be forgotten.** Two nudge; four are gates.
The four gates share one kill switch (`CODERV_GATES_OFF=1`) and all six fail open.

| Hook | Event | Kind | What it does |
|---|---|---|---|
| **coderv-router** | UserPromptSubmit | nudge | Scans every message for *intent* (not just literal phrases), injects a one-line reminder so Claude offers the right command. HIGH/LOW confidence tiers; negative patterns suppress look-alikes. |
| **project-context** | SessionStart | nudge | Injects a live map of the 10 most recently active projects (newest handoff first) with a standing rule to read the real docs first. Reads actual files at start time — can't go stale. |
| **grounding-gate** | PreToolUse | **GATE** | Blocks the session's **first code edit** in a documented project until a receipt proves `/before` read the docs (or a conscious skip). Door locked, not advised. Never gates doc edits / `~/.claude` / temp. |
| **codex-review-gate** | PreToolUse/Bash | **GATE** | Before any commit-creating git command, the outgoing diff goes to a **second model** (Codex CLI) for adversarial review; hunts for *drift* from a fresh approved plan. Findings block **once**; rejected findings must be surfaced. |
| **compact-rehydrate** | SessionStart/compact | **GATE** | Fires only after compaction — the #1 source of state hallucination. Injects a live git snapshot: **when the summary and snapshot conflict, the snapshot wins.** |
| **context-gate** | Stop | **GATE** | Warns, then hard-stops new work at an **absolute** context budget (~180k tokens), not a fraction of the window. The "dumb zone" is an absolute floor. At the limit, the only sanctioned move is writing a handoff. |

---

## The idea underneath

A few sharp ideas applied with unusual consistency across all 14 files.

**Evidence over recollection.** A degraded or compacted session misremembers; it can't
mis-paste. Every state claim is required to be command output — handoffs paste the
`git log` line, the scorecard shows the build's last line, reviewer quotes are re-checked
with `sed` and dropped if they don't literally match.

**A second, independent judgment.** The session that wrote the code can't grade it fairly.
So the plan is peer-reviewed before you see it, the diff is reviewed again at commit, and
`/ship`'s scorecard runs in a fresh context against the written spec. Disagreement is
bounded on purpose: one rebuttal round, escalate to the human when the same finding
bounces twice on the same rationale — the loop is engineered to *terminate*, not to win.

**The human sits above both models.** Every gate surfaces its findings — including
rejected ones — and the human is the final authority. The machinery narrows judgment to
two moments and defends them, rather than removing the human from the loop.

---

## The honest ledger

Every limitation below is documented in the toolkit's own source. That the project writes
down its own gaps is the strongest signal in this brief.

### Genuine strengths

- **Zero runtime dependency.** Markdown + bash. If the toolkit vanished tomorrow, the files still tell you what's going on.
- **Gates run in the harness** — enforcement the model can't route around, qualitatively different from prompt-pack "guidance".
- **Machine-verified honesty.** Findings, citations, and state claims are checked against reality with real commands, not asserted.
- **Idempotent and non-destructive.** Every command is safe to re-run; history files are append-only, superseded, never deleted. (Working files like the per-task spec are deliberately replaced each task.)
- **It documents its own limits.**

### Real limitations

- **Gates are Claude-Code-only.** On Codex / Gemini you get the skills but none of the six hooks — the enforcement half is gone.
- **Fail-open is a double edge.** A broken gate never locks you out — and the gap can be truly silent: only the review gate warns about missing tools; the python3-dependent gates no-op without a word.
- **Second-vendor coupling.** The review gate needs OpenAI's Codex CLI and sends your diff to it — a real dependency and a data-egress fact.
- **PreToolUse can't see the future.** A command that generates files *then* commits reviews the pre-command tree; merges/rebases integrate commits the gate can't see (it warns loudly).
- **Discipline still needs a driver.** Skills are offered, not forced; the human must approve the plan and the scorecard for the loop to mean anything.
