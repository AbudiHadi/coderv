# /ship — Step 7 — The Verification Scorecard (the approval moment)

The score is **computed, never felt**: gates passed / gates total, each gate a
pass/fail check with its real output shown. The model's job is to run checks
and show receipts — not to estimate confidence. Rules:

- **100% requires every gate ✅ with evidence attached.** A check that can't
  run (no tests configured, no spec file) scores ✖ with the reason — never
  silently dropped from the denominator, never rounded up.
- Claims quote their evidence: "committed" shows the `git log` line; "tests
  pass" shows the runner's summary line. **No pasted output → no claim.**
- Human-judgment items (a trade-off, a design choice) are listed under
  "Judgment items" — NEVER folded into the percentage.

The gates (drop only those meaningless for the project — say which and why):

| # | Gate | Evidence shown |
|---|---|---|
| 1 | Grounding receipt exists for this session | receipt path + mtime |
| 2 | Spec checklist: every item verified in the diff | per-item verdict + quoted diff line |
| 3 | Build passes | last line of build output |
| 4 | Tests pass | runner summary ("N passed, 0 failed") |
| 5 | Doc citations valid (Step 3) | "N/N checked" |
| 6 | Reviewer quotes machine-verified | "N/N string-matched" |
| 7 | Fresh-context reviewer: no open objections | reviewer's verdict line |
| 8 | Nothing unrequested in the diff | reviewer + your own check |
| 9 | No secrets / large binaries staged | check output |
| 10 | Required CI green for the pushed commit | `ci-green-check.sh` verdict line + per-job states |

**Gate 10 applies only to a commit that is already pushed** — it answers "is
what's on the remote green?", so on an unpushed commit it scores ✖ with
"not pushed yet", never ✅. Run it as:

```bash
# Installed next to this skill, under whichever host home it came from.
for H in ~/.claude ~/.codex ~/.gemini; do
  [ -x "$H/hooks/ci-green-check.sh" ] && { "$H/hooks/ci-green-check.sh" --dir "$ROOT"; break; }
done
# (in the toolkit repo itself: hooks/ci-green-check.sh --dir "$ROOT")
```

Exit `0` GREEN · `1` NOT GREEN · `2` RUNNING · `3` UNVERIFIED. **Only exit 0 is
a pass.** RUNNING and UNVERIFIED are ✖-with-reason, never rounded up and never
dropped from the denominator — "CI hasn't finished" and "CI is green" are
different facts. A repo with no `.coderv-ci.json` scores ✖ "required jobs
undeclared", which is the honest answer, not a free pass.

> **Green on one platform is not green.** Never substitute a local test run, a
> single-OS result, or `gh run watch` for this gate. `gh run watch` streams ✓
> for the one leg it follows and then exits 1; the run-level `conclusion` reads
> `success` even when a required job never ran. Only the per-job enumeration
> this gate performs distinguishes a full matrix pass from a partial one.

**Default response:**

````markdown
🚢 Ready to ship — <N> files, <one-line summary>.

**VERIFICATION SCORE: <P>% (<passed>/<total> gates)**

✅ 1 Grounding receipt        → <path> (<date>)
✅ 2 Spec verified 4/4        → [say "evidence" to see per-item proof]
✅ 3 Build                    → "✓ built in 4.2s"
✖ 4 Tests                    → no test runner configured in this repo
✖ 10 Required CI             → RUNNING — windows-latest still in progress
… (all gates, one line each, pasted evidence or the reason it can't run)

Unverified claims: <0, or list them>
Judgment items for you: <none, or one line each>

**Suggested commit message:**
```
<type>: <short summary>

<2-3 sentences on WHY>
```

**On "approve" I run:** `git add <files> && git commit -m "<message>"` — committing exactly the CONVERGED snapshot Step 4.5 certified.

👉 **My recommendation: <approve — 100% | fix gate N first | ship at <P>% because <reason>>.**
````

Below 100%, the failing gate line already says exactly what to fix — the user
should never have to ask "why not 100?".

**On request ("details" / "show checklist"), expand:**

```markdown
**Full pre-commit checklist 🚢**

| Area | Status |
|---|---|
| 📦 Files staged | <N files: one-line summary> |
| 📚 Doc updates offered | <N offered, M applied, K skipped> |
| 🔗 Doc references checked | <✅ all good | ⚠ N stale> |
| 🐛 Bug-prevention notes | <✅ logged | ✅ not needed> |
| 🔐 Secrets / large files | <✅ clean | ⚠ <list>> |
| 🧪 Tests / typecheck | <✅ passed | ⚠ skipped | ⚠ failed> |

**Open issues:**
- <blocker, or ✅ none>
```

**Never commit without the user's explicit approval.** Show the command and
wait for "approve". Then run the commit yourself via the Bash tool, and commit
**exactly the snapshot Step 4.5 certified** — if the bytes moved since (the
hash check is cheap, re-run it), that is a new, unreviewed diff: go back to
Step 4.5, never commit it on the strength of the old verdict.

