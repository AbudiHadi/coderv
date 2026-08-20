# Session Handoffs — toolkit

> End-of-session notes for the toolkit repo. Newest at top.

---

## 2026-08-20 11:53 — ADR-028 SHIPPED end-to-end: committed `b76166d`, installed, verified live, pushed; `main` == `origin/main`

> Supersedes the "BUILT + VERIFIED (not committed)" entry below — that state is
> closed. Everything it listed as pending is done; the detail there (mechanism,
> mutation testing, gotchas) is still accurate and worth reading.

**What shipped:**
- ADR-028 BLOCKER/DEBT practical-impact rule + the corrected ceiling — `b76166d`
  (5 files, 1052+/114−: `hooks/codex-review-gate.sh`, `skills/ship/SKILL.md`,
  `tests/gate-cap.sh`, `docs/DECISIONS.md`, `docs/SESSIONS.md`)
- **Three fail-open holes found DURING `/ship`** and fixed before the commit
  landed (full write-up in ADR-028, "Fail-open holes found at `/ship` time"):
  1. `decl_label()` returned `undeclared` on a contradictory `[blocker][debt]`
     cluster, so the marginal arms (which test `== blocker`) dropped the
     blocking claim and **ALLOWED a commit that should have blocked**. Its
     sibling `sec_in_cluster()` already used contains-not-equals; this had
     diverged. → T84.
  2. The owner-visible ceiling `systemMessage` still hardcoded
     `CEILING SECURITY STOP` + `$SEC_COUNT`, so a correctness blocker at the
     ceiling reported **"0 security/data-loss finding(s) still open"** at the
     exact moment a decision was needed. Now tracks `CEIL_KIND`. → T85.
  3. Follow-on: once a contradictory cluster resolves to `blocker`, the material
     arm's lone-`[debt]` note stopped firing, so the attempted demotion blocked
     **silently**. New `decl_contradictory()` reports it on every severity path;
     `decl_label()` stays two-valued so no arm needs a fourth state. → T84.
  (1) and (2) are mutation-tested — each assertion fails against the pre-fix
  code and passes after. 279 → 295 tests is these regressions.
- `./install.sh --force` run; the live gate now carries the new behavior.

**In flight (not yet shipped):** nothing. Tree clean, nothing unpushed.

**State evidence (verbatim):**
```
$ date "+%Y-%m-%d %H:%M"
2026-08-20 11:53

$ git log --oneline -4
b76166d Classify findings BLOCKER vs DEBT; the ceiling stops the loop without overriding a blocker (ADR-028)
874c994 Verify required CI per job, not per run (ADR-027)
7b2c3a5 docs: session handoff — v0.16.1 shipped + released end-to-end (KI-005, both walks); Windows machine owes pull + reinstall
c600e6a v0.16.1: fix the Windows dirname fixed-point infinite loop in both upward walks

$ git status --porcelain
(empty — clean)

$ git status -sb | head -1
## main...origin/main

$ git rev-parse HEAD origin/main
b76166da42de6d93d8764387bac881f74d028ae2
b76166da42de6d93d8764387bac881f74d028ae2

$ cat VERSION
0.16.1

$ git show HEAD:hooks/codex-review-gate.sh | sha256sum   # committed blob
1c575842a64f2fa5daee4267aaa738305a6ebdaf50f9516a2c2de63795c9ce82
$ sha256sum hooks/codex-review-gate.sh ~/.claude/hooks/codex-review-gate.sh
1c575842a64f2fa5daee4267aaa738305a6ebdaf50f9516a2c2de63795c9ce82  hooks/codex-review-gate.sh
1c575842a64f2fa5daee4267aaa738305a6ebdaf50f9516a2c2de63795c9ce82  /root/.claude/hooks/codex-review-gate.sh

$ bash tests/gate-cap.sh | tail -1
295 passed, 0 failed
$ bash tests/ci-green-check.sh | tail -1
71 passed, 0 failed
```

Committed blob == worktree == live installed hook, all three `1c575842…`.
**BLOCKER/DEBT behavior is LIVE.** Verified behaviorally too, not just by SHA:
sourcing the live hook's own functions, `[blocker][debt][edge]` → `decl=blocker`
+ `contradictory=1`, `[debt][correctness]` → stays material, `[compatibility]`
and `[release-integrity]` both parse, bare `[BUG]` → `untagged` (material).

**Gotchas the next session should know:**
- **The live gate was STALE while it reviewed this very commit.** `install.sh`
  runs *after* the commit, so `b76166d` was reviewed by the pre-ADR-028 hook
  (it returned LGTM, no findings, and 295 tests were green — the commit is
  sound). The **first commit actually judged under the new rules is the next
  one.** Expect a `[blocker]`/`[debt]` declaration on every finding now.
- **A handoff saying "fully verified" is not a substitute for verifying.** The
  prior entry claimed ADR-028 was built and fully verified; three real holes —
  two fail-OPEN — were still in it. Both were the same species: a rule stated
  correctly in one place and not carried to a second place that decides or
  reports the outcome. The gate caught its own bugs, which is the point of it.
- The grounding gate correctly rejected the previous session's receipt (new
  session). A fresh `mode:"full"` receipt was written after actually re-reading
  CLAUDE.md + KI-004 + the hook — do not fake `mode:"skip"` to get past it on
  a real code change.

**Open architecture findings:** none (no `docs/ARCH-REVIEW-*.md` in this repo).

**Active effort map:** none (no `docs/PLAN-*.md` marked active).

**Carried forward (unchanged, all deliberate):**
- **Windows machine still owes `git pull` + `./install.sh --force`** — it has
  been owed since v0.16.1 (KI-005) and now also needs ADR-028.
- **VERSION/CHANGELOG bump is a release-time step**, not done here. `VERSION`
  is still `0.16.1`; `release.sh:35` hard-fails unless VERSION == CHANGELOG top
  entry. ADR-028 is committed and live but **unreleased**.
- **`/release-review` remains intentionally untouched** — installed at
  `~/.claude/skills/release-review/` with the installer marker, but has NO
  source and NO git history in this repo (an orphan). `install.sh` globs
  `skills/*/`, so `--force` does NOT restore or remove it. Whether it belongs
  in the repo is a separate owner decision.
- **`devkit/.coderv-ci.json` remains separate scope** — still untracked in
  `/home/appuser/apps/devkit`; needs its own commit in that repo. The old gate
  finding that demanded it be in this diff was factually wrong (different repo;
  git cannot include paths outside the worktree).

**Next session should probably:**
- Release ADR-028: bump `VERSION`, add the CHANGELOG entry, then `./release.sh`
  (+ the `gh release create` it prints). This is the natural next step now that
  the rule is live and proven.
- Then have the Windows machine pull + `./install.sh --force`.

---

## 2026-08-20 — ADR-028 BLOCKER/DEBT practical-impact rule BUILT + VERIFIED (**not committed**, context gate); CI-green work SHIPPED as `874c994`

> **CLOSED — superseded by the entry above.** Shipped as `b76166d` and pushed;
> the "next session" list here is complete. Kept for the mechanism, the
> mutation-testing notes, and the gotchas, which remain accurate.

Owner's rule: *"Ignore atomic, theoretical, defensive, or extremely low-impact
findings that do not materially affect the user."* Classify every finding
BLOCKER vs DEBT; only BLOCKERs deny; stop searching once materially correct.

### State (verbatim)

```
$ date "+%Y-%m-%d %H:%M"
2026-08-20 07:56

$ git log --oneline -3
874c994 Verify required CI per job, not per run (ADR-027)
7b2c3a5 docs: session handoff — v0.16.1 shipped + released end-to-end (KI-005, both walks); Windows machine owes pull + reinstall
c600e6a v0.16.1: fix the Windows dirname fixed-point infinite loop in both upward walks

$ git status --porcelain
 M docs/DECISIONS.md
 M docs/SESSIONS.md
 M hooks/codex-review-gate.sh
 M skills/ship/SKILL.md
 M tests/gate-cap.sh

$ git status -sb | head -1
## main...origin/main [ahead 1]

$ cat VERSION
0.16.1

$ git diff --stat
 docs/DECISIONS.md          |  85 +++++++++++++
 docs/SESSIONS.md           | 158 ++++++++++++++++++++++++
 hooks/codex-review-gate.sh | 295 +++++++++++++++++++++++++++++++++++----------
 skills/ship/SKILL.md       |  48 +++++++-
 tests/gate-cap.sh          | 245 ++++++++++++++++++++++++++++++-------
 5 files changed, 718 insertions(+), 113 deletions(-)
```

Nothing is staged. `874c994` is committed but **NOT pushed** (ahead 1).

### Step 1 — the CI-green backlog SHIPPED (`874c994`)

The previous session's 5 staged files landed as one isolated commit. The
escalated gate finding (*"devkit/.coderv-ci.json missing from the diff"*) was
adjudicated by the owner, who approved the commit conditionally on scope; the
staged set was machine-verified to be exactly the CI-green work first, then the
approval was recorded verbatim via `codex-review-gate.sh --approve` (ADR-023,
single-use, now consumed). **The finding remains factually wrong and unresolved
by design** — devkit is a separate repo; git cannot include paths outside the
worktree.

### Step 2 — ADR-028 built (uncommitted)

- `hooks/codex-review-gate.sh` — owner's wording verbatim as the prompt's
  GOVERNING PRINCIPLE; `[blocker]`/`[debt]` declaration + new `decl_label()`;
  new `[compatibility]` + `[release-integrity]` severity tags; fail-closed
  precedence; "Optional Security Review" → "Non-blocking debt".
- `skills/ship/SKILL.md` — the rule under a new `coderlap:rule:practical-impact`
  marker; Step 4.5 scorecard treats DEBT-only as CONVERGED.
- `tests/gate-cap.sh` — T77–T83 new; T5/T15b/T15c/T21/T22/T22b/T25/T32/T36b
  rewritten to the corrected ceiling rule.
- `docs/DECISIONS.md` — ADR-028.

**Precedence (fail-closed, the load-bearing rule):** severity ALWAYS wins over
the declaration. `[debt]` on a material tag still blocks; a `[blocker]` naming
no category still blocks as malformed; `[blocker]` on a marginal tag blocks on
the higher claim. Anti-evasion floor (untagged/prose/preamble = material) is
untouched. The declaration can only ever CONFIRM the severity.

### The owner's ceiling correction (supersedes ADR-019's blanket allow)

ADR-019 auto-allowed ANY non-security material residue at the hard ceiling.
Owner reversed it: *"The ceiling should stop the loop, not override a material
blocker."* Safe because exotic/defensive findings must now be DEBT, and DEBT
can never keep the loop alive.

**Two latent defects this exposed, fixed beyond the plan:**

1. **`CAP_ESCALATED` was security-only.** A non-security blocker at the ceiling
   denied once with `escalated=0`, so the *identical retry re-passed* — the
   blocker would ship on attempt two. Now any material finding escalates
   durably.
2. **The ceiling message hardcoded "SECURITY STOP."** A correctness or
   compatibility blocker was reported to the owner as a security stop. Now
   `BLOCKER STOP`, naming the real category.

### Verification

```
tests/gate-cap.sh        295 passed, 0 failed
tests/ci-green-check.sh   71 passed, 0 failed
bash -n on both changed shell files: OK
```

**Three holes were found at `/ship` time and fixed before the commit landed**
(T84, T85 — full write-up in ADR-028):

1. The `/ship` fresh-context reviewer caught `decl_label()` dropping a
   `[blocker]` claim on a contradictory `[blocker][debt]` cluster — a
   fail-OPEN that ALLOWED a commit it should have blocked.
2. The Codex gate — reviewing this very change — caught the owner-visible
   ceiling `systemMessage` still hardcoding "SECURITY STOP" with `$SEC_COUNT`,
   so a correctness blocker at the ceiling told the owner "0 security/data-loss
   finding(s) still open" at the moment a decision was needed.
3. Codex's second pass caught the follow-on: with the cluster resolving to
   `blocker`, a contradictory declaration on a MATERIAL severity blocked
   silently. Diagnostic-only (verdict was always right), so it is DEBT by
   ADR-028's own rule — fixed anyway, being cheap and in-scope.

(1) and (2) are mutation-tested — each assertion fails against the pre-fix code
and passes after. The 279 → 295 delta is these regression tests.

Lesson worth keeping: **the ADR was handed off as "fully verified" and all
three holes still existed.** A rule stated in the prompt and on the deny path
is not the same as a rule carried to every place that decides or reports the
outcome. The gate caught its own bugs — which is the point of it.

Live prompt inspected via `CODERV_GATE_CAPTURE_DIR` — the owner's wording
reaches the reviewer verbatim.

**Mutation-tested (6 mutants, all killed).** Two SURVIVED the first pass and
were real coverage gaps, now closed:

- **Dropping both new tags from the `sev_label` whitelist left T81 fully
  green** — unknown tags fall through to `untagged`, which also denies, so
  "it denied" never proved the tag was parsed. T81 now asserts via the
  mislabel wording, which only the recognized path can produce.
- **The blocker/debt contradiction guard was never exercised** — the debt list
  only emits when `FINDING_COUNT > MATERIAL_COUNT`, so a single-finding review
  never reaches it. T79 now uses a MIXED fixture.

### Gotchas for the next session

- **Cache markers are written with `printf '%s'` — NO trailing newline**, and
  the readers are `$`-anchored on exact bytes. A hand-forged marker with `\n`
  reads as corrupt (conservatively an open escalation), not as the legacy form.
- **`latest_marker()` is defined ~line 409**; a test using it must sit after
  that, not before (T15c had to be relocated).
- **No single fixture can straddle the ceiling any more** — material denies on
  both sides, marginal allows in round 1. T36b now asserts the real invariant
  (exactly one review CROSSES) and runs in security mode with `[hardening]`,
  the only class that is material yet non-security.
- `MIXED_MARGINAL_REVIEW` is defined at ~line 1600 — unusable by earlier tests.

### Next session — pick up here

1. `/ship` the 4 changed files (+ this handoff). Expect the gate to review the
   change to itself; the suite is green and mutation-checked.
2. `./install.sh --force` — hooks changed; bare install SKIPS existing files.
3. `git push` — `874c994` is committed but unpushed.
4. Separately: `devkit/.coderv-ci.json` still untracked in
   `/home/appuser/apps/devkit`, needs its own commit in that repo.
5. **Parked, owner's explicit decision:** `~/.claude/skills/release-review/`
   exists installed (Jul 21, carries the installer marker) but has **NO source
   in this repo and NO git history** — an orphan. `install.sh` globs
   `skills/*/`, so `--force` will NOT restore it. Whether it belongs in the
   repo is a separate decision; the owner scoped it OUT of ADR-028.

### Not done, on purpose

- **No CHANGELOG entry / VERSION bump** — `release.sh:35` hard-fails unless
  VERSION == CHANGELOG top entry. Release-time step.
- Nothing pushed; no release.

---

## 2026-08-10 — required-CI green enforcement BUILT + VERIFIED, **NOT committed** (context gate); ONE gate finding escalated to the owner

Two repos are dirty and nothing is committed or pushed. The work is finished and
verified; it is blocked on **one owner decision**, not on more engineering.

### State (verbatim)

```
$ date "+%Y-%m-%d %H:%M"
2026-08-10 18:00

$ git -C /root/claude-docs-toolkit log --oneline -3
7b2c3a5 docs: session handoff — v0.16.1 shipped + released end-to-end (KI-005, both walks); Windows machine owes pull + reinstall
c600e6a v0.16.1: fix the Windows dirname fixed-point infinite loop in both upward walks
570b2ab docs: session handoff — v0.16.0 shipped + released end-to-end; toolkit-vs-community decision parked with owner

$ git -C /root/claude-docs-toolkit status --porcelain
M  docs/DECISIONS.md
A  hooks/ci-green-check.sh
M  install.sh
M  skills/ship/SKILL.md
A  tests/ci-green-check.sh

$ git -C /root/claude-docs-toolkit status -sb | head -1
## main...origin/main

$ git -C /home/appuser/apps/devkit log --oneline -3
8f2c56e docs: session handoff - Windows CI fixed, CI green on all 5 jobs
d440526 test: scope the page permission assertion to POSIX platforms
4e795eb docs: session handoff - Phase 1 committed, not pushed

$ git -C /home/appuser/apps/devkit status --porcelain
?? .coderv-ci.json
```

Toolkit files are **staged** (`git add` ran); the commit was refused by the gate.
devkit's single file is still untracked. VERSION is `0.16.1`, unchanged.

### What was built

"Green on one platform is not green" existed only as prose in
`devkit/docs/SESSIONS.md:108`. Nothing read it, and devkit shipped twice
believing CI was green after Linux-only validation. Now enforced by a machine:

- `hooks/ci-green-check.sh` (new) — enumerates **per-job** results for HEAD's
  commit against required `{workflow, job}` identities declared per-repo.
- `tests/ci-green-check.sh` (new) — 71 assertions, gate-cap.sh pattern
  (throwaway `$HOME`, shimmed `gh`, canned fixtures, no network).
- `skills/ship/SKILL.md` — one new scorecard gate (Gate 10).
- `install.sh` — `TOOL_ROSTER`: skill-invoked tools copied per host, **not**
  wired into settings.json (nothing triggers them on an event).
- `docs/DECISIONS.md` — **ADR-027**.
- `devkit/.coderv-ci.json` (new, other repo) — devkit's real five jobs.

### The ONE open item — owner decision required

The commit gate denied twice; trajectory **3 → 1**. Two findings were real,
fixed, and verified (below). The survivor is **factually wrong** and has now
returned three times on identical evidence, which is the documented escalation
condition — do NOT re-commit to argue it a fourth time.

The finding claims `devkit/.coderv-ci.json` is missing from the outgoing diff.
Machine-verified rebuttal:

```
$ ls -l /home/appuser/apps/devkit/.coderv-ci.json
-rw-r--r-- 1 root root 363 Aug 10 10:04 /home/appuser/apps/devkit/.coderv-ci.json

$ git -C /root/claude-docs-toolkit rev-parse --show-toplevel
/root/claude-docs-toolkit
$ git -C /home/appuser/apps/devkit rev-parse --show-toplevel
/home/appuser/apps/devkit
$ git -C /home/appuser/apps/devkit remote get-url origin
git@github.com:AbudiHadi/devkit.git
```

devkit is a **separate repository**; git cannot include a path outside the
worktree, and Codex only ever sees the toolkit diff. The owner instructed
separate focused commits per repo, so this is correct by design.

**Next session, if the owner agrees the finding is wrong**, the gate's own
documented exit is a per-diff approval (ADR-023):

```
/root/.claude/hooks/codex-review-gate.sh --approve /root/claude-docs-toolkit "<the owner's exact words>"
```

Then commit toolkit (5 staged files), then commit `devkit/.coderv-ci.json`
separately. Never record an approval the owner did not explicitly give.

### Gate findings that WERE real and are fixed

- **`--dir`/`--sha` with no value hung forever.** `shift 2` fails with one arg
  left, `|| true` kept the list unchanged, the parser spun. Confirmed by
  `timeout 5` returning `Terminated`. Same class as KI-005. Now exits `3`;
  T21 covers it **under `timeout`** so a regression fails instead of hanging.
- **The tool installed for Claude only, while `/ship` installs to Codex and
  Gemini too** (`install.sh:528,532`). Gate 10 would have read "unavailable"
  forever on two of three hosts — a gate that silently never runs. Now
  installed/uninstalled per host; `/ship` probes all three homes.

### Earlier Codex round (pre-commit, Step 4.5) — 5 findings, 4 fixed 1 rejected

Fixed: 100-run window → `gh run list --commit <sha>`; a **NUL byte** that made
the script binary to git (from a shell round-trip) plus a separator-less
duplicate key → `unique_by([.workflow, .job])`; prefix sha matching → resolve via
`rev-parse --verify --quiet <sha>^{commit}` then match by equality;
`timed_out|action_required|stale|neutral` → FAILED, unknown conclusion →
UNVERIFIED. Rejected: the same devkit finding above. Round 2 returned **LGTM**.

### Verification (all re-run on the final tree)

```
tests/ci-green-check.sh   71 passed, 0 failed
tests/gate-cap.sh        255 passed, 0 failed
install round-trip        installed+executable in .claude/.codex/.gemini; removed from all three
```

Live, from a neutral cwd (NOT inside devkit — that hid a real `--repo` bug once):

```
$ ci-green-check.sh --dir /home/appuser/apps/devkit --sha 4e795eb
{"verdict":"NOT GREEN","exit":1,"failed":["go-verify (windows-latest, stable)"]}

$ ci-green-check.sh --dir /home/appuser/apps/devkit
{"verdict":"GREEN","exit":0,"n":5}
```

`4e795eb` is the real commit that shipped believing it was green.

### Gotchas for the next session

- **Mutation-test before trusting a green suite.** Six mutants were killed
  (partial-matrix blindness, unrelated-workflow consultation, vacuous empty
  config, unpinned `gh run view`, global-window query, resolution bypass).
- **One equivalent mutant exists and is NOT a coverage gap**: loosening the
  `^[0-9a-f]{40}$` guard to `{7,40}` changes nothing, because `rev-parse`
  always returns 40 chars on both paths. Do not add dead code chasing it.
- **`grep -qa $'\x00'` cannot detect NUL** — bash strips it, the pattern becomes
  empty and matches everything. Use `tr -dc '\000' | wc -c`.
- **jq exits 0 on parse errors piped through `head`** — check `$?` of jq itself.
  The real vacuous-pass risk is `?` absorbing a missing/empty key on valid JSON.
- **Run the checker from OUTSIDE the target repo** when testing; `gh` resolves
  the repo from cwd unless `--repo` is passed.
- **Toolkit deliberately has NO `.coderv-ci.json`** — it has no GitHub Actions
  workflow, so declaring one would be false coverage. Gate 10 correctly scores
  ✖ "required jobs undeclared". Owner decision, not an oversight.

### Deliberate follow-ups (NOT done, on purpose)

- **No CHANGELOG entry.** `release.sh:35` hard-fails unless VERSION == CHANGELOG
  top entry, and history shows CHANGELOG moves **with** a version bump
  (`c600e6a` = `v0.16.1:`). Adding one now without bumping VERSION would break
  the release gate. Do it at release time.
- Nothing pushed. Owner did not authorize a push.

---

## 2026-07-29 — v0.16.1 SHIPPED + RELEASED end-to-end: the Windows dirname fixed-point hang (KI-005), both walks guarded

**What shipped:**
- `c600e6a` — the KI-005 fix: on Windows `os.path.dirname("D:\\")` returns `"D:\\"` unchanged, so grounding-gate's project-root walk never terminated for any edited file outside the home drive — the orphaned `python.exe -` child spun at 100% CPU and froze the whole CLI (the hook timeout kills the bash wrapper, not the Python child). The walk now breaks when `dirname` stops making progress (`hooks/grounding-gate.sh:55-58`). The fresh-context reviewer then falsified the "no other hook has this pattern" claim: the commit gate's bash spec-root walk (`hooks/codex-review-gate.sh`, guarded only by `!= "/"`) had the same latent fixed point (`dirname "."` is `"."`, reachable from a native-form Windows path) — same guard applied in the same commit. Plus VERSION 0.16.1, CHANGELOG entry, docs/KNOWN-ISSUES.md KI-005 with the prevention rule (walks terminate on "dirname made no progress", replay under `ntpath` before trusting).
- **Released v0.16.1 the whole way:** `./release.sh` clean (tag pushed, website site.ts→0.16.1, rebuilt, site repo committed) + `gh release create v0.16.1` page. Both changed hooks copied to `/root/.claude/hooks/`.
- /ship loop trajectory: round 1 Codex caught a real CHANGELOG regression (the 0.16.1 edit had *replaced* the `## [0.16.0]` header, absorbing its notes — "never delete history" violation); round 2 LGTM; fresh-context audit added the bash-twin + separator + "no-op on Linux is overstated (POSIX `//` also hung)" findings; round 3 LGTM, hash-stable → CONVERGED. Commit-time gate: LGTM first try. Suite 255/255 after the gate-hook edit.

**In flight (not yet shipped):**
- Nothing in this repo. The **owner's Windows machine still runs the buggy hooks**: pull + `./install.sh` there (hooks changed → reinstall required), and kill any leftover `python.exe -` process (Task Manager or `Get-Process python | Stop-Process`).

**State evidence (verbatim):**
```
$ git log --oneline -3
c600e6a v0.16.1: fix the Windows dirname fixed-point infinite loop in both upward walks
570b2ab docs: session handoff — v0.16.0 shipped + released end-to-end; toolkit-vs-community decision parked with owner
ea3f155 docs: credit mattpocock/skills in the README
$ git status --short
(clean)
$ cat VERSION
0.16.1
$ bash tests/gate-cap.sh | tail -1
255 passed, 0 failed
```

**Gotchas the next session should know:**
- Linux was never fully immune: the old walk also hung on POSIX `//`-rooted paths (`posixpath.dirname("//") == "//"` and `len("//") > 1` passed the guard). The new break fixes that too — don't re-describe the bug as Windows-only in future docs.
- The `tests/gate-cap.sh` suite does NOT cover grounding-gate at all — its verification here was manual (`ntpath` replay + live hook run). A grounding-gate termination test would make the KI-005 prevention rule machine-checked.

**Next session should probably:**
- Confirm the owner's Windows machine pulled v0.16.1 + reinstalled (the freeze stays live there until then), then consider a small `tests/grounding-gate.sh` termination suite.

---

## 2026-07-28 (later) — v0.16.0 SHIPPED + RELEASED end-to-end: /ship loop (13 fixes), README credit, install, tag, website, release pages

**What shipped:**
- `6d08143` — the full v0.16.0 diff (15 files) after the /ship pre-commit loop: Codex 3 rounds + fresh-context reviewer produced **13 fixes on top of the built release** — effort-map lifecycle strand (fog left an emptied map `active` forever), /before's `/ship`-time map-update promise now backed by a real /ship Step 4 checklist item, chart-mode skip re-keyed to one-sitting fit (not fog absence), Decisions-so-far links-only (gist removed), selection-rule ask-which scoped vs /session's record-all, chart-grill scoped vs /before's opt-in, docify's `templates/CONTEXT.md` runtime dangle reworded, /ship's ADR pointer numbered+scoped (ADR-025, toolkit repo), SESSIONS counts corrected, ADR-025 merge-conflicts line annotated with the ADR-026 forward pointer, /lint vocab grep hardened twice (exclude `docs/`, search the **anchor** not the term). Loop end-state was honestly CAP-STOPPED (cap 3, last micro-edit unreviewed) — and the commit-time gate then earned its backstop: round 1 caught `--exclude-dir` placed AFTER `--` (file operand, not option; reproduced with a live grep before fixing), retry LGTM.
- `ea3f155` — README **Credits** section: Matt Pocock's `mattpocock/skills` (MIT) named as the source of the v0.16.0 adoptions, pointing at ADR-025/026.
- **Released v0.16.0 the whole way:** `./release.sh` clean (tag `v0.16.0` pushed to github.com/AbudiHadi/coderv, website site.ts→0.16.0, astro rebuilt, site repo committed `a52db42`, :3070 serving 0.16.0 verified) + `gh release create v0.16.0` page. Skills force-reinstalled to `~/.claude/skills/` (run-books live).

**In flight (not yet shipped):**
- Nothing in this repo — tree clean, everything released.

**State evidence (verbatim):**
```
$ git log --oneline -4
ea3f155 docs: credit mattpocock/skills in the README
6d08143 v0.16.0: adopt the best of mattpocock/skills across the existing commands (ADR-025, ADR-026)
c0074ec docs: rotate SESSIONS.md — move older entries to archive (keep newest 10)
e3dee7c docs: session handoff — ADR-024 shipped + released (v0.15.2)
$ git status --short
(clean)
$ cat VERSION ; git describe --tags
0.16.0
v0.16.0
$ bash tests/gate-cap.sh | tail -1 ; bash tests/mint-eid.sh | tail -1
255 passed, 0 failed
21 passed, 0 failed
```

**Gotchas the next session should know:**
- **Bare `./install.sh` silently SKIPS existing skill dirs** ("exists — use --force"). Updating live skills after a toolkit commit requires `./install.sh --force` — it bit this session (run-books didn't land until the force rerun).
- The "v0.15.2 GitHub release page missing" claim in the previous handoff was STALE — the page has existed since 2026-07-26 (`gh release create` 422'd on it; verified with `gh release list`). Nothing owed there.
- In /lint's stale-vocabulary check, remember WHY the grep is shaped `grep -rFln --exclude-dir={docs,...} -- '<anchor>' .`: options after `--` become file operands (gate finding, reproduced), `docs/` self-matches the glossary row, and the ANCHOR identifier is what must hit code — the term is only for reporting.
- The spec + skip-receipt under `~/.claude/coderlap/` for this task are now stale (task shipped) — /lint's "stale coderlap artifacts" check will rightly offer cleanup next run.

**Open architecture findings (if any):**
- none (no ARCH-REVIEW file in this repo)

**Next session should probably:**
- **OWNER DECISION PARKED:** keep the toolkit vs switch to popular community skill repos. Recommendation already given and recorded (keep the gated toolkit — enforcement is the moat community markdown can't ship — and absorb community ideas periodically, v0.16.0-style); owner said "I will decide later". Don't start new toolkit feature work until this lands.
- If the toolkit stays: the read-only-agent handoff rule queued in `36ca01e` (2026-07-23, owner-ordered) is still docs-only — wire into /session + context-gate + MASTER/skills.md.

---

## 2026-07-28 — v0.16.0 BUILT, NOT COMMITTED (context gate): mattpocock/skills adoption, both waves — resume at /ship

**Why:** owner evaluated [mattpocock/skills](https://github.com/mattpocock/skills) (~192k stars), goal stated explicitly: *"the target is not show my tools as the best… I am looking for something [that] deliver[s] a clean code to me."* All 17 of his engineering+productivity skills were read in full; the best of them adopted in two waves, everything woven into the existing 7 commands (no new command, no hook changes). Both waves went through /before with Codex plan review (wave 1: 2 rounds → CONVERGED; wave 2: 2 rounds → CONVERGED).

**What was built (uncommitted — 11 modified + 3 new files; this handoff entry makes SESSIONS.md the 12th modified, 15 dirty total):**
- **Wave 1 (ADR-025):** `templates/CONTEXT.md` project-vocabulary template + /docify generates `docs/CONTEXT.draft.md` (drafts-first) + /before reads it (Step 3 pos 2) + /lint deterministic anchor check; `coderlap:rule:tests` + `coderlap:rule:design` markers (scoped, named exceptions); Fowler 12-smell baseline in /ship's fresh-context reviewer brief (advisory only, never scorecard gates); prototype-first option + Seam row in /before Step 5; `skills/coderv/bug-diagnosis.md` run-book (red repro loop BEFORE any hypothesis) wired to the 🐛 shape.
- **Wave 2 (ADR-026):** `skills/coderv/effort-map.md` run-book + 🗺 Big effort shape — `docs/PLAN-<topic>.md` per multi-session effort, `Status: active|done`, map is an INDEX never a store (decisions live only as ADRs, map links them), deterministic selection (`grep -l '^Status: active' docs/PLAN-*.md`, several → ask never guess); /before Step 3 item 9 reads it, /session hands off the frontier, /lint flags >30-day-stale active maps, bare-coderv proposes the next question (precedence slot 4); grill mode = /before Step 4.5 (opt-in, one question at a time with recommendations, scout facts never re-asked); `coderlap:rule:merge-conflicts`.
- **Rejected on paper:** his `code-review` skill (ungated loop vs ADR-019/021–024 — smell baseline adopted, loop not; ADR-025) and my own two-subagent reviewer split (68% confidence — scorecard already separates axes; revisit trigger recorded; ADR-026). Not adopted: wayfinder-with-tracker, triage, to-tickets, handoff, to-spec, research, implement, his persona/content skills — all with reasons in the two ADRs.
- VERSION 0.15.2 → 0.16.0; CHANGELOG `[0.16.0] — 2026-07-28` (no hook changes → no hook reinstall needed).

**Self-audit ran clean before the gate fired:** every spec item grep-verified present; TRIGGER/SKIP intact on all 7 skills; no stale "6 docs" claim anywhere; `git status --porcelain hooks/` = 0 changes.

**State evidence (verbatim):**
```
$ git log --oneline -3
c0074ec docs: rotate SESSIONS.md — move older entries to archive (keep newest 10)
e3dee7c docs: session handoff — ADR-024 shipped + released (v0.15.2)
5dc1e39 Honour the owner gates-off flag at the heredoc fail-closed deny (ADR-024)
$ git status -sb
## main...origin/main
 M CHANGELOG.md
 M README.md
 M VERSION
 M docs/DECISIONS.md
 M skills/before/SKILL.md
 M skills/coderv/SKILL.md
 M skills/docify/SKILL.md
 M skills/lint/SKILL.md
 M skills/session/SKILL.md
 M skills/ship/SKILL.md
 M templates/CLAUDE.md
?? skills/coderv/bug-diagnosis.md
?? skills/coderv/effort-map.md
?? templates/CONTEXT.md
$ cat VERSION
0.16.0
$ bash tests/gate-cap.sh | tail -1
255 passed, 0 failed
```

**Gotchas the next session should know:**
- The spec at `~/.claude/coderlap/specs/-root-claude-docs-toolkit.md` covers BOTH waves (base `c0074ec`, stamped 2026-07-28) — it is the ground truth /ship's reviewer + the gate's drift-hunter will audit this exact diff against. Don't rewrite it, don't /before again — the plan phase is fully done (both Codex rounds CONVERGED).
- All 15 dirty files (the 14 release files + this SESSIONS.md handoff) belong to ONE release — commit as one. The gate reviews the whole dirty tree; nothing unrelated is mixed in (verified: hooks/ untouched).
- ADR-026 explicitly UPDATES one line of ADR-025 (merge-conflicts: skill rejected, distilled rule adopted). If lint ever flags them as contradicting, that's the resolution.
- `~/.claude/skills/` live copies are now OLDER than source — run `install.sh` after commit (skills only; hooks unchanged, no hook reinstall).
- Still pending from 2026-07-25: the GitHub release *page* for v0.15.2 (`gh release create`, cosmetic) and the read-only-agent handoff rule (queued `36ca01e`, still unimplemented).

**Next session should probably:**
- `/ship` this diff (first live run of the smell baseline, fittingly) → then `install.sh` → then owner decides on `./release.sh` for v0.16.0.

---

## 2026-07-25 — ADR-024 SHIPPED + RELEASED (`5dc1e39`, v0.15.2): the last gate block that could trap the owner is closed

**Why:** owner asked for an audit — "does anything block me or my commands, and is every block escapable in-band?" Audited all 23 ADRs + the 4 live gate hooks, cross-checked with Codex (read-only advisory, not a diff review). Result: every gate deny had a clean owner escape EXCEPT one — the commit gate's **heredoc fail-closed deny** (fires when a `<<` heredoc commit can't be awk-sanitized) sat *before* the owner-escape checks, so on an awk-less host an owner saying "ship it" had no in-band way past it. The one spot the gate could overrule the owner — a direct ADR-023 charter violation, surviving in an un-audited corner.

**What shipped (v0.15.2, released clean):**
- **The fail-closed deny now honours the gates-off flag** (`~/.claude/coderlap/gates-off`) via a pure `owner_gates_off_fresh()` predicate defined early (before the branch that calls it), shared with the normal skip site (DRY). `--approve` is deliberately NOT honoured there: when the scrub fails the target repo can only come from the untrusted command, so a cwd-keyed guess could pass a `git -C /other-repo` decoy (Codex plan-review finding 1). gates-off is global → the only safe fail-closed escape.
- **Fixed all stale `CODERV_GATE_OWNER_OVERRIDE` references** — the gate's own commit-time review caught a SECOND one in two-brain-convergence.md:175 my first pass missed (round-2 [DRIFT] finding, fixed in one batch → round-3 LGTM). A hook can't read an env-prefix from a command; `--approve` is the real in-band exit. Legacy runtime check retained (compat), re-documented as launch-env-only.
- **context-gate** "only sanctioned move" softened → one-shot Stop nudge, user is final authority.
- ADR-024, VERSION 0.15.2, CHANGELOG, T76 (suite **255/0**). Hooks installed live this session; `./release.sh` ran clean (tagged+pushed+website synced).

**State evidence (verbatim):**
```
$ git log --oneline -3
5dc1e39 Honour the owner gates-off flag at the heredoc fail-closed deny (ADR-024)
e0b96b4 Fix the coderlap slug on Windows - the grounding gate locked drive-rooted projects forever
36ca01e Docs: queue the read-only-agent handoff rule for the next session (owner order); note v0.15.0 install+release completed
$ git status -sb
## main...origin/main
$ cat VERSION
0.15.2
$ git ls-remote --tags origin | grep v0.15.2
dedd913fbcedf10c421abd9749557b470a41b18b	refs/tags/v0.15.2
$ bash tests/gate-cap.sh | tail -1
255 passed, 0 failed
```

**Gotchas the next session should know:**
- Owner-authority escape map is now: ordinary/cap/ceiling denies → per-diff `--approve`; awk-fail+heredoc fail-closed deny → global gates-off flag. `CODERV_GATE_OWNER_OVERRIDE=1` NEVER works in-band (frozen launch env) — never suggest it.
- Optional leftover: the GitHub Release *page* was NOT created (`gh release create v0.15.2 ...`, command printed by release.sh). The tag itself is live on remote; the page is cosmetic.
- The `read-only-agent handoff rule` queued in `36ca01e` (2026-07-23) is STILL not implemented — only queued in docs. Wire it into /session + context-gate + MASTER/skills.md when picked up.

**Next session should probably:**
- Either create the GitHub release page (one command), OR pick up the still-pending read-only-agent handoff rule from `36ca01e`.

---

## 2026-07-23 (later) — ADR-023 SHIPPED (`68f56b9`): owner authority is mechanical — per-diff `--approve` outranks every gate state; v0.15.0 ready to release

**Why (live-fire failure on alrafiq):** a prior session hit the gate on an owner-approved test branch and dead-ended: the deny told the owner to re-run the commit with `CODERV_GATE_OWNER_OVERRIDE=1`, but the hook reads env FROZEN at session launch — a command prefix never reaches it, for agent or owner alike. The owner's requirement (verbatim in ADR-023): when he explicitly says "approved", the exact rejected diff must ship — no cap-waiting, no cache tricks, no terminal commands — while the gate stays armed for everything else.

**What shipped (`68f56b9`, v0.15.0):**
- `codex-review-gate.sh --approve <repo-dir> "<owner's words>"` records the approval keyed to the sha of repo@HEAD + the exact outgoing diff (shared `collect_outgoing_diff`/`approval_key` functions — review hash and approval key can never diverge). The review path checks the marker at TOP precedence (before round cache/cap/ceiling/security escalation, before any Codex call) → loud allow quoting the owner's words; single-use (consumed on pass); 24h sweep reaps unused markers. Every deny message now teaches this exit.
- `~/.claude/coderlap/gates-off` flag = EMERGENCY off-switch only (24h TTL, loud per-skip) — explicitly secondary, owner rejected it as the primary design.
- Tests T74–T75 (suite **249 checks, 0 failed**): deny names the exit, approval passes exactly once with the quote, marker consumed, stale approval never leaks onto a changed diff, fresh approval outranks a ceiling `[security]` escalation. Two legacy assertions updated to the new deny wording.
- Docs: ADR-023 (rewritten around the owner's requirement), CHANGELOG [0.15.0], VERSION 0.15.0.

**Honest disclosures:**
- This commit itself was NOT Codex-reviewed — the owner's gates-off flag was armed by his explicit in-chat decision (the deny/skip messages surfaced it loudly, as designed).
- The Claude Code auto-mode classifier refuses to let the agent install the hook into `~/.claude/hooks/` or arm/disarm the flag (self-modification rule) — the OWNER must run the install: `cp /root/claude-docs-toolkit/hooks/codex-review-gate.sh /root/.claude/hooks/codex-review-gate.sh` (and `rm /root/.claude/coderlap/gates-off` to re-arm the gate). Until he does, the installed hook is the pre-ADR-023 one (with gates-off support only, installed by his hand this session).

**NEXT SESSION:** (1) DONE same day — owner installed the hook, flag cleared, `./release.sh` ran (v0.15.0 tagged+pushed+released, website synced). (2) first real `--approve` use: quote the owner verbatim in the marker and in the report. (3) **NEW, owner-ordered: the read-only-agent handoff rule.** A read-only recon session (SAADK, 2026-07-23) ended with no handoff — it had no write tools, so its findings existed only as chat text; they survived by luck (a prior session had saved them to `~/.claude/coderlap/recon/`) and by the owner ordering another session to write the handoff for it. Encode the rule: *a read-only agent must never be the last hand to touch its own findings — the LAUNCHING session saves the agent's output to `~/.claude/coderlap/recon/<project>-<date>-<topic>.md` and writes the SESSIONS.md handoff entry BEFORE its own context gate fires.* Wire it into: `/session` skill (a "did any read-only agent run this session?" check), the context-gate message (add it to the sanctioned-moves list), and the docs (MASTER/skills.md). Cost note for the owner: hooks watching = zero tokens; only a fired hook's injected text costs context.

**State evidence (verbatim, at context-gate close):**
```
$ git status -sb | head -2
## main...origin/main [ahead 2]
$ git log --oneline -3
6f529d1 docs: session handoff — ADR-023 shipped, v0.15.0 pending owner install + release
68f56b9 Make owner authority mechanically enforceable in the commit gate (ADR-023)
c419628 Fix the stale 235 suite count the gate flagged; add the ADR-022 ship handoff
$ cat VERSION
0.15.0
$ git tag | tail -2
v0.8.0
v0.9.0
$ diff -q hooks/codex-review-gate.sh /root/.claude/hooks/codex-review-gate.sh
Files ... differ   (INSTALLED HOOK = pre-ADR-023 with gates-off only; owner cp pending)
$ ls /root/.claude/coderlap/gates-off
/root/.claude/coderlap/gates-off   (flag ARMED — expires 24h after 2026-07-23 18:12, or owner rm)
$ bash tests/gate-cap.sh | tail -1
249 passed, 0 failed
```

## 2026-07-23 — ADR-022 SHIPPED (`b8d2ffc`): the gate is a quality gate by default, deep security is /ship --security; v0.14.0 ready to release

**What shipped (the later-5 plan, implemented + hardened + committed):**
- `hooks/codex-review-gate.sh`: `[hardening]` marginal tag + impact-subordination
  governing rule; default mode = ENGINEERING QUALITY GATE brief, marginal-only
  reviews ALLOW in round 1 with an "Optional Security Review (non-blocking)"
  section; mixed denies re-list marginal findings verbatim under that section;
  `CODERV_GATE_SECURITY=1` = deep-security opt-in ([hardening] blocks, old cap
  semantics). `/ship` gained `--security`. Docs: ADR-022, KI-004 closed,
  CHANGELOG [0.14.0], VERSION 0.14.0.
- **Review-driven hardening (3 review rounds + a fresh-context audit, all
  findings fixed, none rejected):** (r1) review MODE joined the gate's cache
  HASH — a default-mode allow never satisfies a --security rerun (T72);
  (audit F1) PreToolUse hooks don't inherit a command env-prefix, so the gate
  now parses `CODERV_GATE_SECURITY=1` from the scrubbed command string
  (upgrade-only) and every verdict names the mode (T73); (r2) an optional-notes
  allow writes NO cache marker — an identical retry re-reviews so findings are
  re-surfaced verbatim, never a count-only caveat (T65). Round 3: LGTM.
- Commit-time gate: allowed at its CEILING (round 15/5 — rounds accumulated at
  this repo@HEAD from the whole pre-pivot lexer saga) with ONE non-security
  residue finding: CHANGELOG:39 said 235 where the suite is 237. Fixed in the
  docs-only follow-up commit that carries this handoff.

**State evidence (verbatim):**
```
$ git log --oneline -2
b8d2ffc Make the default gate an engineering quality gate; deep security is opt-in (ADR-022)
d8ea45f Ban hand-run codex exec — the gate is the only sanctioned review loop (ADR-021)
$ cat VERSION
0.14.0
$ bash tests/gate-cap.sh | tail -1
237 passed, 0 failed
$ diff -q hooks/codex-review-gate.sh ~/.claude/hooks/codex-review-gate.sh
(identical — deployed atomically; install.sh --force also refreshed all skills)
```

**Gotchas the next session should know:**
- The legacy suite (T1–T64) is PINNED to `CODERV_GATE_SECURITY=1` — those
  are the pre-0.14.0 semantics, alive in security mode. Default-mode behavior
  is T65–T73. Don't "fix" the pin.
- The rounds file at d8ea45f carried 15 rounds; the ceiling allow was correct
  behavior, not a bug. HEAD has moved, so the counter is fresh now.
- The grounding receipt this session was a documented skip pointing at the
  converged spec (plan was Codex-LGTM'd in later-5; no /before rerun needed).

**Next session should probably:**
1. Owner: `./release.sh` to tag v0.14.0 + sync the website (owner's call).
2. Optional: backfill release pages v0.6.0–v0.10.1 (needs `gh release create`
   permission — see the 2026-07-19 later-12/13 entries).

---

## 2026-07-22 (later 5) — PIVOT: kill the trickle via a SEVERITY-POLICY redesign (ADR-022), NOT more lexer work. Plan CONVERGED (Codex LGTM r2). Context gate hit BEFORE implementation — fresh session builds it.

**★ START HERE — the plan is done and Codex-approved; nothing is implemented yet.
The round-9 lexer work from later-4 is STILL UNCOMMITTED in the tree but is NO
LONGER the thing to ship. The owner reframed the whole problem. Read this, then
implement the approved spec. ★**

**WHY THE PIVOT (owner's decision — this is the real fix):** the round-8/9 lexer
trickle (one bash-quoting edge per review round, endless) was never a lexer bug —
it was a SEVERITY-POLICY bug. Exotic shell-grammar findings get tagged `[security]`,
and `[security]` can never be marginal, so they block forever. The gate was
"behaving like a penetration tester on every commit." Owner's directive, verbatim
intent: *"redesign the review policy — converge in a SINGLE round for normal dev;
block realistic correctness/regression/data-loss/high-confidence bugs; do NOT
recursively harden against exotic/theoretical/low-frequency attack scenarios;
route deep-hardening findings to an 'Optional Security Review' section instead of
blocking; reserve adversarial/fuzzing/parser-hardening for an explicit opt-in
(`/ship --security`)."*

**OWNER DECISIONS (both locked):**
1. **Scope = POLICY ONLY.** Leave the shell lexer in the tree as-is (it works,
   214/214). Do NOT delete it, do NOT do cwd-only target resolution — that
   direction was explored earlier this session and DE-SCOPED (it just relocated
   the trickle to redirect-vector enumeration: `-C` → `--git-dir` → ambient
   `GIT_DIR` → `-c core.worktree` → `GIT_CONFIG_*`… same infinite-surface trap).
2. **Block line = realistic-impact blocks; exotic → Optional.** Realistic
   high-impact security (real auth bypass / injection reachable by a credible
   attacker) still BLOCKS. Exotic/no-reachable-impact weakness → Optional Security
   Review (allow-with-note).

**THE APPROVED SPEC IS THE GROUND TRUTH:**
`~/.claude/coderlap/specs/-root-claude-docs-toolkit.md` (Base `d8ea45f`, CONVERGED,
Codex LGTM round 2). Implement THAT. Summary of what it says:
- **SEVERITY_RULES** (`hooks/codex-review-gate.sh` ~L1168): add a new MARGINAL tag
  `[hardening]` = security-relevant weakness with NO credible reachable high-impact
  path (the shell-grammar-corner-in-a-self-authored-commit-message class).
  Classification hinges on **REACHABILITY + IMPACT, NOT craftedness** (Codex
  finding: real injection IS crafted and must still block; `[hardening]` is
  FORBIDDEN when a realistic attacker can reach the path). ALL marginal tags
  (`[edge]`/`[theoretical]`/`[hardening]`) are **subordinate to impact** — a
  rare-but-reachable high-impact bug MUST be MATERIAL (Codex finding 2).
- **Reviewer prompt** (BOTH branches, ~L1196+): default = ENGINEERING QUALITY GATE
  brief (one exhaustive pass, prioritize correctness/regression/data-loss/logic,
  route exotic to `[hardening]`/Optional, do NOT recursively harden).
- **Opt-in:** `CODERV_GATE_SECURITY=1` flips to the full adversarial brief AND
  makes `[hardening]` MATERIAL (blocks). `/ship` gets a `--security` flag that
  exports it. Default = quality-gate mode.
- **One-round convergence:** in default mode, marginal-only findings ALLOW-with-
  caveat in ROUND 1 (not cap-gated), listed under a labeled "Optional Security
  Review (non-blocking)" section (transparency preserved — surfaced, not dropped).
  Realistic `[security]`/`[data-loss]`/`[correctness]` still blocks.
- **Tests** (`tests/gate-cap.sh`): (a) hardening-only ALLOWS r1 + Optional section;
  (b) realistic `[security]` BLOCKS; (c) `[correctness]` BLOCKS; (d)
  `CODERV_GATE_SECURITY=1` makes `[hardening]` BLOCK; (e) mixed correctness+hardening
  blocks on correctness, lists hardening in Optional. T1-T15b + lexer tests still pass.
- **Docs:** ADR-022 (the policy split; supersedes the abandoned cwd-only direction);
  close the round-8/9 lexer saga in KNOWN-ISSUES pointing at ADR-022; VERSION →
  **0.14.0** (behavior change); CHANGELOG [0.14.0].
- Deploy hook atomically (temp → `bash -n` → chmod → `mv -f` → `diff -q`); commit
  via `/ship` in DEFAULT mode — it MUST converge in ONE round (that IS the proof).

**RAW STATE at close (verbatim):**
```
$ git status --short
MM CHANGELOG.md
M  VERSION
M  docs/KNOWN-ISSUES.md
MM docs/SESSIONS.md
MM hooks/codex-review-gate.sh
MM tests/gate-cap.sh

$ git log --oneline -3
d8ea45f Ban hand-run codex exec — the gate is the only sanctioned review loop (ADR-021)
1352a5b Give the commit gate memory + project context + a convergence ceiling (ADR-019)
61b0cd2 Move the Claude/Codex argument into a /ship pre-commit loop (ADR-018)

$ cat VERSION
0.13.1                          # spec bumps this to 0.14.0

$ diff -q hooks/codex-review-gate.sh ~/.claude/hooks/codex-review-gate.sh
Files ... differ                # DEPLOYED HOOK != SOURCE. The deployed copy is a
                                # MID-SESSION lexer build; source moved after. Do
                                # NOT trust either as final — the ADR-022 build
                                # will rewrite the source, then redeploy fresh.

$ bash tests/gate-cap.sh   →  214 passed, 0 failed
```

**IMPORTANT nuance for the implementer — the working tree is a MIX:**
- The uncommitted changes contain the later-4 ROUND-9 LEXER WORK (ANSI-C decoder,
  NUL truncation, T54-T64/T57g/h) PLUS partial ADR-022 doc edits I made before the
  pivot (CHANGELOG/SESSIONS still mention 0.13.1 + 213/214 lexer framing). The
  ADR-022 build must OVERWRITE those docs to the 0.14.0 policy framing. The lexer
  code itself STAYS (owner de-scoped its deletion) — it's just non-blocking now.
- The tree is stacked on `d8ea45f`. Do NOT `git reset` — the lexer work is kept.

**DEAD ENDS this session (do not repeat):**
- cwd-only target resolution / deleting the lexer → relocated the trickle to
  redirect-vector enumeration (Codex found 5 classes in 5 rounds). ABANDONED.
- Perfecting the lexer round-by-round → the KI-002 loop. The POLICY fix is what
  ends it: exotic findings simply stop blocking.

**Also still true from later-4:** the deployed hook + 0.13.1 changelog are the
lexer approach; ADR-022 supersedes the framing (not the code). `./release.sh` is
the owner's call AFTER the commit lands.

---

---

> Older sessions: docs/SESSIONS-ARCHIVE.md (nothing is ever deleted)
