# Known Issues & Recurring Bugs — toolkit

> Recurring issues with skills, installer, or templates.
> Each fixed non-obvious bug gets an entry with a **prevention rule**.

---

## Template

```
## KI-NNN: <Symptom>

**First seen:** YYYY-MM-DD
**Last seen:** YYYY-MM-DD
**Status:** open | fixed in commit <hash>

### Symptom
What the user sees.

### Root cause
The actual bug.

### Fix
What was changed.

### Prevention
Rule / test / check that would catch this next time.

### Related
- ADR-NNN / KI-NNN
```

---

## KI-001: drift-hunter note sits downstream of the review cache

**First seen:** 2026-07-17
**Last seen:** 2026-07-17
**Status:** open (follow-up; not a release blocker per owner)

### Symptom
The drift-status decision (fresh-spec drift-hunt vs. generic "drift NOT checked")
is computed *after* the 24h review cache check in `codex-review-gate.sh`. If an
identical diff (same repo + HEAD + diff bytes) is first reviewed in one drift
state and then re-run in a different drift state — e.g. reviewed with no fresh
spec, then a fresh spec appears without the diff changing — the cached verdict
is reused and the drift status does not refresh for that diff.

### Root cause
The cache key is `sha256(repo + HEAD + diff)` and the cache short-circuits with
`exit 0` before the drift/spec-freshness block runs. Spec freshness is not part
of the key, so a spec-state change on an unchanged diff is invisible to the cache.

### Fix
None yet — recorded as a follow-up. In normal use `/before` writes the spec
*before* any diff exists, so the drift state is stable across a task and the
window can't occur; this is the same post-cache placement class as `HIST_NOTE`
and `TRUNC_NOTE`. When addressed, the fix is to fold a spec-freshness marker
(e.g. the fresh spec's `Base:` + mtime, or "no-fresh-spec") into the cache key.

### Prevention
If the cache key ever needs to reflect review *mode* (not just diff bytes),
add the mode to the hash — a stubbed-codex test that runs the same diff twice
under different spec states and asserts the second run re-reviews would catch a
regression.

### Related
- ADR-009 (the drift-hunter this concerns)

<!-- New entries above this line, newest first -->
