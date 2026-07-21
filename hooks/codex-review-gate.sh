#!/usr/bin/env bash
# codex-review-gate — PreToolUse hook for Claude Code (Bash)
#
# Machine gate for the owner's two-model AI workflow: before any commit-
# creating git command runs, the outgoing diff goes to Codex CLI for
# adversarial review. Findings block the commit ONCE — Claude adjudicates
# them (transparency rule: rejected findings must be reported to the owner)
# and a retry of the same diff passes. A changed diff is reviewed afresh.
#
# Drift-hunter: when /before left an approved plan for this repo AND it is
# FRESH (stamped base commit is an ancestor of HEAD, written within 24h),
# the review also hunts for DRIFT from that plan — missed steps, unapproved
# scope, silent changes — findings tagged [DRIFT]/[BUG]. A stale / mismatched
# / missing plan falls back to the generic correctness prompt and every
# outcome states "drift NOT checked" — a drift review that never read a plan
# must never be claimed.
#
# Round cap (two-brain-convergence.md "CAP-STOPPED", enforced by the machine,
# not prose): every reviewed-with-findings round for the same (repo, HEAD) is
# counted in a flock-guarded state file; each deny prints the round number and
# the finding-count trajectory. The reviewer must tag every finding with an
# IMPACT severity — MATERIAL = [data-loss]/[security]/[correctness]/untagged,
# MARGINAL = [edge]/[theoretical]. At round >= cap (default 3, override
# CODERV_GATE_ROUND_CAP) a review whose findings are ALL marginal is ALLOWED
# with a loud CAP-STOPPED caveat instead of denied; material findings keep
# denying, but the deny becomes an explicit owner-visible escalation and every
# later material deny at that (repo, HEAD) stays escalated (durable state).
# The counter has NO delete path — a landed commit moves HEAD (new key) and
# the 24h sweep reaps orphans — so there is no delete/append race to lose.
#
# Detects: commit / merge / cherry-pick / revert / rebase, including
# `git -C <dir>` and other global flags, at command position (quoted
# mentions like `echo "git commit"` do not trigger). Reviews the working-
# tree delta PLUS untracked files, so new-file-only commits are reviewed.
#
# Never blocks: non-commit commands, non-git dirs, empty diffs, docs-only
# diffs (*.md/*.txt), or an already-reviewed diff (hash of repo + HEAD +
# diff, cached 24h — an identical diff in another repo reviews afresh).
# Codex unavailable/auth lapsed/jq missing → commit is ALLOWED with a loud
# warning: never a silent skip, never a lockout of the owner's work.
#
# Accepted limitations (documented, by design):
# - A compound command that generates files and then commits reviews the
#   pre-command tree; PreToolUse cannot see the future tree.
# - A staged hunk whose worktree copy was reverted is missed when OTHER
#   files also changed (working-tree delta wins); the all-reverted case
#   falls back to the staged diff and is covered.
# - The diff is sent to OpenAI (Codex) for review — owner-accepted.
# - `cd $VAR` and paths beyond a leading ~ are not expanded; an
#   unresolvable dir falls back to the session cwd.
# - Commits wrapped in an interpreter (`sh -c 'git commit ...'`) are not
#   detected; quote scrubbing is heuristic — pathological mixed-quote
#   commands can slip past detection. Both fail open, never block.
# - merge / cherry-pick / revert / rebase integrate EXISTING commits the
#   gate cannot see. Clean worktree: loud "NOT reviewed" warning instead
#   of a silent skip. Dirty worktree: only the local delta is reviewed and
#   every outcome states the incoming commits are UNREVIEWED.
# - `--git-dir X` / `--work-tree X` forms are DETECTED, but dir resolution
#   for them falls back to cd/session cwd (Claude uses -C or cd; the
#   repo+HEAD+diff cache key keeps a wrong-repo review from being reused).
#
# Kill switch: CODERV_GATES_OFF=1 (all gates) or CODEX_REVIEW_OFF=1
#
# <!-- claude-docs-toolkit -->
set -o pipefail
export LC_ALL=C

# --- Live-loop event log (PURE side-effect) -------------------------------
# Appends one JSON object per line to loop-events.jsonl so the optional
# coderv-loop dashboard can stream the real Claude<->Codex exchange live.
# CONTRACT: this MUST NEVER influence the gate's allow/deny decision, never
# error the hook, and never write when jq is absent. Every call is wrapped so
# a failed write (full disk, bad perms) is swallowed — the gate outranks the
# log. Honour the same kill switches as the gate itself: no gate run, no log.
LOOP_LOG="${CODERV_LOOP_LOG:-$HOME/.claude/coderlap/loop-events.jsonl}"
log_event() {
    # log_event <actor> <type> <json-payload-object>   (payload defaults to {})
    [[ "${CODERV_LOG_OFF:-0}" == "1" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0
    local actor="$1" etype="$2" payload="${3:-{\}}"
    local line
    line=$(jq -cn --argjson ts "$(date +%s)" \
               --arg repo "${REPO_ID:-${DIR:-}}" \
               --arg actor "$actor" \
               --arg type "$etype" \
               --argjson payload "$payload" \
               '{ts:$ts, repo:$repo, actor:$actor, type:$type, payload:$payload}' 2>/dev/null) || return 0
    {
        mkdir -p "$(dirname "$LOOP_LOG")" 2>/dev/null || true
        # flock serialises concurrent gate runs so two large lines never
        # interleave (viewer relies on one valid JSON object per line). The
        # lock is BOUNDED (-w 1): a hung lock holder must never stall the
        # hook — the gate's pure-side-effect contract outranks log ordering.
        # On timeout (or no flock binary) fall through to a plain append; a
        # rare interleave is preferable to the gate blocking on its own log.
        # shellcheck disable=SC2016  # single quotes intentional: $1/$2 are bash -c positionals
        if command -v flock >/dev/null 2>&1 &&
           flock -w 1 "$LOOP_LOG.lock" bash -c 'printf "%s\n" "$1" >> "$2"' _ "$line" "$LOOP_LOG"; then
            :
        else
            printf '%s\n' "$line" >> "$LOOP_LOG"
        fi
    } 2>/dev/null || true
    return 0
}

[[ "${CODERV_GATES_OFF:-0}" == "1" ]] && exit 0
[[ "${CODEX_REVIEW_OFF:-0}" == "1" ]] && exit 0

INPUT=$(cat)

# No jq = we cannot parse the command. Warn loudly on anything that even
# smells like a commit, never silently bypass the gate.
if ! command -v jq >/dev/null 2>&1; then
    if grep -Eq "commit|merge|cherry-pick|revert|rebase" <<<"$INPUT" 2>/dev/null; then
        printf '%s\n' '{"systemMessage":"⚠ codex-review-gate: jq missing — commit NOT reviewed","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"CODEX REVIEW SKIPPED (jq is not installed, the gate cannot parse commands). Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."}}'
    fi
    exit 0
fi

CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[[ -z "$CMD" ]] && exit 0

# Commit detection: a git invocation at command position (start of command,
# or after ; & | ( ` or newline, optionally behind VAR=val env prefixes)
# whose subcommand — after global flags like -C <dir> / -c k=v (space or
# attached form) / --long-opt — creates commits. Quoted strings are
# scrubbed first (double then single: contractions like "don't" live in
# double quotes) so `echo "git commit"` and commit messages never trigger.
NL=$'\n'
SCRUBBED=$(sed -e 's/"[^"]*"/QUOTED/g' -e "s/'[^']*'/QUOTED/g" <<<"$CMD")
ENVPFX="([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*"
# Git global flags: -C / -c (space or attached form), value-taking long
# flags in BOTH --flag=v and --flag v forms (enumerated from git's own
# global list), and generic boolean/=-form long flags. GFLAG_NC is the
# same set minus -C, used by GITC_RE to locate the -C itself.
VLONG="--(git-dir|work-tree|namespace|super-prefix|config-env)([[:space:]]+|=)[^[:space:]]+"
GFLAG="(-C[[:space:]]*[^[:space:]]+|-c[[:space:]]*[^[:space:]]+|${VLONG}|--[[:alnum:]][[:alnum:]-]*(=[^[:space:]]*)?)"
GFLAG_NC="(-c[[:space:]]*[^[:space:]]+|${VLONG}|--[[:alnum:]][[:alnum:]-]*(=[^[:space:]]*)?)"
SUBCMDS="(commit|merge|cherry-pick|revert|rebase)"
GIT_RE="(^|[;&|(\`${NL}])[[:space:]]*${ENVPFX}(command[[:space:]]+)?git([[:space:]]+${GFLAG})*[[:space:]]+${SUBCMDS}([[:space:]]|\$|[;&|)])"
[[ "$SCRUBBED" =~ $GIT_RE ]] || exit 0
SUBCMD="${BASH_REMATCH[9]}"

# Repo dir candidates, best first: a `-C <dir>` on the commit-creating
# git invocation ITSELF (the -C must sit in the same invocation as the
# subcommand — `git -C /other status && git commit` does NOT supply the
# dir; global flags like `-c k=v` / --long-opts may surround `-C`), then
# a leading `cd <dir>`, then the session cwd. First candidate that IS a
# git repo wins; none = nothing to review. A compound command committing
# in SEVERAL repos reviews only the first matched invocation's repo —
# accepted limitation, same class as the sh -c wrapper.
GITC_RE="(^|[;&|(\`${NL}])[[:space:]]*${ENVPFX}(command[[:space:]]+)?git([[:space:]]+${GFLAG_NC})*[[:space:]]+-C[[:space:]]*(\"[^\"]+\"|\'[^\']+\'|[^\&\;\|[:space:]]+)([[:space:]]+${GFLAG_NC})*[[:space:]]+${SUBCMDS}([[:space:]]|\$|[;&|)])"
C_GITC=""; C_CD=""
if [[ "$CMD" =~ $GITC_RE ]]; then
    C_GITC="${BASH_REMATCH[9]//[\"\']/}"
    C_GITC="${C_GITC/#\~/$HOME}"
fi
if [[ "$CMD" =~ ^[[:space:]]*cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^\&\;\|[:space:]]+) ]]; then
    C_CD="${BASH_REMATCH[1]//[\"\']/}"
    C_CD="${C_CD/#\~/$HOME}"
fi
DIR=""
for CAND in "$C_GITC" "$C_CD" "$(jq -r '.cwd // empty' <<<"$INPUT")"; do
    [[ -n "$CAND" && -d "$CAND" ]] || continue
    if git -C "$CAND" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        DIR="$CAND"; break
    fi
done
[[ -n "$DIR" ]] || exit 0

allow_with_warning() {
    jq -n --arg msg "$1" --arg ctx "$2" '{
        systemMessage: $msg,
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
}

# Publish a cache marker ATOMICALLY: write to a temp file in the SAME dir, then
# rename over the target. A plain `printf > $CACHE/$HASH` is not atomic — a
# concurrent identical retry taking the cache fast-path could `cat` a
# half-written marker and mis-parse the outcome. The rename is atomic on the
# same filesystem, so a reader sees either the old marker or the complete new
# one, never a torn one. A failed write leaves no marker (the retry re-reviews,
# the safe direction) rather than a truncated one; the temp file is cleaned up.
write_marker() {
    # write_marker <marker-file-path> <content>
    local mf="$1" content="$2" tmp
    tmp=$(mktemp "${mf}.tmp.XXXXXX" 2>/dev/null) || return 1
    if printf '%s' "$content" > "$tmp" 2>/dev/null && mv -f "$tmp" "$mf" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# Publish a round-bearing marker under the per-hash lock, MONOTONICALLY: never
# overwrite a marker that already records a HIGHER round (a later/higher-priority
# outcome must not be downgraded by an earlier round finishing late). lgtm has no
# round and is published directly (an LGTM'd diff is a fresh diff/hash anyway, so
# it never contends with a denied/cap_stopped marker at the same hash). Falls
# back to a plain atomic write when flock is unavailable — the same degrade the
# rounds counter uses, and the round append it pairs with was itself skipped, so
# there is no higher-round marker to protect.
publish_round_marker() {
    # publish_round_marker <marker-file-path> <content> <this-round>
    local mf="$1" content="$2" this="$3"
    command -v flock >/dev/null 2>&1 || { write_marker "$mf" "$content"; return $?; }
    # shellcheck disable=SC2016  # single quotes intentional: $1..$3 are bash -c positionals
    flock -w 2 "$mf.lock" bash -c '
        mf="$1"; content="$2"; this="$3"
        cur=0
        if [ -f "$mf" ]; then
            m=$(cat "$mf" 2>/dev/null)
            case "$m" in
                denied\ round=*|cap_stopped\ round=*)
                    r=${m#* round=}; r=${r%% *}
                    case "$r" in ""|*[!0-9]*) cur=0 ;; *) cur=$(( 10#$r )) ;; esac ;;
            esac
        fi
        [ "$this" -lt "$cur" ] && exit 0   # a higher round already published — keep it
        tmp=$(mktemp "$mf.tmp.XXXXXX") || exit 1
        printf "%s" "$content" > "$tmp" && mv -f "$tmp" "$mf" || { rm -f "$tmp"; exit 1; }
    ' _ "$mf" "$content" "$this" 2>/dev/null
}

# What is about to be committed: PreToolUse fires before any `git add` in
# the same command runs, so review the full working-tree delta, not just
# the staged part — PLUS untracked files, which `git diff HEAD` misses.
DIFF=$(git -C "$DIR" diff HEAD 2>/dev/null)
[[ -z "$DIFF" ]] && DIFF=$(git -C "$DIR" diff --cached 2>/dev/null)  # unborn HEAD / all-reverted worktree
UNTRACKED=$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null)
if [[ -n "$UNTRACKED" ]]; then
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        UDIFF=$(git -C "$DIR" diff --no-index -- /dev/null "$f" 2>/dev/null)
        [[ -n "$UDIFF" ]] && DIFF+=$'\n'"$UDIFF"
    done <<<"$UNTRACKED"
fi
# Empty diff: a plain commit has nothing outgoing to review — silent
# allow. But merge/cherry-pick/revert/rebase on a clean worktree are
# about to CREATE commits from history the gate never sees; that must
# be loud, never a silent skip.
if [[ -z "${DIFF//[[:space:]]/}" ]]; then
    [[ "$SUBCMD" == "commit" ]] && exit 0
    allow_with_warning \
        "⚠ codex-review-gate: git $SUBCMD NOT reviewed (no worktree diff — incoming commits unseen)" \
        "CODEX REVIEW SKIPPED: 'git $SUBCMD' integrates existing commits, and with a clean worktree the gate has no outgoing diff to review — the commits it brings in are NOT reviewed. Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."
fi

# Docs-only commits flow freely (a SESSIONS.md handoff must never wait).
DOCS_ONLY=1
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" =~ \.(md|txt)$ ]] || { DOCS_ONLY=0; break; }
done < <({ git -C "$DIR" diff HEAD --name-only 2>/dev/null;
           git -C "$DIR" diff --cached --name-only 2>/dev/null;
           printf '%s\n' "$UNTRACKED"; } | sort -u)
[[ "$DOCS_ONLY" == "1" ]] && exit 0

# One review per unique (repo, HEAD, diff): the retry after adjudication
# passes; any tree change, new commit, or DIFFERENT repo with an identical
# diff produces a new hash and a fresh review.
REPO_ID=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
BASE=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo unborn)
HASH=$(sha256sum <<<"${REPO_ID}@${BASE}${NL}${DIFF}" | cut -d' ' -f1)
CACHE="$HOME/.claude/coderlap/codex-reviewed"
mkdir -p "$CACHE"
# Sweep expired cache state. .lock files are NEVER deleted: flock does not
# bump mtime on acquisition, so a held lock could be unlinked and a second
# gate would lock a fresh inode — two "exclusive" critical sections at once
# (locks are empty; leaving them costs bytes, reaping them costs atomicity).
# rounds-* DATA files are deleted only WHILE HOLDING their lock, with the age
# re-checked inside the critical section — an unlocked delete could race a
# concurrent locked append and lose rounds.
find "$CACHE" -maxdepth 1 -type f ! -name '*.lock' -mmin +1440 2>/dev/null |
while IFS= read -r swept; do
    case "$swept" in
        */rounds-*)
            command -v flock >/dev/null 2>&1 || continue
            # shellcheck disable=SC2016  # single quotes intentional: $1 is a bash -c positional
            flock -w 1 "$swept.lock" bash -c \
                '[ -n "$(find "$1" -maxdepth 0 -mmin +1440 2>/dev/null)" ] && rm -f "$1"' \
                _ "$swept" 2>/dev/null || true
            ;;
        *) rm -f "$swept" 2>/dev/null ;;
    esac
done
# Round-cap parameters + state location (two-brain-convergence.md CAP-STOPPED)
# are computed HERE, before the cache fast-path, because both paths need them:
# the fresh-review decision below, and the cached retry — which must stay LOUD
# when it rides over an unresolved cap escalation.
CAP="${CODERV_GATE_ROUND_CAP:-3}"
[[ "$CAP" =~ ^[1-9][0-9]*$ ]] || CAP=3
CANON_REPO=$(readlink -f "$REPO_ID" 2>/dev/null) || CANON_REPO="$REPO_ID"
ROUNDS_FILE="$CACHE/rounds-$(sha256sum <<<"${CANON_REPO}@${BASE}" | cut -d' ' -f1)"
# Already reviewed once (the adjudicate-then-retry of an IDENTICAL diff): the
# commit is allowed to proceed. Log the successful retry so the dashboard
# shows the loop closing — without it, the viewer would freeze on the denial
# and never show the commit landing. REPO_ID isn't computed yet on this early
# path, so stamp repo from DIR.
if [[ -f "$CACHE/$HASH" ]]; then
    REPO_ID=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
    # Emit the writer's beat before the cached outcome so a same-diff retry
    # still shows a commit_attempt (wire-pulse) on the dashboard — without it
    # the retry would land with no visible writer turn, only a bare outcome.
    log_event claude commit_attempt "$(jq -cn \
        --arg sub "$SUBCMD" --argjson bytes "${#DIFF}" \
        '{subcmd:$sub, diff_bytes:$bytes, cached:true}')"
    # The cached decision is read from the marker's OWN recorded outcome —
    # never inferred from the repo/HEAD-wide round state, which may describe
    # a DIFFERENT diff (an LGTM'd diff must not be denied because an earlier
    # diff at this HEAD escalated, and a CAP-STOPPED allow must keep its
    # caveat on retry). This is a CLOSED classifier: markers are written per
    # terminal path in exactly these schemas —
    #   "lgtm" | "cap_stopped round=N findings=M" | "denied round=N material=M"
    # An empty/legacy marker reads as a plain reviewed-ok pass. Anything ELSE —
    # a torn write, a truncated marker, an unrecognised token — is NOT allowed
    # to fall through to a pass: it is treated as an open escalation and DENIED
    # (the same conservative direction as an unparseable "denied" record). The
    # branch patterns are ANCHORED to the full schema so a marker that merely
    # starts with "denied"/"cap_stopped" but has a garbled tail cannot slip in
    # with a mis-parsed round/material count.
    # Read the marker in ONE operation that captures exact bytes AND read
    # success with NO second, raceable syscall. The sentinel 'X' is appended
    # inside the SAME command substitution but ONLY when `cat` SUCCEEDS (`&&`),
    # so the sentinel doubly serves as (a) the success flag and (b) a guard that
    # command substitution's trailing-newline stripping cannot collapse a real
    # marker to "". After the run:
    #   - RAW ends in X  → cat succeeded; BODY (RAW without the trailing X) is the
    #                      exact marker bytes: "" (real empty → legacy pass),
    #                      "lgtm"/schema (classified), or garbage (→ deny).
    #   - RAW lacks X    → cat FAILED (unreadable/absent) → open escalation deny.
    # No stat, no `-r` probe — there is no TOCTOU window and no GNU-stat dep.
    RAW=$(cat "$CACHE/$HASH" 2>/dev/null && printf 'X')
    MARKER_READ_OK=0; MARKER_STATE=""
    if [[ "$RAW" == *X ]]; then
        MARKER_READ_OK=1; MARKER_STATE="${RAW%X}"   # cat succeeded; exact bytes
    fi
    # RAW without a trailing X ⇒ cat failed ⇒ MARKER_READ_OK stays 0 ⇒ deny.
    CAP_RIDE=0; R_UNVERIFIED=0; R_ROUND=0; R_MAT=0
    if (( ! MARKER_READ_OK )); then
        # marker present but unreadable → open escalation (never a fall-through
        # pass). Handled by the CAP_RIDE deny below with the unverified wording.
        CAP_RIDE=1; R_UNVERIFIED=1
    else
    case "$MARKER_STATE" in
        ""|lgtm)
            # reviewed-ok (or legacy 0-byte marker): plain pass, handled below.
            :
            ;;
        "cap_stopped round="*" findings="*)
            # A valid cap_stopped marker is "cap_stopped round=<int> findings=<int>",
            # AND it must satisfy the same INVARIANTS the gate enforces when it
            # writes one: round >= CAP and findings > 0 (a cap-stopped allow only
            # happens at/after the cap with at least one open marginal finding).
            # Checking only the numeric SHAPE would let a corrupt but shape-valid
            # marker like "cap_stopped round=0 findings=0" bypass the gate; the
            # invariant check routes such a marker to the unverified deny instead.
            # 10# forces base-10 so a leading-zero field (e.g. round=08) is not
            # read as octal — a bare (( 08 >= CAP )) is an arithmetic ERROR that
            # would leave CAP_RIDE=0 and wrongly allow the retry. Same guard as
            # the finding-anchor extraction below (line ~788).
            if [[ "$MARKER_STATE" =~ ^cap_stopped\ round=([0-9]+)\ findings=([0-9]+)$ ]] \
               && (( 10#${BASH_REMATCH[1]} >= CAP )) && (( 10#${BASH_REMATCH[2]} > 0 )); then
                log_event system outcome "$(jq -cn '{result:"passed", cached:true, cap_stopped:true}')"
                allow_with_warning \
                    "⚠ codex-review-gate: retry of a CAP-STOPPED diff ALLOWED — its marginal findings still stand" \
                    "This identical diff was previously allowed at the round cap with MARGINAL findings open ($MARKER_STATE). The retry does not resolve them: surface those findings to the owner alongside this commit (transparency rule — never silently dropped)."
            else
                # cap_stopped prefix but malformed tail OR invariant-violating
                # counts: do NOT auto-allow a garbled/impossible allow-marker —
                # fall to the unknown-marker deny below.
                CAP_RIDE=1; R_UNVERIFIED=1
            fi
            ;;
        "denied round="*" material="*)
            if [[ "$MARKER_STATE" =~ ^denied\ round=([0-9]+)\ material=([0-9]+)$ ]]; then
                # 10# forces base-10 so a leading-zero field (round=08) is not
                # parsed as octal — a bare (( 08 >= CAP )) is an arithmetic error
                # that would leave CAP_RIDE=0 and wrongly allow the retry.
                R_ROUND=$(( 10#${BASH_REMATCH[1]} )); R_MAT=$(( 10#${BASH_REMATCH[2]} ))
                # Validate the denial INVARIANTS, not just the shape: a real
                # denied marker always has round >= 1, and a denial recorded at
                # or above the cap always has material > 0 (an at-cap deny is by
                # definition a material escalation). An impossible combination
                # (round=0, or round>=CAP with material=0) is a torn/forged
                # record — route it to the unverified deny, never a fall-through
                # allow that would skip the mandatory escalation.
                if (( R_ROUND < 1 )) || { (( R_ROUND >= CAP )) && (( R_MAT == 0 )); }; then
                    CAP_RIDE=1; R_UNVERIFIED=1
                elif (( R_ROUND >= CAP && R_MAT > 0 )); then
                    CAP_RIDE=1
                fi
            else
                # denied prefix but malformed tail = open escalation: deny
                # unless the owner explicitly overrides.
                CAP_RIDE=1; R_UNVERIFIED=1
            fi
            ;;
        *)
            # Unknown / torn / truncated marker: never a fall-through allow.
            # Treated as an open escalation (conservative) — the owner override
            # is the only in-band pass, same as an unparseable denial.
            CAP_RIDE=1; R_UNVERIFIED=1
            ;;
    esac
    fi   # MARKER_READ_OK
    if (( CAP_RIDE )); then
        # An open (or unverifiable) CAP-REACHED escalation is NOT cleared by
        # an identical retry. The ONLY in-band pass is the owner's explicit
        # override signal — an agent must never set it on its own judgment.
        # This is the owner-override mechanism the durable escalation state
        # requires: machine-checkable, loud, and attributable to the human.
        if [[ "${CODERV_GATE_OWNER_OVERRIDE:-0}" == "1" ]]; then
            log_event system outcome "$(jq -cn --argjson unv "$R_UNVERIFIED" \
                '{result:"passed", cached:true, over_cap_escalation:true, owner_override:true, state_unverified:($unv==1)}')"
            allow_with_warning \
                "⚠ codex-review-gate: OWNER OVERRIDE (CODERV_GATE_OWNER_OVERRIDE=1) — commit allowed over a CAP-REACHED escalation ($R_MAT material finding(s) open at round $R_ROUND$( ((R_UNVERIFIED)) && printf '%s' '; state unverified' ))" \
                "The owner explicitly overrode an open CAP-REACHED escalation for this identical diff. The material findings remain unresolved by this commit and must be surfaced alongside it (transparency rule — never silently dropped)."
        fi
        log_event system outcome "$(jq -cn --argjson unv "$R_UNVERIFIED" \
            '{result:"denied", cached:true, over_cap_escalation:true, state_unverified:($unv==1)}')"
        R_WHY="$R_MAT material finding(s) open at round $R_ROUND"
        (( R_UNVERIFIED )) && R_WHY="this diff's cache record is unreadable or could not be parsed — treated as an open escalation (conservative)"
        jq -n --arg r "CAP-REACHED escalation is still OPEN for this repo@HEAD ($R_WHY). An identical-diff retry does NOT clear it. Options: fix the material findings (a changed diff gets a fresh review), or the OWNER explicitly overrides by re-running this exact commit with CODERV_GATE_OWNER_OVERRIDE=1 — the override is the owner's in-band decision signal; never set it on your own judgment." \
              --arg msg "⛔ codex-review-gate: identical retry DENIED — CAP-REACHED escalation open ($R_WHY); owner override: CODERV_GATE_OWNER_OVERRIDE=1" '{
            systemMessage: $msg,
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: $r
            }
        }'
        exit 0
    fi
    log_event system outcome "$(jq -cn '{result:"passed", cached:true}')"
    exit 0
fi

# Fail LOUD, not shut: a broken reviewer must never lock the owner out.
command -v codex >/dev/null 2>&1 || allow_with_warning \
    "⚠ codex-review-gate: codex CLI not found — commit NOT reviewed" \
    "CODEX REVIEW SKIPPED (codex CLI missing). Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."
codex login status >/dev/null 2>&1 || allow_with_warning \
    "⚠ codex-review-gate: codex auth lapsed — commit NOT reviewed" \
    "CODEX REVIEW SKIPPED (auth lapsed; owner must run: codex login --device-auth). Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."

# Oversized diffs are reviewed only up to 150KB — that partial coverage is
# stated LOUDLY in every outcome; it must never read as a full review.
TRUNC_NOTE=""
if (( ${#DIFF} > 150000 )); then
    TRUNC_NOTE="⚠ diff exceeds 150KB — Codex reviewed ONLY the first 150KB; the tail is UNREVIEWED. Tell the owner; do not report this commit as fully reviewed."
fi

# History-integrating subcommands: even with a dirty tree, only the LOCAL
# worktree delta gets reviewed — the incoming commits are invisible to the
# gate. Every outcome must say so; a plain LGTM would be a lie.
HIST_NOTE=""
if [[ "$SUBCMD" != "commit" ]]; then
    HIST_NOTE="⚠ 'git $SUBCMD' integrates existing commits the gate cannot see — only the local worktree delta was reviewed; the incoming commits are UNREVIEWED. Tell the owner; do not report this as a fully reviewed operation."
fi

# Drift-hunter: when /before wrote an approved plan for THIS repo, the review
# hunts for DRIFT from that plan (missed steps, scope creep, silent changes)
# on top of the correctness pass. The spec is trusted ONLY if fresh — its
# stamped base commit is an ancestor of the current HEAD (the plan describes
# THIS line of work, not a stale branch) AND it was written within 24h. A
# stale / mismatched / missing spec falls back to the generic prompt and the
# review SAYS "drift not checked" in every outcome — a claimed drift review
# that never read a plan would be a lie (plan §2, §3; convergence doc: never
# claim a review that did not happen). Slug derivation mirrors /before and
# the /ship reviewer exactly (project root = nearest dir with CLAUDE.md).
SPEC_ROOT="$DIR"
while [[ "$SPEC_ROOT" != "/" && ! -f "$SPEC_ROOT/CLAUDE.md" ]]; do SPEC_ROOT=$(dirname "$SPEC_ROOT"); done
[[ -f "$SPEC_ROOT/CLAUDE.md" ]] || SPEC_ROOT="$DIR"
SPEC_FILE="$HOME/.claude/coderlap/specs/$(printf '%s' "$SPEC_ROOT" | tr '/' '-').md"
SPEC=""; DRIFT_NOTE=""
if [[ -f "$SPEC_FILE" ]]; then
    SPEC_BASE=$(sed -n 's/^Base:[[:space:]]*//p' "$SPEC_FILE" | head -1)
    SPEC_AGE=$(( $(date +%s) - $(stat -c %Y "$SPEC_FILE" 2>/dev/null || echo 0) ))
    if [[ -z "$SPEC_BASE" ]]; then
        DRIFT_NOTE="⚠ approved plan on file has no base commit stamp — drift NOT checked (reviewed for correctness only)."
    elif (( SPEC_AGE < 0 || SPEC_AGE > 86400 )); then
        # future mtime (clock skew / deliberately post-dated) is NOT fresh:
        # a negative age must never read as "within 24h".
        DRIFT_NOTE="⚠ approved plan on file is stale or has an invalid (future) timestamp — drift NOT checked (reviewed for correctness only)."
    elif ! git -C "$SPEC_ROOT" merge-base --is-ancestor "$SPEC_BASE" HEAD 2>/dev/null; then
        # Ancestor test runs in the SAME repo /before stamped Base: from — the
        # repo containing SPEC_ROOT, not $DIR. They coincide in the normal case
        # (CLAUDE.md at the git root); in a nested/monorepo layout where the two
        # diverge, checking $DIR's HEAD against a Base: stamped from another repo
        # would be meaningless — so the guard binds the check to SPEC_ROOT's repo
        # (an unresolvable/non-repo SPEC_ROOT makes this fail → "drift NOT checked",
        # the safe direction).
        DRIFT_NOTE="⚠ approved plan's base commit is not an ancestor of HEAD (plan describes different work) — drift NOT checked (reviewed for correctness only)."
    else
        SPEC=$(cat "$SPEC_FILE")
    fi
else
    DRIFT_NOTE="⚠ no approved plan on file (no /before spec for this repo) — drift NOT checked (reviewed for correctness only)."
fi

# Severity contract, shared by both prompt branches. The tags are defined by
# IMPACT, not likelihood — the cap below only ever auto-allows marginal-tagged
# findings, so a tag that lets a serious failure read as marginal would be a
# hole in the gate. The wording (incl. the "never tag as [edge]" rule) was
# co-designed with the reviewer model itself.
SEVERITY_RULES='Tag EVERY finding with exactly ONE impact severity in square
brackets, chosen by IMPACT, not likelihood:
  [data-loss]   = loss or corruption of user data.
  [security]    = confidentiality, integrity, authorization, or any other
                  security-guarantee failure.
  [correctness] = any reachable wrong user-visible or externally observable
                  result not covered by the two above.
  [edge]        = bounded, recoverable misbehavior on unlikely input.
  [theoretical] = proven unreachable under supported real-world execution
                  (not merely unlikely).
Never tag a reachable security, data-integrity, or wrong-result failure as
[edge], regardless of rarity, recoverability, or blast radius. A finding with
no severity tag is treated as material.
Place the severity tag at the VERY START of the finding, in the leading
bracket cluster (immediately after [BUG]/[DRIFT]) — a tag appearing only in
the body text does not count, and more than one severity tag on a finding is
treated as untagged.
The two groups and their consequences: MATERIAL = [data-loss] | [security] |
[correctness] | untagged — always blocks the commit, and escalates to the
owner once the round cap is reached. MARGINAL = [edge] | [theoretical] — may
be allowed-with-caveat once the round cap is reached.
Output ONLY the findings list — no preamble, no closing summary. Any prose
outside a list item is treated as one additional MATERIAL finding.'

if [[ -n "$SPEC" ]]; then
    PROMPT="You are the independent adversarial reviewer in a two-model workflow.
An approved plan was written by the other AI (Claude) BEFORE this diff. Review
the outgoing git diff on TWO axes: (1) DRIFT from the plan — steps missed,
scope added that the plan never approved, silent changes; and (2) correctness
bugs, edge cases, security, data integrity. Style nits do not count.

Do ONE EXHAUSTIVE pass: list EVERY real finding you can see NOW, tagging each
[DRIFT] or [BUG], most severe first. Do NOT hold a deeper issue back for a
later round — surfacing one finding per recommit wastes a converged retry and
lets real bugs hide behind cosmetic ones. If you can find it, report it now.
For each finding give file:line, the concrete failure scenario, and the fix.
$SEVERITY_RULES
If the diff faithfully implements the plan with no significant issue, reply
exactly: LGTM

--- APPROVED PLAN ---
$SPEC
--- END PLAN ---"
else
    PROMPT="You are the independent adversarial reviewer in a two-model workflow.
Review this outgoing git diff for correctness bugs, edge cases, security,
and data integrity. Style nits do not count.

Do ONE EXHAUSTIVE pass: list EVERY real finding you can see NOW, most severe
first. Do NOT hold a deeper issue back for a later round — surfacing one
finding per recommit wastes a converged retry and lets real bugs hide behind
cosmetic ones. If you can find it, report it now. For each finding give
file:line, the concrete failure scenario, and the fix.
$SEVERITY_RULES
If nothing significant, reply exactly: LGTM"
fi

# Live-loop: Claude has produced a diff and is attempting a commit; the
# reviewer is about to look at it. Emit both the writer's turn and the
# reviewer-started turn so the dashboard shows the hand-off.
log_event claude commit_attempt "$(jq -cn \
    --arg sub "$SUBCMD" --argjson bytes "${#DIFF}" \
    '{subcmd:$sub, diff_bytes:$bytes}')"
log_event codex review_started "$(jq -cn \
    --argjson bytes "${#DIFF}" \
    --argjson drift "$([[ -n "$SPEC" ]] && echo true || echo false)" \
    --argjson truncated "$([[ -n "$TRUNC_NOTE" ]] && echo true || echo false)" \
    '{diff_bytes:$bytes, drift_checked:$drift, truncated:$truncated}')"

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
# Stamp review wall-clock start so the verdict can carry how long Codex took —
# a pure side-effect for the dashboard, never read by the allow/deny logic.
REVIEW_START_MS=$(date +%s%3N 2>/dev/null)
[[ "$REVIEW_START_MS" =~ ^[0-9]+$ ]] || REVIEW_START_MS=""
printf '%s' "${DIFF:0:150000}" | timeout 180 codex exec --skip-git-repo-check \
    -s read-only -o "$OUT" "$PROMPT" >/dev/null 2>&1
RC=$?
REVIEW=$(cat "$OUT" 2>/dev/null); rm -f "$OUT"
# Elapsed ms (empty when the clock is unavailable — duration_ms is then emitted
# as JSON null, never a bogus 0). The key is always present so consumers read one
# stable shape (number | null) and never have to test for a missing field.
# `%s%3N` is GNU date; a non-numeric result (BSD date) leaves REVIEW_START_MS
# empty and duration_ms is null.
REVIEW_MS=""
if [[ -n "$REVIEW_START_MS" ]]; then
    NOW_MS=$(date +%s%3N 2>/dev/null)
    [[ "$NOW_MS" =~ ^[0-9]+$ ]] && REVIEW_MS=$(( NOW_MS - REVIEW_START_MS ))
    (( REVIEW_MS < 0 )) && REVIEW_MS=""   # clock skew guard — never a negative duration
fi
# Reusable jq arg pair: binds $dur to the real number, or JSON null when the
# clock was unavailable. An array (not a $(...) string) so the two tokens pass
# without relying on word-splitting — shellcheck-clean and quote-safe.
DUR_ARG=(--argjson dur "${REVIEW_MS:-null}")

if [[ $RC -ne 0 || -z "$REVIEW" ]]; then
    log_event system review_failed "$(jq -cn --argjson rc "$RC" '{rc:$rc}')"
    # The gate fails OPEN here (commit allowed unreviewed), so the loop is
    # over — emit a terminal outcome or the dashboard hangs on "reviewing…"
    # forever. Mark unreviewed:true so it never reads as a passed review.
    log_event system outcome "$(jq -cn '{result:"passed", unreviewed:true}')"
    allow_with_warning \
        "⚠ codex-review-gate: review failed (rc=$RC) — commit NOT reviewed" \
        "CODEX REVIEW FAILED (exit $RC, possibly a timeout). Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."
fi

# NOTE: the review-cache marker is published PER TERMINAL PATH (in the LGTM
# branch below, and after the rounds append for the findings paths) — never
# up front. Publishing it before the rounds append opens a window where a
# concurrent identical attempt takes the cached fast path against stale
# round state and passes without the mandatory escalation caveat.

if [[ "$REVIEW" =~ ^[[:space:]]*LGTM[[:space:].!]*$ ]]; then
    write_marker "$CACHE/$HASH" 'lgtm'
    log_event codex verdict "$(jq -cn "${DUR_ARG[@]}" '{verdict:"lgtm", findings:0, duration_ms:$dur}')"
    log_event system outcome "$(jq -cn '{result:"passed"}')"
    MSG="✓ Codex review: LGTM"
    CTX="Codex adversarial review of this diff: LGTM (no findings)."
    if [[ -n "$TRUNC_NOTE" ]]; then
        MSG="✓ Codex review: LGTM (first 150KB only — tail UNREVIEWED)"
        CTX="Codex reviewed ONLY the first 150KB of this oversized diff: LGTM on that part; the remainder was NOT reviewed. $TRUNC_NOTE"
    fi
    if [[ -n "$HIST_NOTE" ]]; then
        MSG+=" — git $SUBCMD: incoming commits UNREVIEWED"
        CTX+=" $HIST_NOTE"
    fi
    if [[ -n "$DRIFT_NOTE" ]]; then
        CTX+=" $DRIFT_NOTE"
    fi
    jq -n --arg msg "$MSG" --arg ctx "$CTX" '{
        systemMessage: $msg,
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

# The reviewer found problems. Findings are parsed BEFORE the allow/deny
# decision because the round cap below reads their severities. The failure
# direction of parsing is DENY: the cap is only ever unlocked by successfully
# parsed, all-marginal findings — a parse failure just leaves the gate as
# strict as it was before the cap existed. The dashboard events stay pure
# side-effects.
# A finding STARTS at a top-level marker: a number (`N.`/`N)`, any indent) or
# a bullet (`-`/`*`) at COLUMN 0. An INDENTED `-`/`*` is a nested evidence
# bullet and folds into its parent finding, not a new one (else nested bullets
# inflate the count and split findings). This regex is the single source of
# truth for both the count and the awk splitter below — they must match.
TOPMARK='^([[:space:]]*[0-9]+[.)]|[-*])[[:space:]]'
FINDING_COUNT=$(grep -cE "$TOPMARK" <<<"$REVIEW" 2>/dev/null)
[[ "$FINDING_COUNT" =~ ^[0-9]+$ ]] || FINDING_COUNT=0
# NUL-delimited findings are read STRAIGHT into the array — never captured
# in $(...), which strips NUL bytes and would merge every finding into one.
FINDINGS=()
if (( FINDING_COUNT > 0 )); then
    while IFS= read -r -d '' fitem; do
        [[ -z "${fitem//[[:space:]$'\n']/}" ]] && continue
        FINDINGS+=("$fitem")
    done < <(awk '
        /^([[:space:]]*[0-9]+[.)]|[-*])[[:space:]]/ {
            if (buf != "") printf "%s\0", buf
            sub(/^([[:space:]]*[0-9]+[.)]|[-*])[[:space:]]+/, "")
            buf = $0; next
        }
        { if (buf != "") buf = buf "\n" $0 }
        END { if (buf != "") printf "%s\0", buf }
    ' <<<"$REVIEW" 2>/dev/null)
fi

# Severity per finding — the IMPACT tags the prompt demands. MATERIAL =
# data-loss | security | correctness | untagged/unrecognized (a reviewer that
# forgets the tag must never unlock the cap). MARGINAL = edge | theoretical.
# Only the LEADING bracket-tag cluster of the finding's first line counts —
# a finding whose EVIDENCE quotes a literal "[edge]" further along must stay
# untagged/material, and per the prompt exactly ONE severity is legal: zero
# or multiple severities in the cluster classify material too.
sev_label() {
    local first t sev="" n=0
    first=${1%%$'\n'*}
    first=$(tr '[:upper:]' '[:lower:]' <<<"$first")
    first=${first#"${first%%[![:space:]]*}"}   # ltrim
    first=${first#\*\*}                        # tolerate a leading bold marker
    while [[ "$first" =~ ^\[([a-z-]+)\][[:space:]]*(.*)$ ]]; do
        t="${BASH_REMATCH[1]}"; first="${BASH_REMATCH[2]}"
        case "$t" in
            data-loss|security|correctness|edge|theoretical)
                sev="$t"; n=$(( n + 1 )) ;;
            *) ;;   # non-severity tags ([bug]/[drift]/…) just pass through
        esac
    done
    if (( n == 1 )); then printf '%s' "$sev"; else printf 'untagged'; fi
}
MATERIAL_COUNT=0; SEV_SUMMARY=""
for fitem in "${FINDINGS[@]}"; do
    lbl=$(sev_label "$fitem")
    case "$lbl" in
        edge|theoretical) ;;
        *) MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 )) ;;
    esac
    SEV_SUMMARY+="${SEV_SUMMARY:+,}$lbl"
done
# A prose reply with no parseable list is ONE unclassifiable finding: material.
if (( ${#FINDINGS[@]} == 0 )); then
    FINDING_COUNT=1; MATERIAL_COUNT=1; SEV_SUMMARY="prose-unparsed"
else
    # Prose BEFORE the first list marker escapes the splitter — and would
    # otherwise escape severity classification too, letting a material
    # finding written as preamble slip past the cap unlock. The prompt
    # forbids preambles; a violation classifies MATERIAL (the conservative
    # direction — here the failure direction of loose parsing would be
    # ALLOW, so unparsed prose must always count against the cap).
    PREAMBLE=$(awk '/^([[:space:]]*[0-9]+[.)]|[-*])[[:space:]]/{exit} {print}' <<<"$REVIEW")
    if [[ -n "${PREAMBLE//[[:space:]$'\n']/}" ]]; then
        # Counted in BOTH totals — logs, trajectory, and owner messages must
        # report the real number of open findings, unparsed prose included.
        FINDING_COUNT=$(( FINDING_COUNT + 1 ))
        MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
        SEV_SUMMARY+="${SEV_SUMMARY:+,}preamble-unparsed"
    fi
fi

# --- Round cap state append (CAP/CANON_REPO/ROUNDS_FILE set above, before
# the cache fast-path). One line per reviewed-with-findings round for this
# (repo, HEAD): "<finding_count> <material_count> <severity summary>". Key is
# the CANONICAL repo path + HEAD — per-session keys would let a fresh session
# reset the cap (a bypass), and distinct worktrees already resolve to
# distinct toplevels. Read + append happen inside ONE bounded flock critical
# section: per-append locking alone would let two concurrent reviews compute
# the same round number. Lock/flock failure leaves ROUND empty → the strict
# pre-cap behaviour (deny with findings), never a cap unlock. No delete path:
# HEAD movement orphans the file and the 24h sweep above reaps it.
ROUND=""; TRAJECTORY=""
if command -v flock >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # single quotes intentional: $1/$2 are bash -c positionals
    # Round number and trajectory are computed from SCHEMA-VALID lines only
    # ("<count> <material> <summary>") — a corrupt or torn record can neither
    # inflate the round toward the cap nor smuggle text into the trajectory.
    # set -e inside the critical section: a failed append (disk full, bad
    # perms) MUST abort before the round number / trajectory are emitted — a
    # half-done append that still printed "prior+1" would advance the cap off a
    # file that never got this round's line. On abort bash -c exits non-zero,
    # ROUNDS_OUT has no "|", ROUND stays empty → strict pre-cap deny (safe).
    # `grep -c` exits 1 on zero matches (an empty/fresh file) — NOT an error —
    # so it is guarded with `|| :` to keep set -e from tripping on it.
    # The schema regex is anchored to a FULL valid line ("<count> <material>
    # <non-space summary>", end-anchored with $) in BOTH the counter (grep) and
    # the trajectory (awk). This anchoring also neutralizes the only realistic
    # torn record: if a PRIOR crashed append left a newline-less final line,
    # this run's `>>` merges it with the new record onto one physical line
    # ("2 0 edge3 0 edge") — a malformed multi-token tail the end-anchored regex
    # REJECTS. That round is simply not counted (an UNDERCOUNT — the safe
    # direction; it can never prematurely reach the cap), never a corrupt count.
    # A plain guarded append is therefore sufficient; no rewrite/rename needed
    # (a rewrite would change the failure semantics vs. a plain append and
    # reintroduce a verbatim-copy newline-merge bug).
    # shellcheck disable=SC2016  # single quotes intentional: $1/$2 are bash -c positionals
    # grep -c exits 1 on ZERO matches (an empty/fresh file) — expected, mapped to
    # prior=0 — but exits >1 on a real error (unreadable file). awk exits >0 on a
    # read/processing error. A blanket `|| :` would swallow BOTH, letting a bad
    # read emit a numbered round off a wrong count / blank trajectory. Instead
    # each is wrapped in a helper that maps grep's status-1 to a "0" result but
    # RE-RAISES any status >1 (and any awk failure) so set -e aborts → ROUND
    # empty → the tracking-unavailable deny, never a bogus round.
    ROUNDS_OUT=$(flock -w 2 "$ROUNDS_FILE.lock" bash -c '
        set -e
        f="$1"; line="$2"
        prior=0
        if [ -f "$f" ]; then
            # grep: rc 0 = matches, rc 1 = no matches (→0), rc>1 = error (abort)
            prior=$(grep -cE "^[0-9]+ [0-9]+ [^[:space:]]+$" "$f" 2>/dev/null) \
                || { rc=$?; [ "$rc" -eq 1 ] && prior=0 || exit "$rc"; }
        fi
        case "$prior" in ""|*[!0-9]*) prior=0 ;; esac
        printf "%s\n" "$line" >> "$f"
        # awk: any nonzero status is a genuine failure here (the program itself
        # never exits nonzero) → abort under set -e rather than a blank trajectory
        traj=$(awk "/^[0-9]+ [0-9]+ [^[:space:]]+\$/{printf \"%s%s\", sep, \$1; sep=\"->\"}" "$f")
        printf "%s|%s" "$(( prior + 1 ))" "$traj"
    ' _ "$ROUNDS_FILE" "$FINDING_COUNT $MATERIAL_COUNT $SEV_SUMMARY" 2>/dev/null)
    if [[ "$ROUNDS_OUT" == *"|"* ]]; then
        ROUND="${ROUNDS_OUT%%|*}"; TRAJECTORY="${ROUNDS_OUT#*|}"
        [[ "$ROUND" =~ ^[0-9]+$ ]] || { ROUND=""; TRAJECTORY=""; }
    fi
fi
# The cache marker for a findings verdict is written at each TERMINAL path
# below (cap-allow / deny), carrying that outcome — and only when the round
# append succeeded. A failed append publishes nothing: an identical retry
# must earn a fresh review rather than pass silently past state the gate
# never wrote.

log_event codex verdict "$(jq -cn --argjson n "$FINDING_COUNT" \
    --argjson mat "$MATERIAL_COUNT" --argjson round "${ROUND:-null}" \
    --arg traj "$TRAJECTORY" "${DUR_ARG[@]}" \
    '{verdict:"findings", findings:$n, material:$mat, round:$round, trajectory:$traj, duration_ms:$dur}')"
# Emit one event per finding so the dashboard can card each one. Wrapped
# evidence/remediation lines stay with their finding (the splitter above owns
# everything until the next top-level marker).
if (( ${#FINDINGS[@]} > 0 )); then
    for fitem in "${FINDINGS[@]}"; do
        ftag="note"
        [[ "$fitem" == *"[DRIFT]"* ]] && ftag="drift"
        [[ "$fitem" == *"[BUG]"* ]] && ftag="bug"
        # Best-effort file:line extraction for the dashboard's anchor chip —
        # the FIRST `path/with.ext:NNN` token in the finding. Purely additive:
        # when nothing matches, file/line are null and the viewer just shows
        # the finding without a chip. The extension must be a KNOWN SOURCE
        # extension (SRC_EXT below), not just any dotted token — otherwise
        # host:port and IP:port endpoints masquerade as anchors (127.0.0.1:3000
        # would parse as file "127.0.0.1" line 3000; example.com:8080 as
        # "example.com"). Restricting to real code extensions also keeps prose
        # like "12:30" (times) and "step 2:3" out.
        SRC_EXT='(js|mjs|cjs|jsx|ts|tsx|py|rb|go|rs|java|kt|c|h|cc|cpp|hpp|cs|php|swift|sh|bash|sql|json|ya?ml|toml|md|html?|css|scss|vue|svelte)'
        ffile=""; fline=""
        if [[ "$fitem" =~ ([A-Za-z0-9_./-]+\.${SRC_EXT}):([0-9]+) ]]; then
            ffile="${BASH_REMATCH[1]}"
            # Base-10 normalise so a leading-zero line (e.g. foo.js:08) is a valid
            # JSON number for --argjson. jq 1.7 tolerates leading zeros, but 1.6
            # (and the JSON spec) reject them — a downloader on 1.6 would otherwise
            # get a jq error and a degraded finding event. 10# forces base-10 so
            # 08/09 never read as bad octal either. Group 3 is the line number —
            # SRC_EXT's own parens are group 2.
            fline=$(( 10#${BASH_REMATCH[3]} ))
        fi
        LINE_ARG=(--argjson line "${fline:-null}")
        log_event codex finding "$(jq -cn --arg tag "$ftag" --arg text "$fitem" \
            --arg file "$ffile" "${LINE_ARG[@]}" \
            '{tag:$tag, text:$text, file:(if $file=="" then null else $file end), line:$line}')"
    done
else
    # Codex replied in prose without a list — log the raw review so nothing is lost.
    log_event codex finding "$(jq -cn --arg tag "note" --arg text "$REVIEW" '{tag:$tag, text:$text}')"
fi

# --- CAP-STOPPED allow: round cap reached and EVERY finding is marginal ----
# The findings are not dismissed — they go to the owner verbatim, loudly; the
# commit just stops being hostage to edge/theoretical-only residue. Material
# findings never take this path, nor do unparsed/untagged ones (both count as
# material above), nor a failed round counter (ROUND empty).
if [[ -n "$ROUND" ]] && (( ROUND >= CAP )) && (( MATERIAL_COUNT == 0 )) && (( ${#FINDINGS[@]} > 0 )); then
    publish_round_marker "$CACHE/$HASH" "$(printf 'cap_stopped round=%s findings=%s' "$ROUND" "$FINDING_COUNT")" "$ROUND"
    log_event system cap_stopped "$(jq -cn --argjson round "$ROUND" \
        --argjson n "$FINDING_COUNT" --arg traj "$TRAJECTORY" \
        '{round:$round, findings:$n, trajectory:$traj}')"
    log_event system outcome "$(jq -cn --argjson n "$FINDING_COUNT" \
        --argjson round "$ROUND" --arg traj "$TRAJECTORY" \
        '{result:"passed", cap_stopped:true, findings:$n, round:$round, trajectory:$traj}')"
    CTX="CAP-STOPPED (round cap, enforced by the gate): review round
$ROUND reached the cap ($CAP) and EVERY open finding is MARGINAL
([edge]/[theoretical]) — the commit is ALLOWED with this caveat instead of
blocked. Findings trajectory: $TRAJECTORY. Surface ALL findings below to the
owner VERBATIM alongside the commit (transparency rule — never silently
dropped); the owner remains the arbiter and may still demand fixes.

$REVIEW"
    [[ -n "$TRUNC_NOTE" ]] && CTX+=$'\n\n'"$TRUNC_NOTE"
    [[ -n "$HIST_NOTE" ]] && CTX+=$'\n\n'"$HIST_NOTE"
    [[ -n "$DRIFT_NOTE" ]] && CTX+=$'\n\n'"$DRIFT_NOTE"
    allow_with_warning \
        "⚠ CAP-STOPPED: round $ROUND/$CAP — all $FINDING_COUNT open findings marginal; commit ALLOWED with caveat (findings go to the owner)" \
        "$CTX"
fi

# --- Deny. At round >= cap with material findings open, the deny becomes an
# explicit owner escalation (durable: the counter never resets at this HEAD,
# so every later material deny here stays escalated). Below the cap it is the
# normal adjudicate-and-retry message. Changed diffs always get fresh reviews
# — a genuinely fixed diff must be able to reach LGTM; the gate never
# hard-locks the owner's work.
CAP_ESCALATED=0
[[ -n "$ROUND" ]] && (( ROUND >= CAP )) && CAP_ESCALATED=1
# Record this diff's own outcome in its marker so a cached retry acts on
# THIS verdict (below-cap deny retries pass per the adjudicate-then-retry
# contract; at-cap material denies stay escalated). No round recorded → no
# marker → the retry re-reviews.
[[ -n "$ROUND" ]] && publish_round_marker "$CACHE/$HASH" "$(printf 'denied round=%s material=%s' "$ROUND" "$MATERIAL_COUNT")" "$ROUND"
if [[ -n "$ROUND" ]]; then
    ROUND_NOTE=" — round $ROUND of cap $CAP for this repo@HEAD; findings trajectory: $TRAJECTORY"
else
    # ROUND is empty whenever the round could not be recorded — flock missing,
    # lock timeout, OR a rounds-state I/O failure (a failed append / a grep or
    # awk error inside the locked section, which set -e turns into an aborted,
    # "|"-less ROUNDS_OUT). The cap is not applied this run in ANY of those
    # cases; the note must name all of them, not just flock, so the diagnosis is
    # never false. Carry the explicit "round unknown — trajectory unavailable"
    # literals so the owner-facing note reads unambiguously as a no-tracking run.
    ROUND_NOTE=" — round unknown — trajectory unavailable (round tracking unavailable this run: flock missing, lock timeout, or a rounds-state I/O failure); the round cap was NOT applied"
fi
if (( CAP_ESCALATED )); then
    log_event system cap_escalated "$(jq -cn --argjson round "$ROUND" \
        --argjson mat "$MATERIAL_COUNT" --arg traj "$TRAJECTORY" \
        '{round:$round, material:$mat, trajectory:$traj}')"
fi
log_event system outcome "$(jq -cn --argjson n "$FINDING_COUNT" \
    --argjson mat "$MATERIAL_COUNT" --argjson round "${ROUND:-null}" \
    --arg traj "$TRAJECTORY" --argjson esc "$CAP_ESCALATED" \
    '{result:"denied", findings:$n, material:$mat, round:$round, trajectory:$traj, cap_escalated:($esc==1)}')"

if (( CAP_ESCALATED )); then
    REASON="CAP-REACHED — ESCALATE TO THE OWNER (round $ROUND >= cap $CAP; findings trajectory: $TRAJECTORY).
$MATERIAL_COUNT of $FINDING_COUNT open finding(s) are MATERIAL
(data-loss/security/correctness/untagged), so this attempt is DENIED — and
the review loop is OVER. Do NOT fix-and-recommit again on your own judgment:
STOP and present the owner the findings below VERBATIM, plus the options (fix
the material findings / owner overrides the gate / park the work). The owner
decides; you do not spend another round. (After the owner decides: either the
material findings get fixed — a changed diff earns a fresh review — or the
OWNER re-runs this exact commit with CODERV_GATE_OWNER_OVERRIDE=1; the
explicit override passes with a loud caveat and is never yours to set.)
(two-brain-convergence.md: CAP-STOPPED.)

$REVIEW"
else
    REASON="CODEX ADVERSARIAL REVIEW (commit paused once, per the AI workflow rules)$ROUND_NOTE:

$REVIEW

Adjudicate ALL findings before committing anything. Fix every real one, then
retry with a SINGLE commit — do NOT fix one and re-commit, repeat: each recommit
is a fresh diff that earns a fresh review and can deny indefinitely (batch, don't
trickle). Reject a finding ONLY with parsed, machine-verified proof (the line
quoted, the command output) — never a hunch or a lazy grep; no proof means fix it
or escalate it, not dismiss it. Findings you reject MUST be listed to the owner
with that proof (transparency rule — never silently dropped). Then retry: this
exact diff will not be blocked again; a changed diff gets a fresh review.
STOP and surface to the owner when the SAME unresolved finding has been rejected
twice on substantially the same rationale (same underlying claim, same cited
evidence, no materially new code or facts) — that is a loop, not convergence; the
owner decides, you do not keep re-committing."
fi
[[ -n "$TRUNC_NOTE" ]] && REASON+=$'\n\n'"$TRUNC_NOTE"
[[ -n "$HIST_NOTE" ]] && REASON+=$'\n\n'"$HIST_NOTE"
[[ -n "$DRIFT_NOTE" ]] && REASON+=$'\n\n'"$DRIFT_NOTE"
if (( CAP_ESCALATED )); then
    # The escalation must be OWNER-visible, not only agent-context: a
    # systemMessage rides alongside the deny so the human sees the cap state
    # in the transcript without relying on the agent to relay it.
    jq -n --arg r "$REASON" \
        --arg msg "⛔ codex-review-gate CAP-REACHED: round $ROUND/$CAP, $MATERIAL_COUNT material finding(s) still open — owner decision required (trajectory: $TRAJECTORY)" '{
        systemMessage: $msg,
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $r
        }
    }'
else
    jq -n --arg r "$REASON" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $r
        }
    }'
fi
exit 0
