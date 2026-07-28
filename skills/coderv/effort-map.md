<!-- coderlap:runbook:effort-map -->
# Effort map — run-book

> Driven by `/coderv` when the request is the **🗺 Big effort** shape (see
> `SKILL.md` Step 1): an idea too big for one session, wrapped in fog — the way
> to the destination isn't visible yet. This file is the *how*; `/coderv` stays
> the router (SR). Adapted from mattpocock/skills `wayfinder` (MIT) using local
> markdown instead of an issue tracker — see ADR-026.

**What this is:** planning, not doing. The map charts the *decisions* standing
between here and the destination, then resolves them one at a time. When
nothing is left to decide, the map is done and the work hands off to the normal
pipeline (`/before → work → verify → /ship`), slice by slice. The pull to "just
start building" mid-map is usually the signal the map is complete.

## The map file

One file per effort: `docs/PLAN-<topic>.md`. It is an **index, never a store**:
decisions live in `docs/DECISIONS.md` as ADRs — the map only links them. (Two
homes for one decision is the contradiction `/lint` exists to flag.)

```markdown
# Effort map — <topic>
Status: active            <!-- or: Status: done YYYY-MM-DD -->

## Destination
<what "done deciding" looks like — a spec, a locked decision set, a migration
plan. One or two lines; every session orients to this before picking a question.>

## Decisions so far
<!-- LINKS ONLY — one line per resolved question: [ADR-NNN: title](DECISIONS.md).
     The ADR title is the whole entry — no gist, no summary: DECISIONS.md is
     the single owner of decision content. -->

## Open questions
<!-- the frontier: decision tickets, sharpest first. A question belongs here
     only when it can be stated precisely — even if it can't be answered yet.
     Mark blockers inline: "(blocked by Q2)" -->
1. <question — what must be decided, and what the decision unblocks>

## Not yet specified
<!-- the fog: decisions you sense coming but can't phrase sharply yet.
     Coarser than a ticket — one patch may become several questions, or none. -->

## Out of scope
<!-- consciously ruled out of THIS effort. Never graduates; returns only if
     the destination is redrawn. One line each: what + why out. -->
```

**Lifecycle (deterministic):**
- **Created** `Status: active` by chart mode.
- **Done** when Open questions is empty and the fog has nothing left to
  graduate: flip to `Status: done YYYY-MM-DD` (never delete — it's history),
  add a closing line to `docs/SESSIONS.md`.
- **Selection rule** (used by `/before`, `/session`, and this run-book):
  `grep -l '^Status: active' docs/PLAN-*.md` — zero hits: no map behaviour;
  one: that IS the active map; several: list them and ask which — never guess.
  (Ask-which applies when *selecting one map to work on*; `/session` is a
  recorder, not a selector — its handoff lists every active frontier, because
  dropping one would lose state.)

## Chart mode (create the map)

Triggered by a loose big idea ("I want a career hub", "migrate the old data").

1. **Name the destination first** — grill the user (one question at a time,
   recommended answer with each) until the destination is one or two crisp
   lines. The destination fixes the scope; everything else hangs on it.
   (Charting is interactive by nature — this grilling is part of the 🗺 shape
   itself, not `/before`'s opt-in Step 4.5, so no separate offer is needed.)
2. **Fan out breadth-first** — surface the open decisions across the whole
   space, not deep on one thread. Sharp questions → **Open questions**; dim
   shapes → **Not yet specified**; conscious exclusions → **Out of scope**.
3. **If the whole decision set fits one sitting** — a couple of sharp
   questions, no fog: skip the map entirely and run the normal `/before`
   pipeline. But many open questions is still a multi-session effort even
   with zero fog (one question per session is the default pace) — map it. A
   map is overhead only when nothing is unknown *and* it fits one session.
4. Write `docs/PLAN-<topic>.md` (`Status: active`), show it, stop. Charting is
   one session's work; it resolves nothing.

## Work-through mode (resolve the next question)

Triggered by "continue the <topic> map" — or proposed by bare `coderv` when an
active map exists and nothing else is pending.

1. Load the map. Pick the first unblocked open question (or the one the user
   named).
2. Resolve it the cheapest honest way: **facts** are looked up (code, docs,
   recon — never asked); **decisions** are the user's — grill one question at
   a time with a recommendation; a question that needs something concrete to
   react to gets a throwaway prototype (per `/before`'s prototype rules).
3. Record: the decision becomes an ADR via `/decision`; the map's *Decisions
   so far* gets the link (title only — content lives in the ADR); the question
   leaves *Open questions*.
4. Graduate the fog the answer sharpened (fog line → new open question), drop
   questions the answer invalidated, move anything now beyond the destination
   to *Out of scope*.
5. **One question per session by default** — depth over churn; the user may
   ask for more. If *Open questions* just emptied but fog remains, the fog IS
   the frontier now: sharpen each remaining fog line into an open question
   (with the user if needed), or move what can't be sharpened to *Out of
   scope* with why — a map is never left `active` with an empty question list
   (nothing would ever route back to it). Only when the fog is empty too, run
   the Done lifecycle and say what the handoff is: the destination artifact,
   ready for `/before`.

## How the other commands see the map

- **`/before`** — reads the active map as prior art when the task touches its
  topic; a task that contradicts a mapped decision is a heads-up row.
- **`/session`** — the handoff names the active map, its next unblocked
  question, and the frontier count ("PLAN-career-hub: 3 open, next: Q2 —
  entitlement model").
- **`/lint`** — an `active` map untouched for >30 days is rot; *Decisions so
  far* lines that restate content instead of linking an ADR are contradictions.
