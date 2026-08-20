#!/usr/bin/env bash
# ci-green-check.sh — lifecycle test for the required-CI green check
# ("green on one platform is not green", enforced in the machine).
#
# Everything runs against a THROWAWAY $HOME and a throwaway git repo; the real
# `gh` CLI is replaced by a shim on $PATH that replays canned JSON from
# $FAKE_RUNS (run list) and $FAKE_JOBS_DIR/<run-id>.json (per-run jobs).
# No network, no real GitHub, no writes outside mktemp.
#
# Covers: all-green; a failed leg; the PARTIAL MATRIX case (run conclusion
# reads success while a required job is absent); skipped; cancelled; still
# running; rerun resolution (older red + newer green on the same sha); runs
# belonging to a different sha; no run at all; gh missing / unauthenticated;
# malformed, empty, duplicate and missing config; ambiguous job identity; and
# the correction that an UNRELATED workflow still running must not block a
# genuinely green required set.
#
# <!-- claude-docs-toolkit -->
set -u
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CHECK="$REPO_ROOT/hooks/ci-green-check.sh"
[[ -f "$CHECK" ]] || { echo "FATAL: checker not found at $CHECK"; exit 1; }
for dep in jq git; do
    command -v "$dep" >/dev/null 2>&1 || { echo "FATAL: $dep missing"; exit 1; }
done

TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT
export HOME="$TDIR/home"
mkdir -p "$HOME"

# --- fake gh shim ----------------------------------------------------------
# `gh auth status` succeeds unless FAKE_UNAUTHED is set.
# `gh run list --json ...` prints $FAKE_RUNS.
# `gh run view <id> --json jobs` prints $FAKE_JOBS_DIR/<id>.json.
# `gh remote get-url` is git's, not gh's — the checker uses git for that.
BIN="$TDIR/bin"
mkdir -p "$BIN"
cat > "$BIN/gh" <<'SHIM'
#!/usr/bin/env bash
# Record every invocation when GH_CALL_LOG is set, so a test can PROVE which
# flags the checker passed (e.g. --repo) rather than inferring it from success.
[[ -n "${GH_CALL_LOG:-}" ]] && printf '%s\n' "$*" >> "$GH_CALL_LOG"
case "${1:-}" in
    auth) [[ -n "${FAKE_UNAUTHED:-}" ]] && exit 1; exit 0 ;;
    run)
        case "${2:-}" in
            list) [[ -n "${FAKE_RUNS:-}" && -f "$FAKE_RUNS" ]] && cat "$FAKE_RUNS" && exit 0; exit 1 ;;
            view)
                rid="${3:-}"
                f="${FAKE_JOBS_DIR:-}/$rid.json"
                [[ -f "$f" ]] && cat "$f" && exit 0
                exit 1 ;;
        esac ;;
esac
exit 0
SHIM
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# --- throwaway repo --------------------------------------------------------
REPO="$TDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
echo 'base' > "$REPO/app.sh"
git -C "$REPO" add -A
git -C "$REPO" commit -qm seed
git -C "$REPO" remote add origin git@github.com:example/repo.git
SHA=$(git -C "$REPO" rev-parse HEAD)

export FAKE_RUNS="$TDIR/runs.json"
export FAKE_JOBS_DIR="$TDIR/jobs"
mkdir -p "$FAKE_JOBS_DIR"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check() { # check <desc> <condition-exit-status>
    if [[ "$2" == "0" ]]; then ok "$1"; else fail "$1"; fi
}

# --- fixture helpers -------------------------------------------------------
cfg() { printf '%s\n' "$1" > "$REPO/.coderv-ci.json"; }

# The standard 3-job required set used by most cases.
cfg_std() {
    cfg '{"required_jobs":[
      {"workflow":"ci","job":"go-verify (ubuntu-latest, stable)"},
      {"workflow":"ci","job":"go-verify (windows-latest, stable)"},
      {"workflow":"ci","job":"typescript-adapter"}]}'
}

runs() { printf '%s\n' "$1" > "$FAKE_RUNS"; }
jobs_for() { printf '%s\n' "$2" > "$FAKE_JOBS_DIR/$1.json"; }

# A run-list entry. Note the run-level conclusion is deliberately settable to
# "success" independently of the jobs, so the partial-matrix trap is real.
run_entry() { # <id> <workflow> <sha> <status> <conclusion>
    jq -cn --argjson id "$1" --arg wf "$2" --arg sha "$3" --arg st "$4" --arg co "$5" \
        '{databaseId:$id, workflowName:$wf, headSha:$sha, status:$st, conclusion:$co}'
}
job_entry() { # <name> <status> <conclusion>
    jq -cn --arg n "$1" --arg s "$2" --arg c "$3" '{name:$n,status:$s,conclusion:$c}'
}
jobs_doc() { printf '%s' "$*" | jq -s '{jobs:.}'; }

run_check() { bash "$CHECK" --dir "$REPO" 2>&1; }
rc_of()    { bash "$CHECK" --dir "$REPO" >/dev/null 2>&1; echo $?; }

echo "T1: all required jobs green → GREEN (exit 0)"
cfg_std
runs "$(jq -s '.' <<<"$(run_entry 100 ci "$SHA" completed success)")"
jobs_for 100 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "0" ]]; check "exit 0 when every required job succeeded" $?
grep -q "GREEN" <<<"$OUT"; check "verdict says GREEN" $?

echo
echo "T2: THE INCIDENT — windows leg red, everything else green → NOT GREEN"
jobs_for 100 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed failure)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "1" ]]; check "exit 1 when one platform leg failed" $?
grep -q "FAILED.*windows" <<<"$OUT"; check "the failing leg is named as FAILED" $?
grep -q "ubuntu-latest, stable" <<<"$OUT"; check "passing legs still reported (states stay distinguishable)" $?

echo
echo "T3: PARTIAL MATRIX — run conclusion 'success' but a required job never ran"
# This is the core trap: the run-level conclusion lies, so only job enumeration
# can catch it.
runs "$(jq -s '.' <<<"$(run_entry 101 ci "$SHA" completed success)")"
jobs_for 101 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "1" ]]; check "a success-conclusion run missing a required job is NOT green" $?
grep -q "MISSING" <<<"$OUT"; check "the absent job is reported MISSING (its own state)" $?
grep -q "windows-latest" <<<"$OUT"; check "the MISSING row names the absent leg" $?

echo
echo "T4: skipped and cancelled keep their own identity and never pass"
runs "$(jq -s '.' <<<"$(run_entry 102 ci "$SHA" completed success)")"
jobs_for 102 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed skipped)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed cancelled)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "1" ]]; check "skipped/cancelled required jobs are not green" $?
grep -q "SKIPPED" <<<"$OUT"; check "skipped is reported as SKIPPED, not folded into failure" $?
grep -q "CANCELLED" <<<"$OUT"; check "cancelled is reported as CANCELLED" $?

echo
echo "T5: a required job still running → RUNNING (exit 2), distinct from red"
runs "$(jq -s '.' <<<"$(run_entry 103 ci "$SHA" in_progress '')")"
jobs_for 103 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' in_progress '')" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "2" ]]; check "exit 2 (RUNNING) while a required job is in progress" $?
grep -q "RUNNING" <<<"$OUT"; check "verdict says RUNNING, not GREEN and not FAILED" $?

echo
echo "T6: rerun resolution — older red run + newer green run on the SAME sha"
# Run ids are monotonic; the newest attempt containing the job decides.
runs "$(jq -s '.' <<<"$(run_entry 200 ci "$SHA" completed failure)
$(run_entry 201 ci "$SHA" completed success)")"
jobs_for 200 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed failure)" \
    "$(job_entry 'typescript-adapter' completed success)")"
jobs_for 201 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
RC=$(rc_of)
[[ "$RC" == "0" ]]; check "the newest attempt wins (green rerun over an older red)" $?
# ...and the reverse ordering must NOT be rescued by the stale green.
runs "$(jq -s '.' <<<"$(run_entry 300 ci "$SHA" completed success)
$(run_entry 301 ci "$SHA" completed failure)")"
jobs_for 300 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
jobs_for 301 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed failure)" \
    "$(job_entry 'typescript-adapter' completed success)")"
RC=$(rc_of)
[[ "$RC" == "1" ]]; check "an older green attempt does NOT rescue a newer red" $?

echo
echo "T7: THE CORRECTION — an unrelated workflow still running must not block green"
# 'nightly' is in progress for the same sha but is NOT in required_jobs. The
# required set is fully green, so the verdict must be GREEN: unrelated jobs
# never manufacture red (nor green).
cfg_std
runs "$(jq -s '.' <<<"$(run_entry 400 ci "$SHA" completed success)
$(run_entry 401 nightly "$SHA" in_progress '')")"
jobs_for 400 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
jobs_for 401 "$(jobs_doc "$(job_entry 'slow-nightly-thing' in_progress '')")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "0" ]]; check "an unrelated in-progress workflow does NOT block a green required set" $?
grep -q "GREEN" <<<"$OUT"; check "verdict is GREEN despite the unrelated run" $?
! grep -q "slow-nightly-thing" <<<"$OUT"; check "the unrelated job is not reported at all" $?
# The mirror: an unrelated FAILING workflow must not manufacture red either.
runs "$(jq -s '.' <<<"$(run_entry 400 ci "$SHA" completed success)
$(run_entry 402 nightly "$SHA" completed failure)")"
jobs_for 402 "$(jobs_doc "$(job_entry 'slow-nightly-thing' completed failure)")"
RC=$(rc_of)
[[ "$RC" == "0" ]]; check "an unrelated FAILED workflow does not manufacture red" $?

echo
echo "T8: same job name in a DIFFERENT workflow does not satisfy the requirement"
# Job identity is {workflow, job}; a like-named job elsewhere proves nothing.
runs "$(jq -s '.' <<<"$(run_entry 500 other "$SHA" completed success)")"
jobs_for 500 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "1" ]]; check "matching job names under the wrong workflow do not count" $?
grep -q "MISSING" <<<"$OUT"; check "they are reported MISSING for the declared workflow" $?

echo
echo "T9: runs belonging to a DIFFERENT sha are never consulted"
OTHER_SHA="0123456789abcdef0123456789abcdef01234567"
runs "$(jq -s '.' <<<"$(run_entry 600 ci "$OTHER_SHA" completed success)")"
jobs_for 600 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "1" ]]; check "a green run on another commit does not make THIS commit green" $?

echo
echo "T10: no run at all for this commit → not green"
runs '[]'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" != "0" ]]; check "no runs for the commit is never a pass" $?
grep -q "MISSING" <<<"$OUT"; check "reported as MISSING" $?

echo
echo "T11: ambiguous identity — two jobs share a name inside one run → UNVERIFIED"
runs "$(jq -s '.' <<<"$(run_entry 700 ci "$SHA" completed success)")"
jobs_for 700 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed failure)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "duplicate job names in a run are UNVERIFIED, never guessed" $?
grep -qi "ambiguous" <<<"$OUT"; check "the reason names the ambiguity" $?

echo
echo "T12: config fails CLOSED — missing, malformed, empty, duplicate, bad shape"
runs "$(jq -s '.' <<<"$(run_entry 800 ci "$SHA" completed success)")"
jobs_for 800 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"

rm -f "$REPO/.coderv-ci.json"
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "NO config → UNVERIFIED (absence is not 'no requirements')" $?

cfg 'not json at all {{{'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "malformed JSON → UNVERIFIED (jq exits 0 on parse errors; must not pass)" $?

cfg '{"required_jobs":[]}'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "EMPTY required_jobs → UNVERIFIED, never a vacuous green" $?
grep -qi "empty" <<<"$OUT"; check "the reason names the empty declaration" $?

cfg '{"required_jobs":[{"workflow":"ci","job":"typescript-adapter"},{"workflow":"ci","job":"typescript-adapter"}]}'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "duplicate entries → UNVERIFIED (declaration is confused)" $?

cfg '{"required_jobs":["typescript-adapter"]}'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "bare job strings (no workflow identity) → UNVERIFIED" $?

cfg '{"jobs":[{"workflow":"ci","job":"typescript-adapter"}]}'
OUT=$(run_check); RC=$(rc_of)
[[ "$RC" == "3" ]]; check "wrong top-level key → UNVERIFIED" $?

echo
echo "T13: tooling unavailable → UNVERIFIED, never a silent pass"
cfg_std
OUT=$(FAKE_UNAUTHED=1 bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "unauthenticated gh → UNVERIFIED (exit 3)" $?
grep -qi "authenticat" <<<"$OUT"; check "the reason names the auth failure" $?

NOGH="$TDIR/nogh"; mkdir -p "$NOGH"
# A PATH containing only the essentials, with no `gh` on it at all.
OUT=$(PATH="$NOGH:/usr/bin:/bin" bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "gh not installed → UNVERIFIED (exit 3)" $?

echo
echo "T14: --json emits a machine-readable verdict with per-job states"
cfg_std
runs "$(jq -s '.' <<<"$(run_entry 900 ci "$SHA" completed success)")"
jobs_for 900 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed failure)" \
    "$(job_entry 'typescript-adapter' completed success)")"
J=$(bash "$CHECK" --dir "$REPO" --json 2>/dev/null)
jq -e '.verdict == "NOT GREEN"' <<<"$J" >/dev/null 2>&1; check "--json reports the verdict" $?
jq -e '.exit == 1' <<<"$J" >/dev/null 2>&1; check "--json carries the exit code" $?
jq -e '[.jobs[] | select(.state == "FAILED")] | length == 1' <<<"$J" >/dev/null 2>&1; check "--json lists the failed job with its state" $?
jq -e '.jobs | length == 3' <<<"$J" >/dev/null 2>&1; check "--json lists every required job, not just the problems" $?

echo
echo "T15: --dir works from ANY cwd, and every gh call is repo-pinned"
# Regression: gh resolves the repository from the process cwd unless --repo is
# passed. A checker run from outside the target repo (which is the normal case
# for /ship invoking an installed hook) would otherwise query the wrong repo or
# fail. The shim records --repo so we can prove it is passed, not assumed.
cfg_std
runs "$(jq -s '.' <<<"$(run_entry 950 ci "$SHA" completed success)")"
jobs_for 950 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
ELSEWHERE="$TDIR/elsewhere"; mkdir -p "$ELSEWHERE"
OUT=$(cd "$ELSEWHERE" && bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "0" ]]; check "GREEN is reached when run from an unrelated cwd" $?
# And from a DIFFERENT git repo — the trap that cwd-resolution would fall into.
OTHER_REPO="$TDIR/otherrepo"; mkdir -p "$OTHER_REPO"
git -C "$OTHER_REPO" init -q
git -C "$OTHER_REPO" config user.email t@t; git -C "$OTHER_REPO" config user.name t
echo x > "$OTHER_REPO/x"; git -C "$OTHER_REPO" add -A; git -C "$OTHER_REPO" commit -qm seed
git -C "$OTHER_REPO" remote add origin git@github.com:someone/unrelated.git
OUT=$(cd "$OTHER_REPO" && bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "0" ]]; check "GREEN is reached when cwd is a DIFFERENT git repo" $?
# Prove the run-view call carried --repo (not merely that the shim tolerated it).
CAPTURE="$TDIR/ghcalls"; : > "$CAPTURE"
OUT=$(cd "$ELSEWHERE" && GH_CALL_LOG="$CAPTURE" bash "$CHECK" --dir "$REPO" 2>&1)
grep -q "run view .*--repo example/repo" "$CAPTURE"; check "gh run view is pinned with --repo" $?
grep -q "run list .*--repo example/repo" "$CAPTURE"; check "gh run list is pinned with --repo" $?
# A repo with no origin remote cannot be resolved → UNVERIFIED, never a pass.
NOREMOTE="$TDIR/noremote"; mkdir -p "$NOREMOTE"
git -C "$NOREMOTE" init -q
git -C "$NOREMOTE" config user.email t@t; git -C "$NOREMOTE" config user.name t
echo y > "$NOREMOTE/y"; git -C "$NOREMOTE" add -A; git -C "$NOREMOTE" commit -qm seed
cp "$REPO/.coderv-ci.json" "$NOREMOTE/.coderv-ci.json"
OUT=$(bash "$CHECK" --dir "$NOREMOTE" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "no origin remote → UNVERIFIED (exit 3), never a pass" $?

echo "T16: the run list is queried BY COMMIT, not filtered from a global window"
# A recent-runs window silently stops containing the target commit as history
# grows; every required job would then read MISSING — a false red indistinguishable
# from a real one. The shim log proves --commit is passed.
cfg_std
runs "$(jq -s '.' <<<"$(run_entry 960 ci "$SHA" completed success)")"
jobs_for 960 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
CAP2="$TDIR/ghcalls2"; : > "$CAP2"
OUT=$(GH_CALL_LOG="$CAP2" bash "$CHECK" --dir "$REPO" 2>&1)
grep -q -- "--commit $SHA" "$CAP2"; check "gh run list is scoped with --commit <full sha>" $?

echo
echo "T17: an abbreviated or unknown --sha is resolved, never prefix-matched"
# Prefix matching could pool runs from sibling commits and let the highest run
# id manufacture a verdict.
SHORT="${SHA:0:8}"
OUT=$(bash "$CHECK" --dir "$REPO" --sha "$SHORT" 2>&1); RC=$?
[[ "$RC" == "0" ]]; check "a valid abbreviated sha resolves to the full commit and works" $?
OUT=$(bash "$CHECK" --dir "$REPO" --sha "deadbee" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "an unresolvable sha is UNVERIFIED, never a pass" $?
# A run whose headSha merely SHARES A PREFIX must not be counted.
PREFIX_SHA="${SHA:0:6}$(printf '%034d' 7)"
runs "$(jq -s '.' <<<"$(run_entry 961 ci "$PREFIX_SHA" completed success)")"
jobs_for 961 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" != "0" ]]; check "a run sharing only a sha PREFIX does not count as this commit's" $?
# Defence in depth: even if a partial id somehow reached the query stage, it must
# be refused rather than prefix-matched. GH_REPO bypasses the remote lookup so
# this exercises the sha guard itself, not the repo resolution.
runs "$(jq -s '.' <<<"$(run_entry 962 ci "$SHA" completed success)")"
jobs_for 962 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed success)" \
    "$(job_entry 'typescript-adapter' completed success)")"
# A 7-char id that IS a real prefix of HEAD but is not a full id: the resolution
# step expands it, so the guard must see 40 chars. Feed the guard directly by
# pointing --dir at a repo where the abbreviation cannot resolve.
OUT=$(bash "$CHECK" --dir "$NOREMOTE" --sha "${SHA:0:7}" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "an abbreviation unresolvable in the target repo is UNVERIFIED" $?
grep -qiE "resolve|remote" <<<"$OUT"; check "the reason names why it could not be established" $?

echo
echo "T18: every other terminal conclusion is handled, none pass"
for CONCL in timed_out action_required stale neutral; do
    runs "$(jq -s '.' <<<"$(run_entry 970 ci "$SHA" completed failure)")"
    jobs_for 970 "$(jobs_doc \
        "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
        "$(job_entry 'go-verify (windows-latest, stable)' completed "$CONCL")" \
        "$(job_entry 'typescript-adapter' completed success)")"
    OUT=$(bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
    [[ "$RC" == "1" ]]; check "conclusion '$CONCL' is NOT green (exit 1)" $?
    grep -q "$CONCL" <<<"$OUT"; check "conclusion '$CONCL' is preserved in the report" $?
done
# An unrecognised conclusion is UNVERIFIED — not assumed bad, not assumed good.
runs "$(jq -s '.' <<<"$(run_entry 971 ci "$SHA" completed success)")"
jobs_for 971 "$(jobs_doc \
    "$(job_entry 'go-verify (ubuntu-latest, stable)' completed success)" \
    "$(job_entry 'go-verify (windows-latest, stable)' completed some_future_state)" \
    "$(job_entry 'typescript-adapter' completed success)")"
OUT=$(bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "3" ]]; check "an unknown conclusion is UNVERIFIED, never guessed" $?

echo
echo "T19: distinct {workflow, job} identities are not mistaken for duplicates"
# A separator-less concatenation would read {ab,c} and {a,bc} as the same key.
cfg '{"required_jobs":[{"workflow":"ab","job":"c"},{"workflow":"a","job":"bc"}]}'
runs "$(jq -s '.' <<<"$(run_entry 980 ab "$SHA" completed success)
$(run_entry 981 a "$SHA" completed success)")"
jobs_for 980 "$(jobs_doc "$(job_entry 'c' completed success)")"
jobs_for 981 "$(jobs_doc "$(job_entry 'bc' completed success)")"
OUT=$(bash "$CHECK" --dir "$REPO" 2>&1); RC=$?
[[ "$RC" == "0" ]]; check "{ab,c} and {a,bc} are distinct identities, not duplicates" $?
! grep -qi "duplicate" <<<"$OUT"; check "no false duplicate rejection" $?

echo
echo "T20: the checker is plain text (no NUL bytes / not binary to git)"
# A NUL byte makes the script binary to git and undiffable in review. bash strips
# NUL from $'\x00', so a grep for it silently becomes an empty (always-matching)
# pattern — count the bytes directly instead.
[[ "$(tr -dc '\000' < "$CHECK" | wc -c)" == "0" ]]
check "hooks/ci-green-check.sh contains no NUL bytes" $?
grep -Iq . "$CHECK"; check "hooks/ci-green-check.sh is text, not binary, to git-style tooling" $?

echo "T21: a value-taking flag with no value exits, never spins forever"
# `shift 2` with one argument left fails; with `|| true` the argument list never
# shrank and the parser looped forever, freezing the caller (the KI-005 class of
# hang). Each case is run under `timeout` so a regression FAILS instead of
# hanging the suite.
for FLAG in --dir --sha; do
    timeout 5 bash "$CHECK" "$FLAG" >/dev/null 2>&1; RC=$?
    [[ "$RC" != "124" && "$RC" != "137" ]]; check "'$FLAG' with no value terminates (no infinite loop)" $?
    [[ "$RC" == "3" ]]; check "'$FLAG' with no value exits UNVERIFIED (3)" $?
    timeout 5 bash "$CHECK" "$FLAG" "" >/dev/null 2>&1; RC=$?
    [[ "$RC" == "3" ]]; check "'$FLAG' with an EMPTY value exits UNVERIFIED (3)" $?
done
timeout 5 bash "$CHECK" --bogus >/dev/null 2>&1; RC=$?
[[ "$RC" == "3" ]]; check "an unknown flag exits UNVERIFIED, not silently" $?

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
exit 0
