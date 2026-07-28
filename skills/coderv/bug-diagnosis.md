<!-- coderlap:runbook:bug-diagnosis -->
# Bug diagnosis — run-book

> Driven by `/coderv` when the request is the **🐛 Bug** shape (see `SKILL.md`
> Step 1) and the bug is non-trivial — cause not obvious from the error message,
> or a first look didn't find it. This file is the *how* of the "fix" step;
> `/coderv` stays the router (SR). Trivial bugs (typo, obvious null check,
> error message names the line) skip this run-book — just fix and verify.
>
> Adapted from mattpocock/skills `diagnosing-bugs` (MIT) — see the adoption ADR
> in the toolkit's docs/DECISIONS.md.

**The rule this run-book exists to enforce: no red loop, no theory.** Reading
code to build a hypothesis before a repro command exists is the exact failure
mode this prevents — a plausible-sounding cause, a fix for it, and the real bug
still alive.

## Phase 1 — Build the feedback loop (this IS the diagnosis)

Get **one command** that goes red on *this* bug and will go green when it's
fixed. Everything after this phase is mechanical. Try, in rough order:

1. **Failing test** at whatever seam reaches the bug.
2. **curl / HTTP script** against the running dev server.
3. **CLI invocation** with a fixture input, output diffed against known-good.
4. **Headless browser script** driving the UI (only when the bug lives there).
5. **Replay a captured trace** — save the real payload/event, replay it through
   the code path in isolation.
6. **Bisection harness** — bug appeared between two known states → automate
   "boot at X, check" so `git bisect run` can do the walking.

**Flaky bugs:** don't chase a clean repro — raise the reproduction *rate* (loop
the trigger 100×, add stress, narrow timing) until it's debuggable.

**The loop is done when** you can paste the command AND its red output, and it:
- asserts the **user's exact symptom** (not "didn't crash"),
- gives the same verdict every run (or a pinned high flake-rate),
- runs in seconds, unattended.

**Genuinely can't build one?** Stop and say so — list what was tried, ask the
user for a captured artifact (log dump, HAR, recording) or repro access. Do
NOT proceed to guessing; that's the failure mode, not a fallback.

## Phase 2 — Minimise

Shrink the red scenario one cut at a time (inputs, config, steps), re-running
the loop after each cut, until **every remaining element is load-bearing** —
removing any one turns it green. A minimal repro shrinks the suspect list and
becomes the regression test.

## Phase 3 — Hypothesise (plural, falsifiable, shown)

- **3–5 ranked hypotheses** before testing any — a single hypothesis anchors on
  the first plausible idea.
- Each one falsifiable: *"if X is the cause, changing Y makes the loop go
  green."* Can't state the prediction → it's a vibe, sharpen or drop it.
- **Show the ranked list to the user before testing** — they often re-rank it
  instantly ("we just deployed #3's area"). Don't block if they're away.
- First grep `docs/KNOWN-ISSUES.md` — a prior KI in this area outranks any
  fresh hypothesis.

## Phase 4 — Instrument

One variable at a time, each probe mapped to one hypothesis. Prefer a
breakpoint/REPL over logs; when logging, **tag every line with one unique
prefix** (e.g. `[DBG-4f2a]`) so cleanup is a single grep. Never "log everything
and grep". Performance bugs: measure a baseline first, then bisect — logs lie
about time.

## Phase 5 — Fix + regression test

Regression test **before** the fix, at a **correct seam** — one that exercises
the real bug pattern as it occurred. Watch it fail → fix → watch it pass →
re-run the Phase 1 loop on the original, un-minimised scenario. If no correct
seam exists, that architecture gap **is itself a finding** — record it, don't
fake confidence with a shallow test.

## Phase 6 — Clean up + close the loop

- `grep` the debug prefix — zero hits before `/ship`.
- The confirmed hypothesis goes in the commit message — the next debugger
  learns from it.
- Non-obvious root cause (>15 min, or could recur)? `/ship` adds the
  KNOWN-ISSUES entry with its **prevention rule** — per the project's
  `coderlap:rule:prevention-rules`. If you can't name a prevention rule, the
  debugging isn't finished.
- The verify step of the `/coderv` pipeline then observes the fix in the real
  app as usual; the red-turned-green loop command is the evidence the scorecard
  quotes.
