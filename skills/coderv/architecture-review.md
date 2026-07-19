<!-- coderlap:runbook:architecture-review -->
# Architecture & integration audit — run-book

> Driven by `/coderv` when the request is the **🏛 Architecture / system audit**
> shape (see `SKILL.md` Step 1). This file is the *how*; `/coderv` stays the
> router (SR). The output is a scored, Codex-verified report — **advice, never
> an auto-fix.** Findings hand back into the normal fix pipeline on one yes.

The audit answers three questions a diff-level reviewer never can:

1. **Is the code well-structured?** — layering, coupling, cohesion, duplication,
   module boundaries, dead code.
2. **Is everything wired correctly?** — every API call, DB reference, and
   `proxy_pass` points at something that actually exists.
3. **Is anything left running that shouldn't be?** — orphaned services, retired
   ports still routed, dead nginx sites ("a server left alone").

Questions 2–3 are why this is an *integration + system* audit, not a linter.

## The pipeline (fan-out → dedup → Codex verify → report)

```mermaid
flowchart TD
    A["/coderv 🏛 audit shape"] --> B["Step 0 · SCOUT<br/>read-only Explore agent<br/>maps the tree + reads SERVER-MAP.md / ss / pm2"]
    B --> C{Live-service<br/>context?}
    C -->|live runtime| D["7 dimensions"]
    C -->|partial runtime| DP["dims 6–7 gated<br/>per source that ran"]
    C -->|registry only| D1["6 dimensions<br/>(wiring vs registry;<br/>liveness NOT observed)"]
    C -->|none| D2["5 code dimensions only"]
    D --> E
    DP --> E
    D1 -->|dim 7 skipped| E
    D2 -->|dims 1–5 only, 6–7 skipped| E

    subgraph E ["Step 1 · FAN-OUT — parallel dimension agents"]
      direction LR
      E1["layering"]
      E2["coupling / cohesion"]
      E3["duplication"]
      E4["module boundaries"]
      E5["dead code"]
      E6["integration wiring"]
      E7["service liveness"]
    end

    E --> F["Step 2 · DEDUP<br/>merge by file:line + principle<br/>(plain code, not an agent)"]
    F --> G["Step 3 · CODEX VERIFY<br/>each finding sent adversarially<br/>same stdin channel as codex-review-gate.sh<br/>refuted → dropped"]
    G --> H["Step 4 · REPORT<br/>docs/ARCH-REVIEW-&lt;date&gt;.md<br/>scored P0–P3, file:line, principle, fix"]
    H --> I{"Findings to act on?"}
    I -->|yes, one yes| J["hand off to fix pipeline<br/>/before → work → verify → /ship"]
    I -->|no| K["report stands; /session surfaces open P0/P1"]
```

## Step 0 — Scout (read-only, one subagent)

Spawn ONE `Explore` agent. It does not judge — it gathers the map every other
step reads, so the fan-out agents don't each re-walk the tree:

- Project shape: top-level dirs, entry points, the dependency manifest, and
  `docs/architecture.md` if `/docify` ever wrote one.
- **Live-service context** — record which of these the scout actually got,
  as one of three states (a registry and an observed runtime are NOT the
  same evidence):
  - `live` — `ss -tlnp` + `pm2 jlist` + `nginx -T` ran (observed runtime).
    A `SERVER-MAP.md` found up the tree is cross-checked against it.
    **PM2 daemons are per-user:** run `pm2 jlist` as the registered app
    owner (e.g. `sudo -u appuser pm2 jlist` where the registry says apps run
    under `appuser`) — a root-run `pm2 jlist` sees root's separate daemon
    and would falsely report the apps gone. **And PM2's CLI is not
    read-only when the daemon is down** — it will spawn a fresh daemon,
    mutating live state. So before invoking any pm2 command, verify the
    owner's daemon socket actually exists —
    `test -S <owner-home>/.pm2/rpc.sock` (or `$PM2_HOME/rpc.sock` if the
    owner sets `PM2_HOME`) — a socket, not a pgrep, is the daemon's real
    liveness proof. Then run with the owner's HOME resolved:
    `sudo -u <owner> -H pm2 jlist` (without `-H`, PM2 may read root's
    `~/.pm2` and inspect — or create — the wrong daemon). No socket → do
    NOT invoke pm2; record `pm2 ✗ (daemon not running)` as an evidence gap
    for dimension 7, never as "no apps running".
    **Sanitize at collection, not later:** raw `pm2 jlist` embeds each
    process's full environment (tokens, connection strings) in `pm2_env`,
    and `nginx -T` can carry credentials. Keep only the operational fields
    the moment each command runs —
    `pm2 jlist | jq '[.[] | {name, pid, status: .pm2_env.status}]'` and
    `nginx -T 2>/dev/null | grep -E '^\s*(server_name|listen|proxy_pass|upstream|server\s|root)' | sed -E 's#//[^/@ ]+@#//#g; s#\?[^ ;]*##g'`
    (routing shape only, with URL userinfo AND query strings stripped — a
    `proxy_pass http://user:pass@host/x?api_key=…` must lose both right
    here; auth, ssl key paths, and everything else stays out) — so no
    secret ever enters the scout map, an agent's context, or the report.
    The same rule covers the registry: when copying `SERVER-MAP.md`
    material into the scout map, carry only operational fields (ports,
    process names, domains, upstreams) and strip anything
    credential-shaped — values of key/token/password/secret/DSN fields.
    (The Codex-payload redaction in Step 3 is the second line of defence,
    not the first.)
  - `registry-only` — a `SERVER-MAP.md` exists but the runtime commands
    aren't runnable here. A static registry can say what *should* be wired
    where — it cannot reveal an unregistered orphan process, a dead
    listener, or actual nginx/PM2 state.
  - `none` — neither.

Runtime sources can also fail **partially** (`ss` ran, the owner's PM2
daemon didn't, `nginx -T` needs privileges you lack) — that is its own
state, `partial`, never rounded up to `live`. A source only counts as
"ran" if the source command itself exited 0 AND produced non-empty,
parseable output — check the source's own exit status (`PIPESTATUS[0]`, or
run it to a variable before piping), because `pm2 jlist | jq` reports jq's
success even when PM2 failed.

The scout returns a compact map + the `liveness_context` state, which gates
dimensions 6–7 honestly (never claim a check that could not run — same rule
as the gate's "drift NOT checked"):
- `live` → both run, against observed runtime (every source ran).
- `partial` → the Liveness-context line lists each source's status
  (`ss ✓ · pm2 ✗ (daemon unreachable) · nginx ✓`); each of dimensions 6–7
  runs only the checks whose needed sources ran, and reports the rest as
  evidence gaps for that dimension.
- `registry-only` → dimension 6 (integration wiring) runs **against the
  registry only**; dimension 7 (service liveness) does NOT run. The report
  states *"wiring checked against SERVER-MAP.md only; service liveness NOT
  checked (runtime not observed)"*.
- `none` → dimensions 6–7 do NOT run — the report states *"no live-service
  context available → code-only audit; integration wiring and service
  liveness NOT checked"*.

## Step 1 — Fan-out: the seven dimensions

Each dimension is one agent, all in parallel. Every agent returns findings as
`{file, line, principle, severity, evidence, fix}` — no prose reports. The
`principle` names the violated rule so the advice is specific (e.g.
*"tight coupling / low cohesion"*, not *"could be cleaner"*).

| # | Dimension | What it hunts | Names the principle |
|---|---|---|---|
| 1 | **Layering** | UI reaching into the DB, a lower layer importing an upper one, cycles | layer inversion / dependency cycle |
| 2 | **Coupling / cohesion** | One module importing many others; a "god" file doing unrelated jobs | tight coupling ↔ *loose coupling*; low cohesion ↔ *high cohesion* |
| 3 | **Duplication** | The same logic in ≥2 places that should be one source of truth | DRY |
| 4 | **Module boundaries** | Leaky abstractions, a public surface that exposes internals | SR / encapsulation |
| 5 | **Dead code** | Exports nothing imports; routes nothing calls; feature-flagged-off branches left forever | dead code / YAGNI residue |
| 6 | **Integration wiring** *(needs live context)* | An API call / DB ref / `proxy_pass` / env var pointing at a target that isn't in the registry or isn't a live listener | dangling integration |
| 7 | **Service liveness** *(needs live context)* | A PM2 app or port in the registry with no owner; a retired project's port re-bound; an nginx site whose upstream is dead ("a server left alone") | orphaned service / recycled-port hazard |

Dimensions 6–7 read the scout's live-service map directly. On the owner's VPS
they cross-check against `SERVER-MAP.md` §rules (decade-block port ownership,
appuser-only PM2, one-nginx-file-per-domain) — the exact hazards the global
CLAUDE.md warns about (recycled ports silently routing dead domains into live
apps).

## Step 2 — Dedup (plain code, not an agent)

Merge findings by `(file, line)` — **exact line, no bucketing**:
nearby-but-distinct findings stay distinct. Two agents flagging the same
god-file at the same location for coupling and low cohesion collapse into one
finding carrying **all** principles, evidence, and fix suggestions — merging
concatenates, it never discards material (the never-silently-vanish rule
starts here, not at the report). This runs before Codex so the reviewer isn't
paying to verify duplicates.

## Step 3 — Codex adversarial verify

Every deduped finding is sent to Codex to **refute**, one payload per finding,
through the **exact channel `codex-review-gate.sh` uses** — no new invocation
style (DRY with the established two-brain seam):

```bash
# PAYLOAD = the finding + the cited code slice + the dimension agent's
# supporting evidence. Relational claims (no importers, dependency cycle,
# duplicate of X, dead route) MUST include the proof that lives elsewhere in
# the repo — the grep/import-scan output, the second copy's slice — because
# Codex sees only this payload, never the whole tree.
# REDACT BEFORE SENDING: unlike the diff gate (which sees only tracked code),
# this payload can carry runtime config outside git — nginx -T output, env
# values, connection strings. Strip every secret value before the payload
# leaves the machine (API_KEY=****, password/token/key values, credential
# parts of URLs, auth_basic lines). The finding needs the SHAPE of the
# config, never the secret itself.
# PROMPT below; identical flags to the gate.
OUT=$(mktemp)
printf '%s' "$PAYLOAD" | timeout 180 codex exec --skip-git-repo-check \
    -s read-only -o "$OUT" "$PROMPT" >/dev/null 2>&1
RC=$?; REVIEW=$(cat "$OUT" 2>/dev/null); rm -f "$OUT"
```

Prompt (adversarial, findings-only — mirrors the gate's reviewer voice):

> "Reviewing an architecture finding raised by another AI (Claude). Try to
> **refute** it against the code slice + evidence below — is it real, or a
> false positive? Judge conventions, not taste. If it stands, reply
> `CONFIRMED` + one-line why. If the evidence contradicts it, reply
> `REFUTED` + why. If the payload lacks the evidence needed to judge (e.g. a
> repo-wide claim whose proof isn't attached), reply `UNVERIFIABLE` + what's
> missing — do NOT refute a claim you merely couldn't check."

Adjudication (same bounded-convergence discipline as ADR-010): `REFUTED`
findings are **dropped from the report**, but listed in a "Codex refuted (N)"
footnote so nothing is silently discarded (never-delete-history spirit).
`UNVERIFIABLE` findings ship marked `⚠ unverified (evidence gap: <what>)` —
a check that couldn't run is never counted as a refutation.
Codex unavailable / auth lapsed → every finding ships marked
`⚠ unverified (Codex unavailable)` — never a silent skip, never a block.

## Step 4 — The report

Write `docs/ARCH-REVIEW-<YYYY-MM-DD>-<HHMMSS>.md` — the time is ALWAYS in
the name, first run of the day included, so every report has the same shape
and a plain lexicographic `sort` always finds the true newest (a mix of
date-only and timestamped names sorts the date-only file last — `.` > `-` —
and consumers would read a stale report). **Never overwrite an existing
report** — a report is finding history ("rows are never deleted" includes
the file itself); check the chosen path doesn't exist before writing — if
it somehow does (two audits in the same second), wait a second and
re-stamp: every name keeps the same fixed shape, so lexicographic sort
stays correct (a `-2` suffix would sort BEFORE `.md` and hide the newer
report).

**Carry-forward rule — the newest report is always the complete open set.**
Downstream consumers (`/before`, `/ship`, `/session`) read only the newest
report, so a new audit must not hide older open findings: before writing,
read the still-**open** rows of the newest prior report ONLY (by this same
rule it already contains everything older — reading every prior report
would resurrect copies closed since). Each open row either re-appears in
the new report (re-verified, keeping its original date in the title:
`**<title>** (carried from <YYYY-MM-DD>)`) or is closed with a reason
(`Status: fixed ...` / `Status: withdrawn <date> — <why>`). Then mark every
carried row in the prior report `Status: superseded → <new report
basename>` — exactly one report ever holds a finding's open copy, so
closing it in the newest report closes it everywhere. An open finding
never silently vanishes between reports. Structure:

```markdown
# Architecture & integration audit — <YYYY-MM-DD>
> Codex-verified. Advice only — no code was changed.
> Base commit: <git rev-parse HEAD — full SHA (short hashes go ambiguous as history grows; abbreviate only for display); what this audit reviewed. Prefer auditing a CLEAN tree so the stamp truly describes the audited code; if dirty, append `+dirty:` + each changed file with its `git hash-object` blob SHA (deleted files as `path (deleted)` — there is no blob to hash) — those exact contents are what the audit saw; a later edit changes the hash, so staleness checks compare content, not filenames>
> Liveness context: <live (ss+pm2+nginx observed, registry cross-checked) | partial (per source: ss ✓ · pm2 ✗ <why> · nginx ✓) | registry-only (wiring vs SERVER-MAP.md; liveness NOT observed) | none (code-only)>

## Score:  P0 <n> · P1 <n> · P2 <n> · P3 <n>   ( <n> refuted by Codex )

## P0 — must fix (breaks or endangers production)
- **<title>** — `path:line` · principle: <name> · Status: **open**
  <evidence>. **Fix:** <concrete step>.  ✓ Codex CONFIRMED

## P1 — high
  <same row format>

## P2 — medium
  <same row format>

## P3 — low
  <same row format>

## Codex refuted (<n>) — recorded, not acted on
- <title> — `path:line` — Codex: <why>

## Next
👉 <the single highest-value fix>. Act on it? (hands into /before → work → verify → /ship)
```

**A finding is "open" until `/ship` closes it.** Every row starts at
`Status: **open**`. When a commit fixes one, `/ship`'s hot-spot check (on the
reviewer's "addressed" verdict) closes the row **after that commit lands** —
editing it to `Status: fixed YYYY-MM-DD (commit <hash>)` in a docs-only
follow-up commit (the hash doesn't exist until the fixing commit does) — same
pattern as `/ship` marking a tracked gap shipped. Rows are never deleted; the
report is the finding's history. Everything downstream (`/before` prior art,
`/ship` hot-spot warnings, `/session` handoffs) reads only rows still marked
**open**.

Severity rubric (so scoring isn't arbitrary):
- **P0** — a dangling integration to production, an orphaned live service, or a
  layer inversion that will corrupt data. Fix before anything else.
- **P1** — tight coupling / low cohesion on a hot path; real duplication of
  business logic. Fix this sprint.
- **P2** — boundary leaks, moderate duplication. Fix when you touch the area.
- **P3** — dead code, cosmetic structure. Cleanup backlog.

## How this connects to every other command (the weave)

The audit is not a dead-end report — it is wired into the whole loop so its
findings keep reducing errors long after it runs:

| Command | How it uses the audit |
|---|---|
| **`/coderv`** | Routes the 🏛 shape here; on `yes` at Step 4, hands the top finding into the normal fix pipeline. |
| **`/before`** | Reads the newest `ARCH-REVIEW-*.md` as prior art — you plan new work already knowing the fragile spots (hot-spot files become "heads-up" rows). |
| **`/ship`** | If the diff touches a file named in an **open P0/P1** finding, the reviewer step flags it: *"this file has an open architecture finding — did this change address or worsen it?"* Catches regressions at commit time, in the harness. |
| **`/session`** | Surfaces **open P0/P1** findings in the handoff so they don't rot. |
| **`/lint`** | Knows `ARCH-REVIEW-*.md` as a dated doc type — a review whose `Base commit:` stamp predates structural changes (`git diff <base>..HEAD` on source dirs is non-empty) is flagged stale. |
| **`/docify`** | Links the newest review from `architecture.md` so generated docs point at the live audit. |
| **`/decision`** | A structural finding acted on (e.g. splitting a god-module) prompts an ADR so the *why* survives. |

That is the "nothing left, everything connects" property: the audit finds the
problem once, and five other commands keep it in view until it's fixed.
