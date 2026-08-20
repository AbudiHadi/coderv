#!/usr/bin/env bash
# ci-green-check.sh — "green on one platform is not green", enforced by a
# machine instead of a sentence in a handoff.
#
# A delivery is green only when EVERY job the repository declares as required
# is CONFIRMED successful for HEAD's commit. Anything else — a leg that failed,
# was skipped, was cancelled, never ran, is still running, or cannot be read at
# all — is reported as its own distinct state and exits non-zero.
#
# Why this exists: a repo with a 4-way OS matrix shipped twice believing CI was
# green after validating on Linux only. The run-level conclusion is NOT a
# substitute for the per-job truth — GitHub reports a run `success` while a
# required job is absent from it, so checking `.conclusion` reproduces exactly
# the bug this guards against. This script enumerates jobs, never the summary.
#
# Usage:
#   ci-green-check.sh [--dir <repo>] [--sha <sha>] [--json]
#
# Exit codes:
#   0  GREEN       every declared required job present and successful
#   1  NOT GREEN   a required job failed / cancelled / skipped / is missing
#   2  RUNNING     a required job is still queued or in progress
#   3  UNVERIFIED  the answer could not be established (no gh, not authed, no
#                  remote, no run for this sha, ambiguous identity, bad config)
#
# UNVERIFIED is never a pass. "We could not check" and "it is green" are
# different facts and this script refuses to conflate them.
#
# <!-- claude-docs-toolkit -->
set -u
export LC_ALL=C

GREEN_RC=0; NOTGREEN_RC=1; RUNNING_RC=2; UNVERIFIED_RC=3

DIR="$PWD"
SHA=""
JSON_OUT=0

while (( $# )); do
    case "$1" in
        # A value-taking flag with no value must not `shift 2` — with only one
        # argument left the shift fails, the argument list never shrinks, and the
        # loop spins forever (the same class of hang as KI-005). Demand a value.
        --dir)  [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ci-green-check: --dir needs a value" >&2; exit "$UNVERIFIED_RC"; }
                DIR="$2"; shift 2 ;;
        --sha)  [[ $# -ge 2 && -n "${2:-}" ]] || { echo "ci-green-check: --sha needs a value" >&2; exit "$UNVERIFIED_RC"; }
                SHA="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "ci-green-check: unknown argument '$1'" >&2; exit "$UNVERIFIED_RC" ;;
    esac
done

# ---------------------------------------------------------------------------
# Reporting. Every verdict carries the per-job detail that produced it, so a
# reader never has to trust a summary line.
# ---------------------------------------------------------------------------
VERDICT=""
DETAIL=()          # "state<TAB>workflow<TAB>job<TAB>note"
REASON=""

emit() {
    local rc="$1"
    if (( JSON_OUT )); then
        local rows=""
        local d
        for d in ${DETAIL+"${DETAIL[@]}"}; do
            IFS=$'\t' read -r st wf jb nt <<<"$d"
            rows+=$(jq -cn --arg state "$st" --arg workflow "$wf" --arg job "$jb" --arg note "$nt" \
                '{state:$state,workflow:$workflow,job:$job,note:$note}')$'\n'
        done
        printf '%s' "$rows" | jq -s --arg verdict "$VERDICT" --arg reason "$REASON" --argjson exit "$rc" \
            '{verdict:$verdict, exit:$exit, reason:$reason, jobs:.}'
    else
        echo "required-CI: $VERDICT"
        [[ -n "$REASON" ]] && echo "  $REASON"
        local d
        for d in ${DETAIL+"${DETAIL[@]}"}; do
            IFS=$'\t' read -r st wf jb nt <<<"$d"
            printf '  %-10s %s / %s%s\n' "$st" "$wf" "$jb" "${nt:+  ($nt)}"
        done
    fi
    exit "$rc"
}

unverified() { VERDICT="UNVERIFIED"; REASON="$1"; emit "$UNVERIFIED_RC"; }

command -v jq >/dev/null 2>&1 || { echo "required-CI: UNVERIFIED"; echo "  jq is required but not installed"; exit "$UNVERIFIED_RC"; }

# ---------------------------------------------------------------------------
# Repo + config. The config declares WHAT is required; this script only decides
# whether those requirements are met. It never infers requirements on its own.
# ---------------------------------------------------------------------------
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) \
    || unverified "not a git repository: $DIR"

CONFIG="$ROOT/.coderv-ci.json"

# Fail CLOSED on every config problem. An unreadable or empty declaration means
# "requirements unknown", never "no requirements" — the latter would let a typo
# silently manufacture a green.
[[ -e "$CONFIG" ]] || unverified "no .coderv-ci.json in $ROOT — required jobs are undeclared, so green cannot be established"
[[ -r "$CONFIG" ]] || unverified ".coderv-ci.json exists but is not readable"

# `jq -e` + explicit type and length checks. NOT the `?` operator: on valid JSON
# that merely lacks required_jobs (or carries it empty), `jq -r
# '.required_jobs[]?'` exits 0 with empty output, so a naive loop would iterate
# zero times and report a vacuous pass — the same class of bug this script
# exists to prevent.
jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1 \
    || unverified ".coderv-ci.json is malformed or is not a JSON object"
jq -e 'has("required_jobs") and (.required_jobs | type == "array")' "$CONFIG" >/dev/null 2>&1 \
    || unverified ".coderv-ci.json has no required_jobs array"
jq -e '.required_jobs | length > 0' "$CONFIG" >/dev/null 2>&1 \
    || unverified ".coderv-ci.json declares an empty required_jobs list — nothing would be verified"

# Each entry must carry an explicit {workflow, job} identity. A job name alone
# is ambiguous: the GitHub API exposes workflow identity only on the RUN, never
# on the job, so two workflows defining the same job name are indistinguishable
# without the workflow being declared here.
jq -e '.required_jobs | all(type == "object" and (.workflow | type == "string") and (.workflow | length > 0) and (.job | type == "string") and (.job | length > 0))' "$CONFIG" >/dev/null 2>&1 \
    || unverified ".coderv-ci.json entries must each be {\"workflow\": \"<name>\", \"job\": \"<name>\"}"

# Duplicates are rejected rather than de-duplicated: a repeated entry means the
# declaration is confused about its own requirements, and silently collapsing
# it would hide that.
jq -e '(.required_jobs | length) == (.required_jobs | unique_by([.workflow, .job]) | length)' "$CONFIG" >/dev/null 2>&1 \
    || unverified ".coderv-ci.json contains duplicate {workflow, job} entries"

# ---------------------------------------------------------------------------
# The commit under test.
# ---------------------------------------------------------------------------
if [[ -z "$SHA" ]]; then
    SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null) || unverified "cannot resolve HEAD"
else
    # Resolve whatever was passed to ONE full commit id. An abbreviated sha that
    # matches several commits, or names nothing, is ambiguous — and an ambiguous
    # target must never be answered, because runs from different commits would
    # be pooled and the highest run id could manufacture either verdict.
    RESOLVED=$(git -C "$ROOT" rev-parse --verify --quiet "${SHA}^{commit}" 2>/dev/null) \
        || unverified "cannot resolve '$SHA' to a single commit in this repository"
    SHA="$RESOLVED"
fi
# Full 40-char id only past this point: the run list is matched by equality, not
# by prefix, so a partial id can never pool runs from sibling commits.
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || unverified "not a full commit sha: $SHA"

command -v gh >/dev/null 2>&1 || unverified "gh is not installed — required CI cannot be read"
gh auth status >/dev/null 2>&1 || unverified "gh is not authenticated — required CI cannot be read"

# ---------------------------------------------------------------------------
# Runs for this sha. Fetched once; every required job is resolved against this
# same snapshot so one job cannot be judged against a newer world than another.
# ---------------------------------------------------------------------------
# Resolve the repository ONCE from the target's own remote and pass it to every
# gh call. Without --repo, gh resolves the repository from the process's cwd,
# so a --dir pointing at another checkout would silently query the wrong repo
# (or fail outright). GH_REPO is honoured as an override for callers that have
# no remote configured.
REPO_SLUG="${GH_REPO:-}"
if [[ -z "$REPO_SLUG" ]]; then
    REPO_SLUG=$(git -C "$ROOT" remote get-url origin 2>/dev/null \
        | sed -E 's#^git@[^:]+:#ap#; s#^ssh://[^/]+/#ap#; s#^https?://[^/]+/#ap#; s#\.git$##; s#^ap##')
fi
[[ -n "$REPO_SLUG" ]] || unverified "no git remote 'origin' — cannot tell which GitHub repository to read"

# Ask GitHub for THIS commit's runs rather than filtering a recent-runs window
# locally: a global window silently stops containing the target commit as the
# repository accumulates history, and every required job would then read MISSING
# — a false red that looks exactly like a genuine one.
RUNS=$(gh run list --repo "$REPO_SLUG" --commit "$SHA" \
        --limit 200 --json headSha,workflowName,databaseId,status,conclusion 2>/dev/null) \
    || unverified "could not list workflow runs for $REPO_SLUG (the API refused, or the repo is unreachable)"

jq -e 'type == "array"' <<<"$RUNS" >/dev/null 2>&1 \
    || unverified "unparseable run list from gh"

# Only runs for the exact commit under test. A run for a different sha proves
# nothing about this one and is never consulted.
SHA_RUNS=$(jq -c --arg sha "$SHA" '[.[] | select(.headSha == $sha)]' <<<"$RUNS")

# ---------------------------------------------------------------------------
# Resolve each declared required job independently.
#
# Selection rule, per job: consider ONLY runs for this sha whose workflowName
# matches the job's declared workflow; take the highest databaseId among those
# that actually contain the job (run ids are monotonic, so this is the latest
# attempt and is deterministic — createdAt is not a safe tiebreak, observed
# out-of-order against startedAt on real reruns); that run's copy of the job
# decides. An unrelated workflow is never consulted, so it can neither
# manufacture green nor block a genuinely green result.
# ---------------------------------------------------------------------------
N_REQ=$(jq -r '.required_jobs | length' "$CONFIG")
WORST=""   # sticky verdict: UNVERIFIED > NOTGREEN > RUNNING > GREEN

note_state() { # note_state <state> <workflow> <job> <note>
    DETAIL+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"${4:-}")
}

# Precedence: an unreadable answer outranks a red, which outranks "not finished".
# Escalate-only so no later job can downgrade an earlier problem.
rank() { case "$1" in UNVERIFIED) echo 4 ;; NOTGREEN) echo 3 ;; RUNNING) echo 2 ;; *) echo 1 ;; esac; }
escalate() { local cur; cur=$(rank "${WORST:-GREEN}"); (( $(rank "$1") > cur )) && WORST="$1"; return 0; }

for (( i = 0; i < N_REQ; i++ )); do
    WF=$(jq -r --argjson i "$i" '.required_jobs[$i].workflow' "$CONFIG")
    JB=$(jq -r --argjson i "$i" '.required_jobs[$i].job' "$CONFIG")

    # Candidate runs: this sha AND this workflow, newest id first.
    CAND=$(jq -c --arg wf "$WF" '[.[] | select(.workflowName == $wf)] | sort_by(.databaseId) | reverse' <<<"$SHA_RUNS")
    N_CAND=$(jq -r 'length' <<<"$CAND")

    if [[ "$N_CAND" == "0" ]]; then
        note_state "MISSING" "$WF" "$JB" "no run of workflow '$WF' for this commit"
        escalate NOTGREEN
        continue
    fi

    FOUND=0
    for (( c = 0; c < N_CAND; c++ )); do
        RID=$(jq -r --argjson c "$c" '.[$c].databaseId' <<<"$CAND")
        JOBS=$(gh run view "$RID" --repo "$REPO_SLUG" --json jobs 2>/dev/null) || {
            note_state "UNVERIFIED" "$WF" "$JB" "could not read jobs of run $RID"
            escalate UNVERIFIED; FOUND=1; break
        }
        jq -e '.jobs | type == "array"' <<<"$JOBS" >/dev/null 2>&1 || {
            note_state "UNVERIFIED" "$WF" "$JB" "unparseable job list for run $RID"
            escalate UNVERIFIED; FOUND=1; break
        }

        MATCHES=$(jq -c --arg jb "$JB" '[.jobs[] | select(.name == $jb)]' <<<"$JOBS")
        N_MATCH=$(jq -r 'length' <<<"$MATCHES")
        [[ "$N_MATCH" == "0" ]] && continue   # not in this attempt; try an older one

        # Two jobs with the same name inside one run: identity is ambiguous and
        # is never guessed.
        if (( N_MATCH > 1 )); then
            note_state "UNVERIFIED" "$WF" "$JB" "$N_MATCH jobs share this name in run $RID — ambiguous identity"
            escalate UNVERIFIED; FOUND=1; break
        fi

        ST=$(jq -r '.[0].status // "unknown"' <<<"$MATCHES")
        CO=$(jq -r '.[0].conclusion // ""' <<<"$MATCHES")
        FOUND=1

        if [[ "$ST" != "completed" ]]; then
            note_state "RUNNING" "$WF" "$JB" "status=$ST in run $RID"
            escalate RUNNING
            break
        fi

        case "$CO" in
            success)   note_state "SUCCESS"   "$WF" "$JB" "run $RID" ;;
            failure)   note_state "FAILED"    "$WF" "$JB" "run $RID"; escalate NOTGREEN ;;
            cancelled) note_state "CANCELLED" "$WF" "$JB" "run $RID"; escalate NOTGREEN ;;
            skipped)   note_state "SKIPPED"   "$WF" "$JB" "run $RID"; escalate NOTGREEN ;;
            # The remaining terminal conclusions GitHub documents. They are not
            # success, so they are not green; each keeps its raw conclusion in
            # the note so the reason stays diagnosable.
            timed_out|action_required|stale|neutral)
                       note_state "FAILED"    "$WF" "$JB" "run $RID, conclusion=$CO"; escalate NOTGREEN ;;
            "")        note_state "UNVERIFIED" "$WF" "$JB" "completed with no conclusion in run $RID"; escalate UNVERIFIED ;;
            # A conclusion this script does not know is not assumed to be bad OR
            # good — an unknown state is exactly what UNVERIFIED is for.
            *)         note_state "UNVERIFIED" "$WF" "$JB" "run $RID, unrecognised conclusion=$CO"; escalate UNVERIFIED ;;
        esac
        break
    done

    if (( ! FOUND )); then
        # The workflow ran for this commit but never contained this job — the
        # partial-matrix case. The run's own conclusion may well read "success".
        note_state "MISSING" "$WF" "$JB" "workflow '$WF' ran for this commit but contains no such job"
        escalate NOTGREEN
    fi
done

case "${WORST:-GREEN}" in
    GREEN)
        VERDICT="GREEN"
        REASON="all $N_REQ required job(s) succeeded for ${SHA:0:7}"
        emit "$GREEN_RC" ;;
    RUNNING)
        VERDICT="RUNNING"
        REASON="required CI has not finished for ${SHA:0:7} — not green yet"
        emit "$RUNNING_RC" ;;
    UNVERIFIED)
        VERDICT="UNVERIFIED"
        REASON="required CI could not be established for ${SHA:0:7} — this is not a pass"
        emit "$UNVERIFIED_RC" ;;
    *)
        VERDICT="NOT GREEN"
        REASON="at least one required job did not succeed for ${SHA:0:7}"
        emit "$NOTGREEN_RC" ;;
esac
