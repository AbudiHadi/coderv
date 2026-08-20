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
# Convergence (two-brain-convergence.md, enforced by the machine, not prose):
# every reviewed-with-findings round for the same (repo, HEAD) is counted in a
# flock-guarded state file; each deny prints the round number + finding-count
# trajectory. The reviewer tags every finding with an IMPACT severity — MATERIAL
# = [data-loss]/[security]/[correctness]/[compatibility]/[release-integrity]/
# untagged, MARGINAL = [edge]/[theoretical]/[hardening].
#
# ADR-028 practical-impact rule: every finding ALSO declares [blocker] or [debt].
# BLOCKER = a material impact on users, data, security/privacy, correctness,
# compatibility, or release integrity; DEBT = small/defensive/theoretical/
# cosmetic/low-probability. Only BLOCKERs deny; a debt-only review passes
# immediately and the reviewer is told to stop looking for smaller issues. The
# declaration is a CROSS-CHECK, never a lever: severity always wins (see the
# precedence block at the severity contract), so [debt] cannot demote a real
# defect and a category-less [blocker] still blocks as malformed. The ceiling
# STOPS the loop but no longer overrides a blocker.
#
# ADR-022 policy split — quality gate by default, deep security by opt-in:
# in DEFAULT mode the review is an ENGINEERING QUALITY GATE: realistic-impact
# defects (correctness/regression/data-loss/reachable security) block; exotic
# adversarially-crafted-input findings are tagged [hardening] and, together
# with [edge]/[theoretical], ALLOW IMMEDIATELY (round 1, not cap-gated) under
# the "Non-blocking debt" section — surfaced, never dropped.
# CODERV_GATE_SECURITY=1 (/ship --security) is the explicit deep-review mode:
# full adversarial brief, [hardening] blocks like material, and the cap-gated
# marginal semantics below apply unchanged.
#
# ADR-019 makes the loop self-terminate on GENUINE CONVERGENCE instead of
# escalating routine code to the human. Three inputs give Codex what a cold
# memoryless review lacks: (1) a per-(repo,HEAD) findings LEDGER fed back into
# the prompt so it stops re-raising resolved findings; (2) PROJECT CONTEXT — the
# review runs read-only FROM the repo cwd with the changed-file list, so Codex
# reads the real code and false findings die; (3) CONVERGENCE PRESSURE — a
# late-appearing finding is tagged [LATE] and "converged" is defined as LGTM
# with full context. Three round tiers:
#   - ROUND < CAP (default 3, CODERV_GATE_ROUND_CAP): ordinary retry-deny.
#   - CAP <= ROUND < ROUND_MAX (default 5, CODERV_GATE_ROUND_MAX) and cumulative
#     transmitted bytes < CODERV_GATE_DIFF_BUDGET (default 800000): marginal-only
#     ALLOWED-with-caveat; material still DENIES but WITHOUT owner escalation, so
#     the loop keeps converging with memory+context.
#   - CEILING (ROUND >= ROUND_MAX or byte budget exhausted, and >= CAP): the loop
#     self-terminates. ONLY a still-open [security]/[data-loss] finding BLOCKS
#     (a durable owner escalation — the gate refusing to auto-merge a security
#     hole); every other residue is ALLOWED-with-caveat, findings surfaced
#     verbatim. The denied marker carries an escalated={0,1} flag so an ordinary
#     deny retries but a ceiling security block stays escalated.
# The counter/ledger have NO delete path — a landed commit moves HEAD (new key)
# and the 24h sweep reaps orphans — so there is no delete/append race to lose.
# The ledger + project context are best-effort: any flock/IO failure degrades to
# the pre-ADR-019 cold review (empty prior block, diff-only) and never blocks.
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
# Owner authority (ADR-023): the owner is the FINAL authority — the gate
#   blocks autonomous agent decisions, never an explicit owner decision. When
#   the owner explicitly approves shipping a denied diff AS-IS (in-chat), the
#   decision is recorded per-diff and mechanically honoured:
#       codex-review-gate.sh --approve <repo-dir> "<the owner's words>"
#   keys the approval to the EXACT current outgoing diff; the identical commit
#   then passes immediately — outranking round cache, cap, ceiling and
#   security escalation — loudly, quoting the approval. Single-use (consumed
#   on the pass, swept after 24h if unused); any other diff reviews normally.
# Kill switch: CODERV_GATES_OFF=1 (all gates) or CODEX_REVIEW_OFF=1 — read
#   from Claude Code's own environment, which is FROZEN at session launch, so
#   they cannot be flipped mid-session. EMERGENCY mid-session switch
#   (secondary — prefer the per-diff --approve above): `touch
#   ~/.claude/coderlap/gates-off` skips ALL commit reviews loudly until the
#   file is removed or expires 24h after creation. Owner's explicit in-chat
#   decision only, never agent judgment.
# Tunables: CODERV_GATE_ROUND_CAP (soft cap, default 3), CODERV_GATE_ROUND_MAX
#   (hard ceiling, default 5, always > cap), CODERV_GATE_DIFF_BUDGET (cumulative
#   transmitted-byte ceiling, default 800000), CODERV_GATE_SECURITY=1 (ADR-022
#   deep-security opt-in: adversarial brief + [hardening] blocks; default is the
#   quality-gate mode), CODERV_GATE_OWNER_OVERRIDE=1 (legacy launch-env-only
#   pass over an open ceiling security escalation — superseded by the per-diff
#   --approve, which works from inside a running session), CODERV_LOG_OFF=1
#   (silence the live-loop event log).
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
# eid = per-event identity: nanosecond epoch + PID + a random suffix. On a
# healthy host this is strongly unique across concurrent gate processes; on a
# degraded host it is best-effort probabilistic (see mint_eid). The viewer
# de-dupes on eid alone, so
# replayed history on reconnect can't double-count. NOT a sort key (ts + arrival
# order orders the display); eid is identity only. Mirrors how the gate already
# makes unique names via `mktemp XXXXXX`. A skip path mints one eid up front so
# it can set BOTH the event's eid AND its xid="skip-<reason>-<eid>" from the same
# token (the two stay correlated — spec contract), then passes the eid in.
mint_eid() {
    # Pure, error-swallowing: every subshell suppresses stderr and has a fallback,
    # so a missing/broken `date` or unreadable /dev/urandom can never leak to hook
    # stderr — the logging-is-invisible contract holds even on a degraded host.
    # The three-part <time>-<pid>-<entropy> shape is preserved with NON-EMPTY time
    # and entropy on every path (degraded time → $SECONDS-derived ns; degraded
    # entropy → a mktemp-name token, then $RANDOM$RANDOM), so uniqueness never
    # silently collapses to --$$--.
    local ns pid rnd tmp
    ns="$(date +%s%N 2>/dev/null)" || ns=""
    [[ -n "$ns" ]] || ns="${SECONDS}000000000"
    pid="$$"
    rnd="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' 2>/dev/null)" || rnd=""
    if [[ -z "$rnd" ]]; then
        # /dev/urandom unreadable. $RANDOM alone is a 15-bit PRNG whose seed can
        # repeat, so under PID reuse / PID namespaces two events in the same
        # second could collide and the viewer would de-dup a real event. Prefer a
        # token from a SUCCESSFULLY-CREATED mktemp file, then remove the file so
        # this stays a pure side-effect. This is BEST-EFFORT PROBABILISTIC only —
        # stronger in practice than $RANDOM, but neither mktemp's entropy source
        # nor its suffix strength is a portable contract, and once the file is
        # removed the name could in theory be reissued. Everything is swallowed.
        # If mktemp ALSO fails, fall back to $RANDOM$RANDOM so the eid is never
        # empty (last resort).
        tmp="$(mktemp "${TMPDIR:-/tmp}/eidXXXXXXXXXX" 2>/dev/null)" || tmp=""
        [[ -n "$tmp" ]] && rm -f "$tmp" 2>/dev/null
        rnd="${tmp##*/eid}"                       # keep only the XXXXXXXXXX tail
        rnd="${rnd//[^0-9A-Za-z]/}"               # scrub to the eid alphabet
        [[ -n "$rnd" ]] || rnd="$RANDOM$RANDOM"
    fi
    printf '%s-%s-%s' "$ns" "$pid" "$rnd"
}
log_event() {
    # log_event <actor> <type> <json-payload-object> [xid] [eid]  (payload → {})
    # xid = exchange id: all events of one review/skip share it, so the viewer
    # can group + de-duplicate correctly even when repos interleave. Review path
    # sets EVENT_XID once (the diff HASH); skip paths pass their synthetic xid.
    # eid: explicit 5th arg (skip paths, so xid can be derived from it) else minted
    # here. Empty xid is fine (legacy/unkeyed) — the viewer tolerates it.
    [[ "${CODERV_LOG_OFF:-0}" == "1" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0
    # xid: explicit 4th arg wins; else fall back to EVENT_XID (the review path
    # sets it once to the diff HASH, so every event of one review shares it
    # without threading HASH through 18 call sites — DRY, and no call can miss).
    local actor="$1" etype="$2" payload="${3:-{\}}" xid="${4:-${EVENT_XID:-}}"
    local eid="${5:-$(mint_eid)}"
    local line
    line=$(jq -cn --argjson ts "$(date +%s)" \
               --arg repo "${REPO_ID:-${DIR:-}}" \
               --arg actor "$actor" \
               --arg type "$etype" \
               --arg xid "$xid" \
               --arg eid "$eid" \
               --argjson payload "$payload" \
               '{ts:$ts, eid:$eid, xid:$xid, repo:$repo, actor:$actor, type:$type, payload:$payload}' 2>/dev/null) || return 0
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

# --- ADR-023: owner-approval recorder + diff identity ----------------------
# The owner is the FINAL authority: the gate exists to block AUTONOMOUS agent
# decisions, never an explicit owner decision. When a review denies a diff and
# the owner explicitly approves shipping it AS-IS (in-chat), that decision is
# recorded mechanically:
#     codex-review-gate.sh --approve <repo-dir> "<the owner's words>"
# The approval is keyed to the EXACT current outgoing diff of <repo-dir>
# (repo@HEAD + worktree delta + untracked — the same construction the review
# path hashes), so it can never leak onto different work: one changed byte =
# different key = normal review. The marker stores the owner's quoted words +
# timestamp (auditable), is SINGLE-USE (consumed when the identical commit
# passes), and is swept by the 24h cache TTL if unused. Record it ONLY on the
# owner's explicit approval, never on agent judgment.
collect_outgoing_diff() {
    # <dir> -> the outgoing delta the review path sees: worktree diff vs HEAD
    # (staged fallback for unborn HEAD / all-reverted tree) plus untracked.
    local dir="$1" d u f ud
    d=$(git -C "$dir" diff HEAD 2>/dev/null)
    [[ -z "$d" ]] && d=$(git -C "$dir" diff --cached 2>/dev/null)
    u=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)
    if [[ -n "$u" ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            ud=$(git -C "$dir" diff --no-index -- /dev/null "$f" 2>/dev/null)
            [[ -n "$ud" ]] && d+=$'\n'"$ud"
        done <<<"$u"
    fi
    printf '%s' "$d"
}
approval_key() {
    # <dir> -> sha256 keying an owner approval to the exact outgoing diff.
    # Mode-independent on purpose: the owner's "ship it as-is" covers the
    # diff itself, whichever review brief denied it. Both the writer
    # (--approve) and the reader (the review path) call THIS function, so the
    # two can never diverge.
    local dir="$1" repo base nl=$'\n'
    repo=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    base=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo unborn)
    sha256sum <<<"${repo}@${base}${nl}$(collect_outgoing_diff "$dir")${nl}owner-approval" | cut -d' ' -f1
}
# ADR-023 EMERGENCY owner off-switch, as a PURE predicate (no logging, no emit,
# no later-defined state) so it can be consulted at the earliest fail-closed
# point AND at the normal skip site below — one definition, no divergence.
# The flag is global (repo-independent) and grants a LOUD skip for 24h; a
# forgotten flag must never silently disable review forever, so an expired flag
# is reaped by the caller. This is the ONLY owner escape safe to honor before
# the review target is resolved: the per-diff --approve marker is keyed to a
# specific repo's diff, and at fail-closed time the target can only come from
# the very command we could not sanitize — a cwd-keyed guess would wrongly pass
# a `git -C /other-repo commit` decoy. gates-off means "skip ALL reviews this
# session," which needs no target, so it is the honest fail-closed exit.
GATES_OFF_FLAG="$HOME/.claude/coderlap/gates-off"
owner_gates_off_fresh() {
    # 0 = flag present AND < 24h old (honor it); 1 = absent or expired.
    [[ -f "$GATES_OFF_FLAG" ]] || return 1
    [[ -n "$(find "$GATES_OFF_FLAG" -mmin -1440 2>/dev/null)" ]]
}
# CLI recorder mode — must run BEFORE the env kill switches and the stdin
# read: it is invoked as a command, not as a hook, and recording an approval
# is meaningful even when other gate machinery is off.
if [[ "${1:-}" == "--approve" ]]; then
    A_DIR="${2:-}"; A_QUOTE="${3:-}"
    [[ -n "$A_DIR" && -d "$A_DIR" ]] || { echo "usage: $0 --approve <repo-dir> \"<the owner's words>\"" >&2; exit 2; }
    git -C "$A_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "--approve: $A_DIR is not a git repo" >&2; exit 2; }
    [[ -n "${A_QUOTE//[[:space:]]/}" ]] || { echo "--approve: the owner's approval words are required (the record must be auditable)" >&2; exit 2; }
    command -v jq >/dev/null 2>&1 || { echo "--approve: jq is required" >&2; exit 2; }
    A_KEY=$(approval_key "$A_DIR")
    A_CACHE="$HOME/.claude/coderlap/codex-reviewed"
    mkdir -p "$A_CACHE" 2>/dev/null || { echo "--approve: cannot create $A_CACHE" >&2; exit 1; }
    A_MARKER="$A_CACHE/owner-approval-$A_KEY"
    A_TMP=$(mktemp "$A_MARKER.tmp.XXXXXX" 2>/dev/null) || { echo "--approve: cannot write marker" >&2; exit 1; }
    if jq -n --arg quote "$A_QUOTE" \
             --arg repo "$(git -C "$A_DIR" rev-parse --show-toplevel 2>/dev/null)" \
             --arg base "$(git -C "$A_DIR" rev-parse HEAD 2>/dev/null || echo unborn)" \
             --argjson ts "$(date +%s)" \
             '{quote:$quote, repo:$repo, base:$base, ts:$ts}' > "$A_TMP" 2>/dev/null \
       && mv -f "$A_TMP" "$A_MARKER" 2>/dev/null; then
        REPO_ID=$(git -C "$A_DIR" rev-parse --show-toplevel 2>/dev/null)
        log_event owner approval_recorded \
            "$(jq -cn --arg q "$A_QUOTE" --arg k "$A_KEY" '{quote:$q, key:$k}')" "approve-$A_KEY"
        echo "owner approval recorded for the exact current outgoing diff of $A_DIR"
        echo "marker: $A_MARKER"
        echo "retry the identical commit now — it passes this one time; any other diff reviews normally."
        exit 0
    fi
    rm -f "$A_TMP" 2>/dev/null
    echo "--approve: failed to write $A_MARKER" >&2
    exit 1
fi

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
# Heredoc BODIES are stdin data, never commands (0.13.1): a message fed via
# `git commit -F - <<'EOF'` is unquoted text, so an embedded
# `; git -C <dir> commit` line inside it would otherwise survive the quote
# scrub and steer target resolution. Drop body lines (and the terminator);
# the operator line itself survives, so detection still sees the real
# invocation. An unterminated heredoc scrubs to end-of-command — the safe
# direction. `<<<` herestrings are not heredocs and are left alone.
#
# The delimiter word is resolved by FULL Bash quote removal (0.13.1 round 9):
# a `#` or backtick is an ordinary word char once the word has begun
# (<<EOF#TAG terminates on the literal EOF#TAG, not EOF); a `#` at word start
# is a comment (no heredoc); segments may be unquoted, '...', "...", $'...'
# (ANSI-C, fully decoded), or $"..." (dq); bare `$` is a literal char. Quote
# state (single / double / ANSI-C) CARRIES across newlines via q_sq/q_dq/q_ac
# so a multi-line quoted string can't hide a fake <<EOF on a later line and
# smuggle a real commit past the scrub. LC_ALL=C so ANSI-C byte emission is
# exact. If awk cannot sanitize, the caller fails CLOSED when a heredoc is
# present (never reviews attacker-controlled unsanitized text).
SCRUBBED=$(LC_ALL=C awk '
    # ---- ANSI-C ($\x27...\x27) decode: return the decoded delimiter segment.
    # s is the segment body (between the quotes). Full escape set, matching
    # bash: \a\b\e\E\f\n\r\t\v \\ \\\x27 \" \? , octal \nnn (1-3), hex \xHH
    # (1-2), control \cX, unicode \uHHHH / \UHHHHHHHH (emitted as UTF-8).
    # Unknown escapes keep the backslash literally, as bash does.
    function ansic(s,    out, m, len, ch, nx, j, hex, oct, cp, cc) {
        out = ""; m = 1; len = length(s)
        while (m <= len) {
            ch = substr(s, m, 1)
            if (ch != "\\" || m == len) { out = out ch; m++; continue }
            nx = substr(s, m+1, 1)
            if (nx == "a") { out = out sprintf("%c", 7);  m += 2; continue }
            if (nx == "b") { out = out sprintf("%c", 8);  m += 2; continue }
            if (nx == "e" || nx == "E") { out = out sprintf("%c", 27); m += 2; continue }
            if (nx == "f") { out = out sprintf("%c", 12); m += 2; continue }
            if (nx == "n") { out = out sprintf("%c", 10); m += 2; continue }
            if (nx == "r") { out = out sprintf("%c", 13); m += 2; continue }
            if (nx == "t") { out = out sprintf("%c", 9);  m += 2; continue }
            if (nx == "v") { out = out sprintf("%c", 11); m += 2; continue }
            if (nx == "\\") { out = out "\\"; m += 2; continue }
            if (nx == "\047") { out = out "\047"; m += 2; continue }
            if (nx == "\"") { out = out "\""; m += 2; continue }
            if (nx == "?") { out = out "?"; m += 2; continue }
            # A NUL byte TRUNCATES the $'...' string in bash — everything from
            # the \0 onward is dropped (verified: $'AB\x00CD' -> "AB"). So any
            # numeric escape that decodes to 0 ends the segment right here;
            # returning `out` matches bash instead of emitting a literal NUL that
            # would mismatch the real terminator and swallow a later commit.
            if (nx ~ /[0-7]/) {                 # \nnn octal, up to 3 digits
                oct = nx; j = m + 2
                while (j <= len && length(oct) < 3 && substr(s, j, 1) ~ /[0-7]/) { oct = oct substr(s, j, 1); j++ }
                cp = 0
                for (hex = 1; hex <= length(oct); hex++) cp = cp * 8 + (substr(oct, hex, 1) + 0)
                if (cp % 256 == 0) return out    # NUL truncates
                out = out sprintf("%c", cp % 256); m = j; continue
            }
            if (nx == "x") {                    # \xHH hex, up to 2 digits
                hex = ""; j = m + 2
                while (j <= len && length(hex) < 2 && substr(s, j, 1) ~ /[0-9A-Fa-f]/) { hex = hex substr(s, j, 1); j++ }
                if (hex == "") { out = out "\\x"; m += 2; continue }   # bash keeps \x literal
                if (hexval(hex) == 0) return out    # NUL truncates
                out = out sprintf("%c", hexval(hex)); m = j; continue
            }
            if (nx == "c") {                    # \cX control char
                if (m + 2 > len) { out = out "\\c"; m += 2; continue }
                cc = substr(s, m+2, 1)
                # Bash: \cX = toupper(X) masked with 0x1f, over the FULL ASCII
                # range (punctuation too: \c[ -> 27, \c] -> 29), with \c? the
                # sole special case -> DEL (127). \c@ decodes to 0 -> truncates.
                if (cc == "?") { out = out sprintf("%c", 127); m += 3; continue }
                if (ORD[toupper(cc)] % 32 == 0) return out    # \c@ -> NUL truncates
                out = out sprintf("%c", ORD[toupper(cc)] % 32)
                m += 3; continue
            }
            if (nx == "u" || nx == "U") {       # \uHHHH / \UHHHHHHHH -> UTF-8
                len_max = (nx == "u") ? 4 : 8
                hex = ""; j = m + 2
                while (j <= len && length(hex) < len_max && substr(s, j, 1) ~ /[0-9A-Fa-f]/) { hex = hex substr(s, j, 1); j++ }
                if (hex == "") { out = out "\\" nx; m += 2; continue }
                cp = hexval(hex)
                # A codepoint of 0 truncates the string like any NUL. Out-of-
                # range code points (> U+10FFFF) are bash-version-specific and
                # not a delimiter a committer types; treat them as truncating
                # too — conservative, since truncation only ever makes our
                # computed delimiter a PREFIX of the real one, which over-runs
                # the scrub (safe) rather than under-running it (which could let
                # a decoy survive).
                if (cp == 0 || cp > 1114111) return out
                out = out utf8(cp); m = j; continue
            }
            out = out "\\" nx; m += 2           # unknown escape: keep backslash (bash)
        }
        return out
    }
    function hexval(h,   v, k, d, c) {
        v = 0
        for (k = 1; k <= length(h); k++) {
            c = substr(h, k, 1); d = index("0123456789abcdef", tolower(c)) - 1
            v = v * 16 + d
        }
        return v
    }
    function utf8(cp) {                          # encode a code point as UTF-8 bytes
        # DECIMAL literals only — mawk parses 0x80 as 0, which would emit wrong
        # bytes and let a \u.. delimiter miss its real terminator (round 9).
        if (cp < 128) return sprintf("%c", cp)
        if (cp < 2048)
            return sprintf("%c%c", 192 + int(cp/64), 128 + (cp%64))
        if (cp < 65536)
            return sprintf("%c%c%c", 224 + int(cp/4096), 128 + int(cp/64)%64, 128 + (cp%64))
        return sprintf("%c%c%c%c", 240 + int(cp/262144), 128 + int(cp/4096)%64, 128 + int(cp/64)%64, 128 + (cp%64))
    }
    # Every heredoc is QUEUED (with <<A <<B the bodies follow in order, so
    # tracking only the first would let the second body survive). Operators
    # count ONLY at unquoted, uncommented positions — a quoted "<<EOF", a
    # `# <<EOF` comment, or a <<EOF inside a still-open multi-line string must
    # not queue a bogus delimiter that eats a later real commit line.
    BEGIN {
        qh = 1; qt = 0; q_sq = 0; q_dq = 0; q_ac = 0
        # ORD[char] = ASCII code, built portably (awk has no ord()); used by the
        # \cX control-escape decoder over the full printable range.
        _asc = " !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\140abcdefghijklmnopqrstuvwxyz{|}~"
        for (_z = 1; _z <= length(_asc); _z++) ORD[substr(_asc, _z, 1)] = _z + 31
    }
    qh <= qt {
        line = $0
        if (tabq[qh]) sub(/^\t+/, "", line)
        if (line == delimq[qh]) qh++
        next
    }
    {
        line = $0
        n = length(line); i = 1
        while (i <= n) {
            c = substr(line, i, 1)
            # Quote state carries across newlines: if a string opened on an
            # earlier line and never closed, we are still inside it here.
            if (q_sq) { if (c == "\047") q_sq = 0; i++; continue }
            if (q_ac) {                              # inside $\x27...\x27 (ANSI-C)
                if (c == "\\") { i += 2; continue }  # \\ and \\\x27 do not close
                if (c == "\047") q_ac = 0
                i++; continue
            }
            if (q_dq) {
                if (c == "\\") { i += 2; continue }
                if (c == "\"") q_dq = 0
                i++; continue
            }
            if (c == "\\") { i += 2; continue }
            # $\x27 opens an ANSI-C string; $" opens a locale double-quote —
            # both must be seen BEFORE the bare-quote cases so \x27 inside
            # $\x27...\x27 is not mistaken for a plain single quote.
            if (c == "$" && substr(line, i+1, 1) == "\047") { q_ac = 1; i += 2; continue }
            if (c == "$" && substr(line, i+1, 1) == "\"")   { q_dq = 1; i += 2; continue }
            if (c == "\047") { q_sq = 1; i++; continue }
            if (c == "\"") { q_dq = 1; i++; continue }
            # `#` opens a comment only at a token boundary: start of line, or
            # after whitespace or a control operator (; & | ( ) ). `true;# <<EOF`
            # and `case x in x)# <<EOF` are comments — without the operator case
            # the fake heredoc would queue and eat a following real commit line.
            if (c == "#" && (i == 1 || substr(line, i-1, 1) ~ /[[:space:];&|()]/)) break
            if (c == "<") {
                if (substr(line, i, 3) == "<<<") { i += 3; continue }
                if (substr(line, i, 2) == "<<") {
                    j = i + 2
                    tab = 0
                    if (substr(line, j, 1) == "-") { tab = 1; j++ }
                    while (substr(line, j, 1) ~ /[[:space:]]/) j++
                    # A `#` here (word start, before any segment) is a comment,
                    # not a delimiter char: `cat << #x` is a bash syntax error,
                    # nothing runs, so queue nothing and stop scanning the line.
                    if (substr(line, j, 1) == "#") break
                    # The delimiter is ONE shell word, possibly built from
                    # concatenated segments of different quoting (unquoted,
                    # '...', "...", $\x27...\x27 ANSI-C, $"...") that the shell
                    # quote-removes and joins. Parse segment by segment until a
                    # word boundary, decoding as the shell does, so a partial
                    # quote cannot make us queue a short delimiter that then
                    # swallows the real terminator and a following commit.
                    # broke=1 means a segment hit end-of-line mid-quote: not a
                    # valid heredoc op. sawq=1 means at least one quote segment
                    # was seen, so an empty resolved word (<<\x27\x27) is still a
                    # real (empty) delimiter and must queue.
                    d = ""; broke = 0; sawq = 0
                    while (j <= n) {
                        ch = substr(line, j, 1)
                        # $\x27...\x27 ANSI-C segment
                        if (ch == "$" && substr(line, j+1, 1) == "\047") {
                            k = j + 2; seg = ""
                            while (k <= n) {
                                cc = substr(line, k, 1)
                                if (cc == "\\" && k < n) { seg = seg cc substr(line, k+1, 1); k += 2; continue }
                                if (cc == "\047") break
                                seg = seg cc; k++
                            }
                            if (k > n) { broke = 1; break }
                            d = d ansic(seg); sawq = 1; j = k + 1; continue
                        }
                        # $"..." locale double-quote segment (same removal as ")
                        if (ch == "$" && substr(line, j+1, 1) == "\"") { j++; ch = "\"" }
                        # word boundary: whitespace, control/redirection ops.
                        # `#` and backtick are ORDINARY chars once the word has
                        # begun — they are NOT boundaries here (they were only
                        # boundaries at word start, handled above).
                        if (ch ~ /[[:space:];&|()<>]/) break
                        if (ch == "\"") {
                            k = j + 1
                            while (k <= n) {
                                cc = substr(line, k, 1)
                                if (cc == "\\" && k < n) {
                                    nx = substr(line, k+1, 1)
                                    # inside "...", backslash escapes " \ $ ` and
                                    # is dropped; before anything else it stays.
                                    if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { d = d nx; k += 2; continue }
                                }
                                if (cc == "\"") break
                                d = d cc; k++
                            }
                            if (k > n) { broke = 1; break }
                            sawq = 1; j = k + 1; continue
                        }
                        if (ch == "\047") {
                            k = j + 1
                            while (k <= n && substr(line, k, 1) != "\047") { d = d substr(line, k, 1); k++ }
                            if (k > n) { broke = 1; break }
                            sawq = 1; j = k + 1; continue
                        }
                        if (ch == "\\" && j < n) { d = d substr(line, j+1, 1); j += 2; continue }
                        d = d ch; j++
                    }
                    if (broke) { i = j; continue }   # unterminated quote: not a heredoc op
                    if (d != "" || sawq) {           # real word (incl. empty <<\x27\x27)
                        qt++
                        tabq[qt] = tab
                        delimq[qt] = d
                        i = j
                        continue
                    }
                }
            }
            i++
        }
        print line
    }
' <<<"$CMD" 2>/dev/null)
AWK_RC=$?
# awk missing/failed: fall back to the raw command (pre-heredoc-scrub
# behaviour) ONLY when no heredoc is present — the quote scrub below still
# applies. But if the command contains `<<` and awk could not sanitize it, a
# heredoc body could smuggle a decoy commit line past the scrub; there is no
# safe fallback, so fail CLOSED (deny loudly), mirroring the jq-missing path.
if [[ -z "$SCRUBBED" || $AWK_RC -ne 0 ]]; then
    if [[ "$CMD" == *'<<'* ]]; then
        # ADR-023: the owner is never trapped. This deny is the ONLY place a
        # gate block precedes the owner-escape checks below (819/906), because
        # it fires before the review target is resolved. An explicit owner
        # gates-off decision still overrides it — honored here, loudly. (The
        # per-diff --approve marker is deliberately NOT consulted at this point:
        # it is keyed to a specific repo's diff, and the target can only come
        # from the command we just failed to sanitize; honoring a cwd-keyed
        # guess would wrongly pass a `git -C /other-repo commit` decoy. gates-off
        # is global, so it is the safe fail-closed owner exit.)
        if owner_gates_off_fresh; then
            jq -n \
              --arg msg "⚠ codex-review-gate: OWNER GATES-OFF flag — heredoc commit NOT reviewed (awk unavailable; rm ~/.claude/coderlap/gates-off to re-arm)" \
              --arg ctx "CODEX REVIEW SKIPPED: awk could not sanitize the heredoc, but the owner's gates-off flag is present (an explicit in-chat decision to skip ALL reviews this session, expires 24h after creation). Honouring it here so the fail-closed path can never trap the owner. Report the skip alongside the commit; per the AI workflow rules a skipped review never stays silent." '{
                systemMessage: $msg,
                hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $ctx }
            }'
            exit 0
        fi
        jq -n \
          --arg msg "⛔ codex-review-gate: heredoc present but awk could not sanitize it — commit BLOCKED (not reviewed). Install awk (mawk/gawk) or rewrite the commit without a heredoc, then retry." \
          --arg r "A heredoc (<<) is present and the command-scrub pass (awk) failed or is unavailable. A heredoc body could hide an unreviewed command line past the scrub, so there is no safe fallback — per the AI workflow rules a review that cannot run must fail CLOSED, never silently allow. Fix options: (1) install awk; (2) re-run the commit without a heredoc (e.g. -m/-F <file>); (3) if the owner has explicitly approved skipping review this session, the fail-closed owner exit is the gates-off flag: touch ~/.claude/coderlap/gates-off (per-diff --approve cannot apply here — the review target is unresolved when the scrub fails)." '{
            systemMessage: $msg,
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: $r
            }
        }'
        exit 0
    fi
    SCRUBBED="$CMD"
fi
# Quote scrub, escape-aware for the forms that support backslash escapes
# (0.13.1): inside "..." and $'...' a \" / \' does NOT close the string, so
# the old naive pairing let a message containing \" spill its tail —
# including an injected `; git -C <dir> commit` — outside the QUOTED
# sentinel. Plain '...' cannot contain an escaped quote (POSIX), so its
# naive rule is exact. Order: $'...' first, then "..." (contractions like
# "don'\''t" live inside double quotes), then '...'.
SCRUBBED=$(sed -E -e "s/\\\$'([^'\\\\]|\\\\.)*'/QUOTED/g" -e 's/"([^"\\]|\\.)*"/QUOTED/g' -e "s/'[^']*'/QUOTED/g" <<<"$SCRUBBED")
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
# SECURITY (0.13.1): match against $SCRUBBED, never raw $CMD — same as GIT_RE
# above. Raw matching let a commit MESSAGE containing `; git -C <clean-repo>
# commit ...` hijack the review target: the clean decoy's empty diff silently
# allowed while the real repo's diff committed unreviewed. Trade-off: a QUOTED
# -C path scrubs to QUOTED (not a dir) and degrades to the cd/cwd candidates
# below — the same repo in the common case. Protecting `-C "..."` from the
# scrub is NOT an option: a message containing that exact text would be
# protected too, reintroducing the bypass.
if [[ "$SCRUBBED" =~ $GITC_RE ]]; then
    C_GITC="${BASH_REMATCH[9]//[\"\']/}"
    C_GITC="${C_GITC/#\~/$HOME}"
    # 0.13.1: a fully-quoted -C value scrubs to exactly QUOTED (or to a
    # QUOTED/... artifact from a quoted leading segment) — never treat those
    # as paths: as bare candidates they resolve RELATIVE to the gate's cwd,
    # ahead of the session cwd, so a plantable clean repo literally named
    # QUOTED would become a silent-allow decoy. Discard those two forms
    # ONLY; a real path merely CONTAINING the word (e.g. /srv/QUOTED-project)
    # stays a valid candidate — over-discarding would skip its review
    # whenever the session cwd is outside that repo.
    [[ "$C_GITC" == "QUOTED" || "$C_GITC" == QUOTED/* ]] && C_GITC=""
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

# Publish a cache marker under the per-hash lock, MONOTONICALLY: never overwrite
# a marker that already records a HIGHER round (a later/higher-priority outcome
# must not be downgraded by an earlier round finishing late). This ALSO protects
# concurrent-verdict disagreement: the HASH keys the DIFF, not the review result,
# so two reviews of the SAME diff can reach different verdicts (Codex is not
# deterministic). An LGTM path finishing after a deny path must NOT erase the
# deny's escalation marker — so lgtm is published here too (this="0", below every
# real round >= 1) and, like any lower/equal round, refuses to replace an
# existing round-bearing (denied/cap_stopped) marker. Falls back to a plain
# atomic write when flock is unavailable — the same degrade the rounds counter
# uses, and the round append it pairs with was itself skipped, so there is no
# higher-round marker to protect.
publish_round_marker() {
    # publish_round_marker <marker-file-path> <content> <this-round>
    local mf="$1" content="$2" this="$3"
    command -v flock >/dev/null 2>&1 || { write_marker "$mf" "$content"; return $?; }
    # shellcheck disable=SC2016  # single quotes intentional: $1..$3 are bash -c positionals
    # Severity rank of the INCOMING content — a blocking `denied` outranks an
    # allowing `cap_stopped`, which outranks `lgtm`. Ordering is by (round, rank):
    # a strictly-higher round always wins, and at EQUAL round the higher-severity
    # verdict wins so a late `cap_stopped` can never downgrade a same-round `denied`
    # escalation into an allow.
    local newrank=0
    case "$content" in
        denied\ round=*)      newrank=2 ;;
        cap_stopped\ round=*) newrank=1 ;;
        *)                    newrank=0 ;;   # lgtm / anything else
    esac
    # ADR-019 finding 12: a CEILING security block (denied … escalated=1) is the
    # top precedence key. It must outrank EVERY allowing marker (lgtm/cap_stopped)
    # and every escalated=0 deny REGARDLESS of round, so a later-round allow of the
    # same diff can never overwrite it and silently clear the required owner
    # escalation. Signalled to the critical section as newesc.
    local newesc=0
    case "$content" in *" escalated=1") newesc=1 ;; esac
    # shellcheck disable=SC2016  # single quotes intentional: $1..$5 are bash -c positionals
    flock -w 2 "$mf.lock" bash -c '
        mf="$1"; content="$2"; this="$3"; newrank="$4"; newesc="$5"
        cur=0; had_round=0; currank=0; curesc=0
        if [ -f "$mf" ]; then
            m=$(cat "$mf" 2>/dev/null)
            case "$m" in *" escalated=1") curesc=1 ;; esac
            case "$m" in
                denied\ round=*|cap_stopped\ round=*)
                    had_round=1
                    case "$m" in denied\ round=*) currank=2 ;; *) currank=1 ;; esac
                    r=${m#* round=}; r=${r%% *}
                    # reject an out-of-range/oversized field before arithmetic:
                    # 10# on a >64-bit value WRAPS (e.g. 2^64+1 -> 1), which would
                    # make a higher round look lower and let this write clobber it.
                    # Bounded to 9 digits (< 2^63) — real rounds are single/low
                    # double digits; anything longer is a corrupt record we keep
                    # (treat as an unbeatably-high round so it is never overwritten).
                    case "$r" in
                        ""|*[!0-9]*) cur=0 ;;
                        ?????????*)  cur=999999999 ;;   # >=10 digits: corrupt, keep it
                        *)           cur=$(( 10#$r )) ;;
                    esac ;;
            esac
        fi
        # ADR-019 finding 12: escalated=1 is the TOP precedence key, above the
        # (round, severity) ordering below.
        #   - an existing escalated=1 marker is UNBEATABLE by anything except
        #     another escalated=1 (a ceiling security stop is never cleared by a
        #     later allow of the same diff, whatever its round);
        #   - an incoming escalated=1 always wins (it must be able to overwrite an
        #     earlier allow/ordinary-deny to record the security stop).
        if [ "$curesc" -eq 1 ] && [ "$newesc" -ne 1 ]; then exit 0; fi
        if [ "$newesc" -eq 1 ]; then
            tmp=$(mktemp "$mf.tmp.XXXXXX") || exit 1
            printf "%s" "$content" > "$tmp" && mv -f "$tmp" "$mf" || { rm -f "$tmp"; exit 1; }
            exit 0
        fi
        # Downgrade protection, ordered by (round, severity-rank):
        #   - a strictly-lower round never overwrites (incl. lgtm at round 0);
        #   - at EQUAL round, a lower-or-equal severity never overwrites, so a
        #     late cap_stopped (rank 1) cannot replace a same-round denied
        #     (rank 2), while a denied CAN still supersede a same-round
        #     cap_stopped (an upgrade toward blocking is always safe).
        if [ "$had_round" -eq 1 ]; then
            if [ "$this" -lt "$cur" ]; then exit 0; fi
            if [ "$this" -eq "$cur" ] && [ "$newrank" -le "$currank" ]; then exit 0; fi
        fi
        tmp=$(mktemp "$mf.tmp.XXXXXX") || exit 1
        printf "%s" "$content" > "$tmp" && mv -f "$tmp" "$mf" || { rm -f "$tmp"; exit 1; }
    ' _ "$mf" "$content" "$this" "$newrank" "$newesc" 2>/dev/null
}

# What is about to be committed: PreToolUse fires before any `git add` in
# the same command runs, so review the full working-tree delta, not just
# the staged part — PLUS untracked files, which `git diff HEAD` misses.
# ADR-023: built by the shared collect_outgoing_diff so the review hash and
# the owner-approval key can never disagree about what "this diff" means.
DIFF=$(collect_outgoing_diff "$DIR")
UNTRACKED=$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null)
# The viewer groups + de-dups by (xid, eid). A skip is a terminal one-event
# exchange, so it needs its own xid. log_skip mints ONE eid, then emits the event
# with that eid AND xid="skip-<reason>-<eid>" — the two stay correlated (spec
# contract), and concurrent identical skips never collide. REPO_ID is set to the
# canonical toplevel FIRST so a skip beat lands under the same project name the
# review path uses (never a subdir/symlink spelling) — log_event reads REPO_ID
# for the event's repo field.
log_skip() {
    # log_skip <reason> <payload-json>
    local reason="$1" payload="$2" eid
    eid="$(mint_eid)"
    log_event system gate_skipped "$payload" "skip-${reason}-${eid}" "$eid"
}
REPO_ID=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
REPO_ID=$(readlink -f "$REPO_ID" 2>/dev/null || printf '%s' "$REPO_ID")

# Empty diff: a plain commit has nothing outgoing to review — silent
# allow. But merge/cherry-pick/revert/rebase on a clean worktree are
# about to CREATE commits from history the gate never sees; that must
# be loud, never a silent skip.
if [[ -z "${DIFF//[[:space:]]/}" ]]; then
    if [[ "$SUBCMD" == "commit" ]]; then
        log_skip empty_diff \
            "$(jq -cn --arg sub "$SUBCMD" '{reason:"empty_diff", subcmd:$sub}')"
        exit 0
    fi
    log_skip merge_incoming \
        "$(jq -cn --arg sub "$SUBCMD" '{reason:"merge_incoming", subcmd:$sub}')"
    allow_with_warning \
        "⚠ codex-review-gate: git $SUBCMD NOT reviewed (no worktree diff — incoming commits unseen)" \
        "CODEX REVIEW SKIPPED: 'git $SUBCMD' integrates existing commits, and with a clean worktree the gate has no outgoing diff to review — the commits it brings in are NOT reviewed. Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."
fi

# Docs-only commits flow freely (a SESSIONS.md handoff must never wait).
DOCS_ONLY=1; DOCS_FILES=0
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" =~ \.(md|txt)$ ]] || { DOCS_ONLY=0; break; }
    DOCS_FILES=$((DOCS_FILES+1))
done < <({ git -C "$DIR" diff HEAD --name-only 2>/dev/null;
           git -C "$DIR" diff --cached --name-only 2>/dev/null;
           printf '%s\n' "$UNTRACKED"; } | sort -u)
if [[ "$DOCS_ONLY" == "1" ]]; then
    log_skip docs_only \
        "$(jq -cn --arg sub "$SUBCMD" --argjson files "$DOCS_FILES" \
            '{reason:"docs_only", subcmd:$sub, files:$files}')"
    exit 0
fi

# ADR-023 EMERGENCY owner off-switch (secondary — the per-diff --approve
# above is the primary owner exit) — a FILE, because the env kill switches at
# the top are read from Claude Code's environment, frozen at session launch:
# an owner saying "skip the gate this session" mid-conversation has no way to
# reach them. The flag file works immediately, expires 24h after creation (a
# forgotten flag must never silently disable review forever — same TTL as the
# cache sweep), and every skip it grants is LOUD, never silent. Checked AFTER
# commit detection + docs-only so non-commit commands stay noise-free. Uses the
# same owner_gates_off_fresh predicate the early fail-closed path consults
# (defined once near the top, GATES_OFF_FLAG with it) so the two can never
# diverge; this site adds the log_skip + owner-facing allow the early path
# cannot (its logging/emit helpers are not defined yet).
if [[ -f "$GATES_OFF_FLAG" ]]; then
    if owner_gates_off_fresh; then
        log_skip owner_gates_off \
            "$(jq -cn --arg sub "$SUBCMD" '{reason:"owner_gates_off", subcmd:$sub}')"
        allow_with_warning \
            "⚠ codex-review-gate: OWNER GATES-OFF flag — commit NOT reviewed (rm ~/.claude/coderlap/gates-off to re-arm)" \
            "CODEX REVIEW SKIPPED: the owner's gates-off flag file is present (~/.claude/coderlap/gates-off, expires 24h after creation). The flag exists to honour an explicit owner decision given in-chat — create it ONLY on such a decision, never on your own judgment — and the skip must be reported alongside the commit; per the AI workflow rules a skipped review never stays silent."
    fi
    rm -f "$GATES_OFF_FLAG" 2>/dev/null   # expired flag: reap it, the gate re-arms
fi

# ADR-022 review-policy mode — resolved BEFORE the cache key because the mode
# is part of the review's identity (see HASH below). DEFAULT (unset) =
# engineering QUALITY GATE: realistic-impact defects block; marginal findings
# ([edge]/[theoretical]/[hardening]) never block — they allow immediately and
# are surfaced under the "Non-blocking debt" section, so a healthy commit
# converges in ONE round. CODERV_GATE_SECURITY=1 = explicit DEEP SECURITY
# REVIEW opt-in (/ship --security): the full adversarial brief, [hardening]
# treated as material, and the pre-0.14.0 cap-gated marginal semantics.
SECURITY_MODE=0
[[ "${CODERV_GATE_SECURITY:-0}" == "1" ]] && SECURITY_MODE=1
# A PreToolUse hook inherits Claude Code's environment, NOT an env-prefix
# written inside the command string — so the /ship --security commit form
# (`CODERV_GATE_SECURITY=1 git commit ...`) must be recognized from the
# SCRUBBED command text itself or the opt-in would silently downgrade to the
# default brief (fresh-context audit F1). Matching the scrubbed text keeps
# quoted mentions inert; and the spoof direction is safe by construction —
# the flag can only UPGRADE the review to the stricter adversarial mode.
SEC_PFX_RE='(^|[;&|(`[:space:]])CODERV_GATE_SECURITY=1[[:space:]]'
[[ "$SCRUBBED" =~ $SEC_PFX_RE ]] && SECURITY_MODE=1
# Outcome visibility: every owner-facing verdict names the mode when the deep
# review ran, so a transport failure can never masquerade as a security pass.
MODE_TAG=""; (( SECURITY_MODE )) && MODE_TAG=" [deep-security mode]"

# One review per unique (repo, HEAD, diff, mode): the retry after adjudication
# passes; any tree change, new commit, DIFFERENT repo with an identical diff,
# or a MODE FLIP produces a new hash and a fresh review. The mode is part of
# the key because an allow earned under the default quality-gate policy
# (lgtm / optional marker) must never satisfy an explicit --security rerun of
# the same diff — the deep review is the whole point of the opt-in — and,
# symmetrically, a security-mode verdict must not pre-answer a default run.
REPO_ID=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
BASE=$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo unborn)
HASH=$(sha256sum <<<"${REPO_ID}@${BASE}${NL}${DIFF}${NL}mode=${SECURITY_MODE}" | cut -d' ' -f1)
# Every event of THIS review shares the diff HASH as its exchange id (xid), so
# the viewer groups + de-dups the whole exchange correctly even when repos
# interleave. Set here, once, after HASH exists; log_event falls back to it.
# (Do NOT let this feed HASH above — HASH is the cache key and must stay stable.)
EVENT_XID="$HASH"
# Canonicalise the repo label to match the skip paths (readlink of toplevel) so
# one repo never splits across two project names in the viewer. Purely the event
# label — applied AFTER HASH so the cache key is untouched.
REPO_ID=$(readlink -f "$REPO_ID" 2>/dev/null || printf '%s' "$REPO_ID")
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
        */rounds-*|*/ledger-*)
            # rounds-* AND ledger-* (ADR-019) are flock-guarded DATA files: delete
            # only WHILE HOLDING their lock, age re-checked inside the critical
            # section, so an unlocked delete can't race a concurrent locked append.
            command -v flock >/dev/null 2>&1 || continue
            # shellcheck disable=SC2016  # single quotes intentional: $1 is a bash -c positional
            flock -w 1 "$swept.lock" bash -c \
                '[ -n "$(find "$1" -maxdepth 0 -mmin +1440 2>/dev/null)" ] && rm -f "$1"' \
                _ "$swept" 2>/dev/null || true
            ;;
        *) rm -f "$swept" 2>/dev/null ;;
    esac
done
# ADR-023 scoped owner approval — TOP precedence, checked before every other
# gate state (round cache, cap, ceiling, security escalation) and before any
# Codex call: an explicit owner decision on THIS exact outgoing diff is
# final. The gate blocks autonomous agent decisions; it never overrules the
# owner. Single-shot: the marker is consumed here, so the recorded authority
# spends itself on one pass; every other diff (one changed byte = a new key)
# reviews normally, and the sweep above reaps unused markers after 24h.
A_KEY=$(approval_key "$DIR")
APPROVAL_MARKER="$CACHE/owner-approval-$A_KEY"
if [[ -f "$APPROVAL_MARKER" ]]; then
    A_QUOTE=$(jq -r '.quote // empty' < "$APPROVAL_MARKER" 2>/dev/null)
    rm -f "$APPROVAL_MARKER" 2>/dev/null   # single-use: spent on this pass
    log_event owner outcome "$(jq -cn --arg q "$A_QUOTE" \
        '{result:"passed", owner_approved_diff:true, quote:$q}')"
    allow_with_warning \
        "⚠ codex-review-gate: OWNER-APPROVED DIFF — commit allowed on the owner's recorded decision (open findings, if any, remain unresolved)" \
        "OWNER APPROVAL on record for this exact diff (quote: \"$A_QUOTE\"). The owner is the final authority: this commit passes regardless of open findings or escalations. Surface any unresolved findings alongside the commit (transparency rule — never silently dropped). The approval was single-use and is now consumed; the gate stays armed for every other diff."
fi
# Round-cap parameters + state location (two-brain-convergence.md CAP-STOPPED)
# are computed HERE, before the cache fast-path, because both paths need them:
# the fresh-review decision below, and the cached retry — which must stay LOUD
# when it rides over an unresolved cap escalation.
# Env-tunable thresholds — each bounded to 1-9 digits (< 1e9, safely < 2^63) so
# no oversized value can overflow the (( )) arithmetic below (ADR-019 finding 8).
# The CAP guard is TIGHTENED from the historical `^[1-9][0-9]*$` (which accepted
# an arbitrarily long digit string) to the same bounded form.
CAP="${CODERV_GATE_ROUND_CAP:-3}"
[[ "$CAP" =~ ^[1-9][0-9]{0,8}$ ]] || CAP=3
# ADR-019 hard ceiling: above the soft CAP (where marginal residue auto-allows)
# sits ROUND_MAX — the round at/after which even non-security material residue
# self-terminates (allow-with-caveat) instead of the loop escalating routine code
# to the human. Default 5, must be > CAP; a MAX <= CAP would make the ceiling
# meaningless (the middle tier would be empty), so clamp up to CAP+2.
ROUND_MAX="${CODERV_GATE_ROUND_MAX:-5}"
[[ "$ROUND_MAX" =~ ^[1-9][0-9]{0,8}$ ]] || ROUND_MAX=5
(( ROUND_MAX <= CAP )) && ROUND_MAX=$(( CAP + 2 ))
# ADR-019 cumulative transmitted-byte ceiling: a size-based hard stop parallel to
# ROUND_MAX, in bytes ACTUALLY SENT to Codex (LC_ALL=C, see the accumulation in
# the rounds transaction). Default 800000; same bounded-int guard.
DIFF_BUDGET="${CODERV_GATE_DIFF_BUDGET:-800000}"
[[ "$DIFF_BUDGET" =~ ^[1-9][0-9]{0,8}$ ]] || DIFF_BUDGET=800000
# (SECURITY_MODE is resolved earlier, before the cache key — the review mode
# is part of the review's identity.)
CANON_REPO=$(readlink -f "$REPO_ID" 2>/dev/null) || CANON_REPO="$REPO_ID"
ROUNDS_FILE="$CACHE/rounds-$(sha256sum <<<"${CANON_REPO}@${BASE}" | cut -d' ' -f1)"
# ADR-019 findings ledger: sibling to ROUNDS_FILE, same (canonical repo, HEAD)
# key, same lifecycle (flock append, no delete path, reaped by the 24h sweep and
# by HEAD movement). One line per reviewed finding: "<fingerprint> <round> <text>"
# where text is the finding newline-flattened + length-capped. Prior findings are
# fed back into the review prompt so Codex stops re-raising resolved ones.
LEDGER_FILE="$CACHE/ledger-$(sha256sum <<<"${CANON_REPO}@${BASE}" | cut -d' ' -f1)"
# Already reviewed once (the adjudicate-then-retry of an IDENTICAL diff): the
# commit is allowed to proceed. Log the successful retry so the dashboard
# shows the loop closing — without it, the viewer would freeze on the denial
# and never show the commit landing. REPO_ID is already resolved + canonicalised
# above; keep it canonical here too so the cached-retry beat lands under the same
# project name as the original review (never a subdir/symlink spelling). EVENT_XID
# (=HASH) is likewise already set, so these cached events share the review's xid.
if [[ -f "$CACHE/$HASH" ]]; then
    REPO_ID=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
    REPO_ID=$(readlink -f "$REPO_ID" 2>/dev/null || printf '%s' "$REPO_ID")
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
    # terminal path in exactly these schemas (ADR-019 added the trailing
    # ceiling=/escalated= fields; the legacy field-less forms still parse) —
    #   "lgtm"
    #   "cap_stopped round=N findings=M [ceiling=K]"
    #   "denied round=N material=M [escalated=E]"
    # (An ADR-022 optional-notes allow deliberately writes NO marker — a
    # cached retry could only echo a count, not the findings, so it
    # re-reviews instead; transparency over caching.)
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
            # Fields are bounded to 1-9 digits (< 2^63): an oversized value like
            # round=18446744073709551617 would WRAP under 64-bit arithmetic
            # (2^64+1 -> 1), making an above-cap denial look below-cap; a >9-digit
            # field fails this anchored match and falls to the deny below instead.
            # The ceiling field is OPTIONAL (ADR-019): a new marker is
            # "cap_stopped round=N findings=M ceiling=K"; a legacy one omits it.
            # ceiling=0 (or absent) → classic marginal-only stop; ceiling=K>0 →
            # K non-security material findings self-terminated at the hard ceiling,
            # so the retry caveat must NOT claim "only MARGINAL findings".
            CS_CEIL=0; CS_MATCH=0
            if [[ "$MARKER_STATE" =~ ^cap_stopped\ round=([0-9]{1,9})\ findings=([0-9]{1,9})\ ceiling=([0-9]{1,9})$ ]]; then
                CS_MATCH=1; CS_CEIL=$(( 10#${BASH_REMATCH[3]} ))
            elif [[ "$MARKER_STATE" =~ ^cap_stopped\ round=([0-9]{1,9})\ findings=([0-9]{1,9})$ ]]; then
                CS_MATCH=1; CS_CEIL=0   # legacy marker: treat as marginal-only
            fi
            if (( CS_MATCH )) && (( 10#${BASH_REMATCH[1]} >= CAP )) && (( 10#${BASH_REMATCH[2]} > 0 )); then
                log_event system outcome "$(jq -cn --argjson ceil "$CS_CEIL" '{result:"passed", cached:true, cap_stopped:true, ceiling_material:$ceil}')"
                if (( CS_CEIL > 0 )); then
                    allow_with_warning \
                        "⚠ codex-review-gate: retry of a CEILING-STOPPED diff ALLOWED — $CS_CEIL non-security material finding(s) still stand" \
                        "This identical diff self-terminated at the convergence ceiling with $CS_CEIL non-security material finding(s) still open ($MARKER_STATE) — the loop stopped rather than escalate routine code, but the findings are NOT resolved. Surface them to the owner alongside this commit (transparency rule — never silently dropped)."
                else
                    allow_with_warning \
                        "⚠ codex-review-gate: retry of a CAP-STOPPED diff ALLOWED — its marginal findings still stand" \
                        "This identical diff was previously allowed at the round cap with MARGINAL findings open ($MARKER_STATE). The retry does not resolve them: surface those findings to the owner alongside this commit (transparency rule — never silently dropped)."
                fi
            else
                # cap_stopped prefix but malformed tail OR invariant-violating
                # counts: do NOT auto-allow a garbled/impossible allow-marker —
                # fall to the unknown-marker deny below.
                CAP_RIDE=1; R_UNVERIFIED=1
            fi
            ;;
        "denied round="*" material="*)
            # ADR-019: the denied marker now carries an explicit escalation flag
            # "denied round=N material=M escalated=E" (E in {0,1}). Only
            # escalated=1 (a CEILING [security]/[data-loss] block) is an OPEN
            # escalation that an identical retry cannot clear. escalated=0 (an
            # ordinary below-cap or middle-tier deny) retries per the
            # adjudicate-then-retry contract — so the loop can reach ROUND_MAX
            # instead of the first middle-tier deny locking it (finding 9).
            # Fields bounded to 1-9 digits (< 2^63): an oversized round would WRAP
            # under 64-bit arithmetic; a >9-digit field fails the anchored match
            # and routes to the unverified-escalation deny below.
            if [[ "$MARKER_STATE" =~ ^denied\ round=([0-9]{1,9})\ material=([0-9]{1,9})\ escalated=([01])$ ]]; then
                # 10# forces base-10 (round=08 must not parse as octal).
                R_ROUND=$(( 10#${BASH_REMATCH[1]} )); R_MAT=$(( 10#${BASH_REMATCH[2]} ))
                R_ESC="${BASH_REMATCH[3]}"
                # Invariant: a real denied marker has round >= 1, and an
                # escalated=1 marker (a ceiling security stop) is only ever
                # written at/above the cap. An escalated=1 recorded below the cap
                # is impossible → torn/forged, route to the unverified deny.
                if (( R_ROUND < 1 )) || { [[ "$R_ESC" == 1 ]] && (( R_ROUND < CAP )); }; then
                    CAP_RIDE=1; R_UNVERIFIED=1
                elif [[ "$R_ESC" == 1 ]]; then
                    CAP_RIDE=1
                fi
                # R_ESC=0 → ordinary deny: leave CAP_RIDE=0 so the identical
                # retry falls through to the plain reviewed-ok pass below.
            elif [[ "$MARKER_STATE" =~ ^denied\ round=([0-9]{1,9})\ material=([0-9]{1,9})$ ]]; then
                # LEGACY marker (pre-ADR-019, no escalated flag). Infer the flag
                # from the round vs CAP (finding 15): a legacy deny AT/ABOVE the
                # cap was an escalation under the old semantics → treat as
                # escalated (conservative for at/above-cap ambiguity); a legacy
                # BELOW-cap deny was an ordinary retry-deny → must NOT become a
                # permanent owner escalation after upgrade, so it retries.
                R_ROUND=$(( 10#${BASH_REMATCH[1]} )); R_MAT=$(( 10#${BASH_REMATCH[2]} ))
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
            # Treated as an open escalation (conservative) — the owner clears it
            # with --approve (ADR-023), same as an unparseable denial.
            CAP_RIDE=1; R_UNVERIFIED=1
            ;;
    esac
    fi   # MARKER_READ_OK
    if (( CAP_RIDE )); then
        # An open (or unverifiable) CAP-REACHED escalation is NOT cleared by an
        # identical retry. The real in-band owner exit is --approve (ADR-023),
        # named in the deny message below — it works from inside a running
        # session and is keyed to this exact diff. The legacy
        # CODERV_GATE_OWNER_OVERRIDE check below is retained only for
        # compatibility: it is read from Claude Code's launch environment
        # (frozen at session start), so an env-prefix on the retried command
        # never reaches this hook — it can only pass when the variable was
        # exported before the session began. Not the in-band exit; --approve is.
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
        jq -n --arg r "CAP-REACHED escalation is still OPEN for this repo@HEAD ($R_WHY). An identical-diff retry does NOT clear it. Options: fix the material findings (a changed diff gets a fresh review), or the OWNER explicitly approves shipping this exact diff as-is (in-chat) — then record that decision and retry the identical commit: $0 --approve <repo-dir> \"<the owner's words>\" (ADR-023: keyed to this exact diff, passes it once, gate stays armed for everything else). Record it only on the owner's explicit approval, quoted verbatim — never on your own judgment." \
              --arg msg "⛔ codex-review-gate: identical retry DENIED — CAP-REACHED escalation open ($R_WHY); owner exit: --approve (ADR-023)" '{
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
# KI-005: terminate on "dirname made no progress", not on the '/'-only check —
# Windows-form paths (D:/x, D:\x) walk to '.' and dirname "." is "." forever.
while [[ "$SPEC_ROOT" != "/" && ! -f "$SPEC_ROOT/CLAUDE.md" ]]; do P=$(dirname "$SPEC_ROOT"); [[ "$P" == "$SPEC_ROOT" ]] && break; SPEC_ROOT="$P"; done
[[ -f "$SPEC_ROOT/CLAUDE.md" ]] || SPEC_ROOT="$DIR"
# Windows (0.15.1): Git Bash sees /d/... while native tools see D:\... —
# cygpath -w canonicalises to the native form (no-op on Linux, where cygpath
# does not exist); '\' becomes a separator dash and ':' (illegal in Windows
# filenames) is stripped, so writer and reader always agree on the slug.
SPEC_FILE="$HOME/.claude/coderlap/specs/$(printf '%s' "$(cygpath -w "$SPEC_ROOT" 2>/dev/null || printf '%s' "$SPEC_ROOT")" | tr '/\\' '--' | tr -d ':').md"
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

# --- ADR-019 MEMORY: prior findings for this (repo, HEAD) --------------------
# Read the findings ledger (schema-valid lines only) and build a block Codex
# sees BEFORE reviewing, so it stops re-raising a finding Claude already
# resolved. Best-effort: any read failure yields an empty block (the exact
# pre-ADR-019 behavior — a cold review), never a blocked commit. Each ledger
# line is "<fp> <round> <flattened text>"; we surface the ROUND it was first
# raised and the text, and instruct Codex not to re-raise unless the CURRENT
# code still exhibits it. The ledger is populated after this review (below).
# The ledger read + append + the rounds transaction all rely on flock for
# consistency. When flock is UNAVAILABLE the whole ADR-019 context layer degrades
# to the pre-ADR-019 cold review (empty prior block + PROMPT_NOCTX below): reading
# the ledger unlocked could race the 24h sweep or a concurrent append and feed a
# torn/partial history into the prompt. CTX_OK tracks whether the memory+context
# layer is trustworthy this run; it gates BOTH the prior-findings read and the
# prompt selection.
CTX_OK=0
command -v flock >/dev/null 2>&1 && CTX_OK=1
PRIOR_FINDINGS_BLOCK=""
if (( CTX_OK )) && [[ -f "$LEDGER_FILE" ]]; then
    # Read UNDER the ledger lock so a concurrent append / the sweep can't hand us a
    # torn file. Grep to schema-valid lines, strip the fingerprint, keep the text.
    # A torn/legacy line that doesn't match is simply skipped (safe: it just
    # isn't fed back). Cap by LINE COUNT (head/tail -n), never bytes: a byte cap
    # under LC_ALL=C can split a multibyte finding mid-character, and that invalid
    # UTF-8 embedded in the prompt can make `codex exec` reject the whole request
    # and trip the fail-open path. Whole-line truncation keeps every char intact.
    # A generous 300-line cap keeps the full history in all realistic loops (a
    # handful of rounds x findings) while bounding a pathological ledger; newer
    # findings matter most, so keep the LAST N lines (tail).
    # Snapshot the ledger UNDER its lock into a temp file FIRST, checking flock's
    # OWN exit status directly (not PIPESTATUS after a $(...) — that reflects the
    # substitution, not the flock inside it). Only if the lock was taken do we
    # parse the snapshot. If the lock times out / errors, the read is untrusted →
    # degrade the whole context layer to the pre-ADR-019 diff-only review rather
    # than presenting a memory-assisted prompt with no memory.
    LED_SNAP=$(mktemp 2>/dev/null)
    # shellcheck disable=SC2016
    if [[ -n "$LED_SNAP" ]] && flock -w 2 "$LEDGER_FILE.lock" \
            bash -c 'cat "$1" > "$2" 2>/dev/null' _ "$LEDGER_FILE" "$LED_SNAP" 2>/dev/null; then
        PRIOR_FINDINGS_BLOCK=$(grep -E '^[0-9a-f]{16} [0-9]+ .+' "$LED_SNAP" 2>/dev/null \
            | sed -E 's/^[0-9a-f]{16} ([0-9]+) /  - (first raised round \1) /' \
            | tail -n 300)
    else
        # lock not taken (timeout/error) OR no temp file → untrusted read.
        CTX_OK=0
        PRIOR_FINDINGS_BLOCK=""
    fi
    [[ -n "$LED_SNAP" ]] && rm -f "$LED_SNAP"
fi
# The round this review will BECOME — read the prior round count from the rounds
# file so the [LATE] pressure attaches to round >= 2 REGARDLESS of ledger
# contents (a failed ledger append, an all-torn ledger, or a prose-only prior
# round must still get the [LATE] rule — finding: the rule was wrongly tied to a
# non-empty prior block). Best-effort + advisory only: it shapes the prompt, it
# does NOT gate allow/deny (that is the authoritative flock transaction below).
# Counts BOTH schemas (new 4-field + legacy 3-field), same as that transaction.
# NOTE (intentional, not a defect): this is an UNLOCKED read, so under two
# concurrent FIRST reviews both can see 0 prior rows and get a round-1 prompt
# (no [LATE]) even though one is later recorded as round 2. That is acceptable:
# [LATE] is a convergence-pressure HINT, never a gate decision — a missing tag
# can't unlock the cap or a ceiling. Reserving the round under a lock here would
# add a second serialized section purely to perfect an advisory prompt string;
# the authoritative round + every allow/deny still come from the locked
# transaction below, which the two concurrent reviews DO serialize on.
UPCOMING_ROUND=1
if [[ -f "$ROUNDS_FILE" ]]; then
    _pr=$(grep -cE '^[0-9]+ [0-9]+ [^[:space:]]+( [0-9]+)?$' "$ROUNDS_FILE" 2>/dev/null)
    [[ "$_pr" =~ ^[0-9]+$ ]] && UPCOMING_ROUND=$(( _pr + 1 ))
fi

# --- ADR-019 CONTEXT: changed files + [LATE] pressure -----------------------
# The changed-file list (tracked + untracked) is named to Codex so it can READ
# the real surrounding code (the review runs read-only from the repo cwd, so a
# false finding the code disproves is avoidable). Best-effort: an empty list
# just omits the hint. Untracked included to match the diff-assembly contract.
# A very large changeset is line-capped (context hint, not the diff itself — the
# diff Codex reviews is unaffected); the cap is announced so an omitted-file
# finding is never silently under-contextualised.
CHANGED_ALL=$( { git -C "$DIR" diff --name-only HEAD 2>/dev/null
                 git -C "$DIR" diff --cached --name-only 2>/dev/null
                 git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null
               } | sort -u )
CHANGED_TOTAL=$(printf '%s\n' "$CHANGED_ALL" | grep -c . || true)
CHANGED_FILES=$(printf '%s\n' "$CHANGED_ALL" | head -500)
CHANGED_NOTE=""
(( CHANGED_TOTAL > 500 )) && CHANGED_NOTE="  (… $(( CHANGED_TOTAL - 500 )) more changed files not listed — the diff below still contains them)"

# The prior-findings + [LATE] instruction block, injected into both prompt
# branches. "Converged" is defined so a reviewer with memory + real code in front
# of it knows LGTM is the goal, not a per-round trickle of one new finding.
MEMORY_BLOCK="You are reviewing with MEMORY and PROJECT CONTEXT (two-model
convergence, ADR-019). The repository is your working directory; you may READ
any file in it (read-only) to confirm or disprove a suspected issue BEFORE
reporting it — a finding the real code disproves must NOT be raised.
Changed files in this diff:
${CHANGED_FILES:-  (none listed)}${CHANGED_NOTE:+
$CHANGED_NOTE}

CONVERGED means: you reply LGTM because, with the prior findings and the real
code in front of you, nothing material remains — NOT merely \"no new finding
this round\". Do the ONE exhaustive pass that reaches that state."
if [[ -n "$PRIOR_FINDINGS_BLOCK" ]]; then
    MEMORY_BLOCK+="

You have ALREADY raised these findings in earlier rounds for this same commit
point. Do NOT raise any of them again UNLESS the CURRENT code still exhibits it
— and if it does, cite the exact line that still shows the problem:
$PRIOR_FINDINGS_BLOCK"
fi
# [LATE] pressure attaches whenever this is round >= 2, independent of whether
# the prior-findings block above is populated (finding: a failed/empty ledger
# must not disable it).
if (( UPCOMING_ROUND >= 2 )); then
    MEMORY_BLOCK+="

This is review round $UPCOMING_ROUND for this commit point. Any finding that
FIRST appears now (was not already raised in an earlier round) MUST be tagged
[LATE] at the very start and justify in one clause why it could not have been
seen at round 1. Reserve [LATE] for genuinely new issues; a resurfaced old
finding is not [LATE], it is a re-raise and is barred unless the code still
shows it."
fi

# Severity contract, shared by both prompt branches. The tags are defined by
# REACHABILITY + IMPACT, never likelihood or craftedness — the allow paths below
# only ever auto-allow marginal-tagged findings, so a tag that lets a serious
# failure read as marginal would be a hole in the gate. The wording (incl. the
# "never tag as [edge]" rule) was co-designed with the reviewer model itself.
# ADR-022: [hardening] joins the marginal group in default mode; the grouping
# paragraph is mode-dependent (default = Optional-Security-Review routing,
# security mode = the pre-0.14.0 cap semantics with [hardening] material).
SEVERITY_RULES='GOVERNING PRINCIPLE (practical impact, not theoretical
perfection): Ignore atomic, theoretical, defensive, or extremely low-impact
findings that do not materially affect the user. Do NOT block a commit for
issues that have no realistic user-facing impact, do not affect correctness in
normal use, do not risk data loss or corruption, do not create a security or
privacy issue, do not break compatibility, release integrity, or core
contracts, or are only speculative hardening, cosmetic debt, comment wording,
micro-cleanup, or unlikely edge cases. Once the implementation is materially
correct and verified, STOP — do not keep searching for increasingly smaller
issues. Practical impact is the stopping rule.

DECLARE every finding as exactly one of:
  [blocker] = there is a MATERIAL impact on users, data, security/privacy,
              correctness, compatibility, or release integrity.
  [debt]    = a small, defensive, theoretical, cosmetic, or low-probability
              issue. NON-BLOCKING DEBT.
A [blocker] MUST also name its harm category with one of the severity tags
below. If you cannot identify a realistic material harm in one of those six
categories, the finding is [debt] by construction.

Then tag EVERY finding with exactly ONE impact severity in square brackets,
chosen by REACHABILITY + IMPACT — never by likelihood, and never by how
crafted the triggering input is (real injection is usually crafted input;
craftedness must not downgrade a reachable failure):
  [data-loss]   = loss or corruption of user data.
  [security]    = confidentiality, integrity, authorization, or any other
                  security-guarantee failure that a realistic actor — normal
                  use OR a credible attacker against the real trust boundary —
                  can actually REACH.
  [correctness] = any reachable wrong user-visible or externally observable
                  result not covered by the two above. This is also the tag for
                  a material USER-IMPACT harm — a user hits a wrong or broken
                  result in normal use.
  [compatibility] = a reachable break of a core contract with something outside
                  this change: a published interface, config format, on-disk
                  or wire format, documented flag/behavior, or a supported
                  platform. Breaking a caller that legitimately depends on the
                  old behavior is [compatibility], not [edge].
  [release-integrity] = a defect in what ships or how it ships: version /
                  CHANGELOG / tag disagreement, an installer or release gate
                  that would emit or publish the wrong artifact, or a shipped
                  file that does not match what the release claims.
  [edge]        = bounded, recoverable misbehavior on unlikely input.
  [theoretical] = proven unreachable under supported real-world execution
                  (not merely unlikely).
  [hardening]   = a security-relevant weakness that requires adversarially-
                  crafted, exotic, or extremely-low-frequency input (obscure
                  shell-grammar corners, parser edge cases) AND has NO credible
                  reachable high-impact path: a defense-in-depth gap whose only
                  "attacker" is someone crafting pathological input to defeat a
                  guardrail with no realistic damage beyond it. [hardening] is
                  FORBIDDEN when a realistic attacker can reach the path —
                  reachability wins over rarity.
GOVERNING RULE for ALL marginal tags: [edge], [theoretical], and [hardening]
are valid ONLY when the defect has no credible reachable high-impact
consequence. A rare-but-reachable data-loss, security, compatibility,
release-integrity, or wrong-result defect MUST take a MATERIAL tag regardless
of rarity, recoverability, or blast radius.
A finding with no severity tag is treated as material.
PRECEDENCE — the severity tag always wins over the [blocker]/[debt]
declaration; the declaration can only CONFIRM it, never override it:
  * [debt] on a material severity does NOT demote it — it still blocks.
  * [blocker] with no severity tag is MALFORMED and still blocks (it is not
    downgraded to debt; "no category named" is not a free pass).
  * [blocker] on a marginal severity blocks on the higher claim.
Every disagreement is reported to the owner as a mislabel. Classify honestly
in ONE pass: the labels are a contract, not a lever.
Place the severity tag at the VERY START of the finding, in the leading
bracket cluster (immediately after [BUG]/[DRIFT]) — a tag appearing only in
the body text does not count, and more than one severity tag on a finding is
treated as untagged.'
if (( SECURITY_MODE )); then
    SEVERITY_RULES+='
The two groups and their consequences (DEEP SECURITY REVIEW mode): MATERIAL
(BLOCKER) = [data-loss] | [security] | [correctness] | [compatibility] |
[release-integrity] | [hardening] | untagged — blocks the commit while the loop
is still converging (in this opt-in mode hardening gaps block like real bugs,
so a [debt][hardening] finding still blocks here). MARGINAL (DEBT) = [edge] |
[theoretical] — may be allowed-with-caveat once the round cap is reached. At
the hard convergence ceiling, ANY still-open MATERIAL finding blocks and
escalates to the owner for a decision (ADR-028) — the ceiling stops the review
loop, it does not override a blocker. Only marginal residue self-terminates
with a caveat, so tag precisely.'
else
    SEVERITY_RULES+='
The two groups and their consequences (quality-gate mode): MATERIAL (BLOCKER) =
[data-loss] | [security] | [correctness] | [compatibility] |
[release-integrity] | untagged — blocks the commit while the loop is still
converging, and still blocks at the hard ceiling, where it escalates to the
owner for a decision (ADR-028). MARGINAL (DEBT) = [edge] | [theoretical] |
[hardening] — NEVER blocks: debt findings are surfaced to the owner under a
the "Non-blocking debt" section and the commit proceeds. If only debt
remains, the review is DONE — say so and stop; do not go looking for smaller
issues. Tag precisely in BOTH directions: a marginal tag on a reachable
high-impact defect lets a real bug through; a material tag on an exotic
guardrail gap blocks a healthy commit.'
fi
SEVERITY_RULES+='
Output ONLY the findings list — no preamble, no closing summary. Any prose
outside a list item is treated as one additional MATERIAL finding.'

# ADR-022 mode framing shared by all four prompt variants. Default = quality
# gate (converge in one round on realistic-impact findings only); security
# mode = the full adversarial brief the gate always used, made explicit.
if (( SECURITY_MODE )); then
    ROLE_LINE="You are the independent adversarial reviewer in a two-model workflow, running an explicit DEEP SECURITY REVIEW (owner opt-in)."
    MODE_BRIEF="Hunt exhaustively with an adversarial mindset: fuzzing, parser
hardening, exotic shell grammar, adversarially-crafted input, and every
correctness and data-integrity angle. Deep-hardening findings are in scope
and block in this mode."
else
    ROLE_LINE="You are the ENGINEERING QUALITY GATE in a two-model workflow."
    MODE_BRIEF="This is a quality gate, not a penetration test. Prioritize
correctness bugs, regressions, data loss, broken logic, compatibility breaks,
release-integrity defects, and other high-confidence problems a user would
actually hit. Report realistic security issues — a credible attacker can reach
the path and the impact is high — those block. Do NOT recursively harden
against increasingly exotic, adversarially-crafted, or extremely-low-frequency
input: tag such deep-hardening/parser-corner findings [hardening] so they route
to the \"Non-blocking debt\" section instead of blocking. Once the change is
materially correct and verified, STOP — a review that reaches that state and
reports only debt is COMPLETE, not unfinished."
fi

if [[ -n "$SPEC" ]]; then
    PROMPT="$ROLE_LINE
$MEMORY_BLOCK

An approved plan was written by the other AI (Claude) BEFORE this diff. Review
the outgoing git diff on TWO axes: (1) DRIFT from the plan — steps missed,
scope added that the plan never approved, silent changes; and (2) correctness
bugs, edge cases, security, data integrity. Style nits do not count.
$MODE_BRIEF

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
    PROMPT="$ROLE_LINE
$MEMORY_BLOCK

Review this outgoing git diff for correctness bugs, edge cases, security,
and data integrity. Style nits do not count.
$MODE_BRIEF

Do ONE EXHAUSTIVE pass: list EVERY real finding you can see NOW, most severe
first. Do NOT hold a deeper issue back for a later round — surfacing one
finding per recommit wastes a converged retry and lets real bugs hide behind
cosmetic ones. If you can find it, report it now. For each finding give
file:line, the concrete failure scenario, and the fix.
$SEVERITY_RULES
If nothing significant, reply exactly: LGTM"
fi

# Diff-only fallback prompt for when we CANNOT cd into $DIR — same review, but
# with the filesystem-context instruction ($MEMORY_BLOCK) removed so Codex is
# never told to read files it would resolve against the WRONG directory. The
# prior-findings/[LATE]/converged framing is intentionally dropped here too:
# without the repo cwd this is a pure diff-only cold review (the pre-ADR-019
# behavior). Uses the spec branch's drift framing when a fresh plan exists.
if [[ -n "$SPEC" ]]; then
    PROMPT_NOCTX="$ROLE_LINE
An approved plan was written by the other AI (Claude) BEFORE this diff. Review
the outgoing git diff on TWO axes: (1) DRIFT from the plan; and (2) correctness
bugs, edge cases, security, data integrity. Style nits do not count. Review the
DIFF ONLY — do not attempt to read repository files.
$MODE_BRIEF
Do ONE EXHAUSTIVE pass, tagging each [DRIFT] or [BUG], most severe first.
For each finding give file:line, the concrete failure scenario, and the fix.
$SEVERITY_RULES
If the diff faithfully implements the plan with no significant issue, reply
exactly: LGTM

--- APPROVED PLAN ---
$SPEC
--- END PLAN ---"
else
    PROMPT_NOCTX="$ROLE_LINE
Review this outgoing git diff for correctness bugs, edge cases, security, and
data integrity. Style nits do not count. Review the DIFF ONLY — do not attempt
to read repository files.
$MODE_BRIEF
Do ONE EXHAUSTIVE pass: list EVERY real finding you can see NOW, most severe
first. For each finding give file:line, the concrete failure scenario, and the fix.
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
# The exact slice transmitted to Codex this round; its REAL byte size feeds the
# ADR-019 cumulative diff budget, accumulated in the rounds transaction below.
# The script exports LC_ALL=C globally, so `wc -c` (and ${#..}) already count
# BYTES not characters — but wc -c is used explicitly so the byte semantics are
# self-evident and survive any future locale change (finding 6). Slice computed
# once so the count is of precisely what is sent.
SENT="${DIFF:0:150000}"
SENT_BYTES=$(printf '%s' "$SENT" | LC_ALL=C wc -c | tr -d ' ')
[[ "$SENT_BYTES" =~ ^[0-9]+$ ]] || SENT_BYTES=0
# Run read-only FROM THE REPO so Codex's file reads resolve to the real project
# (ADR-019 project context). CRITICAL: the prompt instructs Codex to READ
# surrounding files, so it must ONLY run with that prompt when we have actually
# `cd`-ed INTO $DIR. If the cd fails (repo vanished / became inaccessible between
# diff collection and review), running the context prompt from the gate's own cwd
# would let Codex read and transmit an UNRELATED repository outside the
# owner-approved boundary AND judge the wrong code. So on cd failure we fall back
# to a DIFF-ONLY prompt from a FRESH EMPTY temp directory (NOT $HOME, which may
# hold credentials or other private repos a tool-driven reviewer could inspect) —
# the pre-ADR-019 cold review — never the context prompt against the wrong tree.
# Either way the commit is never blocked on this. $PROMPT_NOCTX is the same
# review without the file-reading context (built below).
# The context prompt is used ONLY when BOTH (a) we can cd into the repo AND (b)
# the context layer is trustworthy (CTX_OK — flock present). Without flock the
# ledger/rounds state can't be read/written consistently, so the whole ADR-019
# layer degrades to the pre-ADR-019 diff-only cold review even from the right cwd.
if (( CTX_OK )) && ( cd "$DIR" 2>/dev/null ); then
    ( cd "$DIR" && printf '%s' "$SENT" | timeout 180 codex exec \
        --skip-git-repo-check -s read-only -o "$OUT" "$PROMPT" >/dev/null 2>&1 )
    RC=$?
else
    # Diff-only fallback — reached when cd into $DIR failed OR the context layer is
    # untrusted (no flock). Run from a throwaway EMPTY dir so a tool-driven reviewer
    # has no unrelated files to read, with the diff-only prompt (no "read the repo"
    # instruction). If even the temp dir can't be made, fail OPEN without calling
    # Codex (RC=1 → the fail-open path below) rather than review from an unknown cwd.
    NEUTRAL=$(mktemp -d 2>/dev/null)
    if [[ -n "$NEUTRAL" && -d "$NEUTRAL" ]]; then
        ( cd "$NEUTRAL" && printf '%s' "$SENT" | timeout 180 codex exec \
            --skip-git-repo-check -s read-only -o "$OUT" "$PROMPT_NOCTX" >/dev/null 2>&1 )
        RC=$?
        rmdir "$NEUTRAL" 2>/dev/null || true
    else
        RC=1   # no isolated cwd → do not invoke Codex from an unknown dir; fail open
    fi
fi
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
    # Publish under the per-hash lock at round 0 so a concurrent deny/cap_stopped
    # review of the SAME diff (same hash, different verdict) is never erased by a
    # late-finishing LGTM — round 0 is below every real round and refuses to
    # replace a round-bearing marker.
    publish_round_marker "$CACHE/$HASH" 'lgtm' 0
    log_event codex verdict "$(jq -cn "${DUR_ARG[@]}" '{verdict:"lgtm", findings:0, duration_ms:$dur}')"
    log_event system outcome "$(jq -cn '{result:"passed"}')"
    MSG="✓ Codex review: LGTM$MODE_TAG"
    CTX="Codex review of this diff: LGTM (no findings).$MODE_TAG"
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
# forgets the tag must never unlock the cap). MARGINAL = edge | theoretical |
# hardening — except in security mode (ADR-022), where hardening is MATERIAL.
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
            data-loss|security|correctness|compatibility|release-integrity|edge|theoretical|hardening)
                sev="$t"; n=$(( n + 1 )) ;;
            *) ;;   # non-severity tags ([bug]/[drift]/[blocker]/[debt]) pass through
        esac
    done
    if (( n == 1 )); then printf '%s' "$sev"; else printf 'untagged'; fi
}

# ADR-028: the DECLARATION tag the reviewer must state on every finding —
# [blocker] or [debt] — read from the same leading bracket cluster as sev_label.
# It is a cross-check on the severity tag, never a substitute for it: the
# precedence rules below let a declaration only ever CONFIRM the severity, so a
# reviewer cannot demote a real defect by typing [debt] nor promote a nit by
# typing [blocker].
#
# A CONTRADICTORY cluster ([blocker] AND [debt] both present) must resolve the
# same direction every other ambiguity in this file resolves: toward BLOCKING.
# Returning 'undeclared' there would fail OPEN — the marginal arms below test
# for `blocker`, so dropping a stated [blocker] on an [edge]/[theoretical]
# finding silently discards the higher claim and ALLOWS the commit, which is the
# very evasion this cross-check exists to catch. (A [debt] alongside it changes
# nothing on its own: [debt] can never demote anything.) So `blocker` is detected
# by whether the cluster CONTAINS it — contains, not equals — mirroring
# sec_in_cluster() below, which already handles this same multi-tag hazard. Only
# the leading cluster is scanned, so a tag quoted in later evidence cannot vote.
#
# A contradictory cluster is ALSO reported: `decl_contradictory()` answers it
# separately, so the owner is told the reviewer declared both ways on ANY
# severity. Folding that into the return value would mean re-teaching every
# severity arm a fourth state; asking a second question keeps each arm's test
# (`== blocker` / `== debt`) exactly as it reads today.
decl_label() {
    local first t decl="" saw_blocker=0 n=0
    first=${1%%$'\n'*}
    first=$(tr '[:upper:]' '[:lower:]' <<<"$first")
    first=${first#"${first%%[![:space:]]*}"}
    first=${first#\*\*}
    while [[ "$first" =~ ^\[([a-z-]+)\][[:space:]]*(.*)$ ]]; do
        t="${BASH_REMATCH[1]}"; first="${BASH_REMATCH[2]}"
        case "$t" in
            blocker) saw_blocker=1; decl="$t"; n=$(( n + 1 )) ;;
            debt) decl="$t"; n=$(( n + 1 )) ;;
            *) ;;
        esac
    done
    # Fail closed: any cluster naming [blocker] keeps the blocking claim, even
    # when contradicted or repeated. Otherwise a single tag stands; anything else
    # (neither tag, or a repeated [debt]) is 'undeclared' and the severity alone
    # decides — the pre-existing, already-fail-closed behaviour.
    if (( saw_blocker )); then printf 'blocker'
    elif (( n == 1 )); then printf '%s' "$decl"
    else printf 'undeclared'; fi
}
# Did the leading cluster declare BOTH ways? Echoes 1/0. Kept separate from
# decl_label so the verdict logic stays two-valued while the owner still learns
# the reviewer contradicted itself — on a MATERIAL severity the attempted [debt]
# demotion would otherwise go unreported, because decl_label (correctly) resolves
# the cluster to `blocker` and the material arm only notes a lone [debt].
decl_contradictory() {
    local first t b=0 d=0
    first=${1%%$'\n'*}
    first=$(tr '[:upper:]' '[:lower:]' <<<"$first")
    first=${first#"${first%%[![:space:]]*}"}
    first=${first#\*\*}
    while [[ "$first" =~ ^\[([a-z-]+)\][[:space:]]*(.*)$ ]]; do
        t="${BASH_REMATCH[1]}"; first="${BASH_REMATCH[2]}"
        case "$t" in blocker) b=1 ;; debt) d=1 ;; *) ;; esac
    done
    (( b && d )) && printf 1 || printf 0
}
# ADR-019 finding 16 / ADR-028: at the ceiling ANY material finding now blocks,
# so this no longer decides IF the ceiling blocks — it decides HOW. A still-open
# [security]/[data-loss] finding produces a DURABLE escalation (escalated=1,
# survives identical-diff retries); other material residue denies without the
# durable escalation, so fixing it and retrying is enough. `sev_label` returns 'untagged' for a
# MULTI-severity cluster like [security][correctness], which would hide the
# security tag — so security presence is detected SEPARATELY, by whether the
# leading bracket cluster CONTAINS a security/data-loss tag (contains, not
# equals). Only the leading cluster is scanned (mirrors sev_label), so a
# security tag quoted in later evidence text does not count.
sec_in_cluster() {
    local first t
    first=${1%%$'\n'*}
    first=$(tr '[:upper:]' '[:lower:]' <<<"$first")
    first=${first#"${first%%[![:space:]]*}"}
    first=${first#\*\*}
    while [[ "$first" =~ ^\[([a-z-]+)\][[:space:]]*(.*)$ ]]; do
        t="${BASH_REMATCH[1]}"; first="${BASH_REMATCH[2]}"
        [[ "$t" == security || "$t" == data-loss ]] && { printf 1; return; }
    done
    printf 0
}
MATERIAL_COUNT=0; SEV_SUMMARY=""; SEC_COUNT=0; MISLABELED=""
for fitem in "${FINDINGS[@]}"; do
    lbl=$(sev_label "$fitem")
    dcl=$(decl_label "$fitem")
    # A cluster declaring BOTH ways is surfaced on EVERY severity path. The
    # per-severity arms below key off the resolved `$dcl`, which is `blocker` for
    # a contradictory cluster — so without this the attempted [debt] demotion on
    # a material finding would block correctly but silently, and the owner would
    # never learn the reviewer contradicted its own contract.
    contradictory=$(decl_contradictory "$fitem")
    [[ "$contradictory" == 1 ]] && MISLABELED+="${MISLABELED:+; }[blocker] and [debt] both declared on a [$lbl] finding — contradictory declaration, blocking on the higher claim"
    # ADR-028 precedence — FAIL-CLOSED in every ambiguous case. The severity tag
    # decides materiality; the declaration tag can only agree with it. Any
    # disagreement resolves toward BLOCKING and is recorded in MISLABELED so the
    # owner sees that the reviewer classified against the contract.
    case "$lbl" in
        edge|theoretical)
            # Marginal severity. [blocker] on marginal severity means the
            # reviewer believes there IS material harm but tagged the severity
            # wrong — trust the higher claim and block (mislabeled, surfaced).
            if [[ "$dcl" == blocker ]]; then
                MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
                # Skip when already reported as contradictory above — one finding
                # earns one mislabel note, not two overlapping ones.
                [[ "$contradictory" == 1 ]] || MISLABELED+="${MISLABELED:+; }[blocker] declared on a [$lbl] finding — blocking on the higher claim"
            fi ;;
        hardening)
            # ADR-022: marginal by default (non-blocking debt), material under
            # the explicit deep-security opt-in — so [debt][hardening] still
            # blocks with /ship --security, as that mode intends.
            if (( SECURITY_MODE )); then
                MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
            elif [[ "$dcl" == blocker ]]; then
                MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
                [[ "$contradictory" == 1 ]] || MISLABELED+="${MISLABELED:+; }[blocker] declared on a [hardening] finding — blocking on the higher claim"
            fi ;;
        untagged)
            # Anti-evasion floor, unchanged: no parseable harm category means
            # the reviewer never tied this to material harm. It still counts
            # MATERIAL and still blocks — a [blocker] with no category is
            # malformed, and is NEVER downgraded to debt on that basis.
            MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
            [[ "$dcl" == blocker ]] && MISLABELED+="${MISLABELED:+; }[blocker] names no harm category — malformed, blocking"
            [[ "$dcl" == debt ]] && MISLABELED+="${MISLABELED:+; }[debt] on an untagged finding — no harm category to justify it, blocking" ;;
        *)
            # Material severity: data-loss | security | correctness |
            # compatibility | release-integrity. Always blocks. A [debt]
            # declaration here is an attempted demotion of a real defect and is
            # refused outright.
            MATERIAL_COUNT=$(( MATERIAL_COUNT + 1 ))
            [[ "$dcl" == debt ]] && MISLABELED+="${MISLABELED:+; }[debt] declared on a [$lbl] finding — a material defect cannot be demoted, blocking" ;;
    esac
    [[ "$(sec_in_cluster "$fitem")" == 1 ]] && SEC_COUNT=$(( SEC_COUNT + 1 ))
    SEV_SUMMARY+="${SEV_SUMMARY:+,}$lbl"
done
# ADR-019 findings 17+18: a malformed / prose-unparsed reply whose RAW text names
# a security or data-loss defect must also block at the ceiling — a security tag
# anywhere in the raw review (case-insensitive, matching sev_label's lowercasing)
# forces SEC_COUNT>0 so the ceiling-allow can never let it slip past the
# per-finding cluster scan.
if (( SEC_COUNT == 0 )); then
    _rl=$(tr '[:upper:]' '[:lower:]' <<<"$REVIEW")
    [[ "$_rl" == *'[security]'* || "$_rl" == *'[data-loss]'* ]] && SEC_COUNT=1
fi
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
# (repo, HEAD). SCHEMA (ADR-019): "<finding_count> <material_count> <summary>
# <sent_bytes>" — a 4th field carrying the bytes ACTUALLY transmitted to Codex
# this round, so the cumulative diff-budget ceiling is computed from the SAME
# locked transaction as the round increment (finding 10 atomicity). LEGACY
# 3-field lines "<count> <material> <summary>" (written by a pre-ADR-019 gate
# before HEAD moved) are still counted toward the round total + trajectory, but
# contribute 0 bytes — so a mixed file across a straddling upgrade never
# undercounts rounds (finding 11). Key is the CANONICAL repo path + HEAD.
# Read + append + byte-sum happen inside ONE bounded flock critical section:
# per-append locking alone would let two concurrent reviews compute the same
# round number OR both read a stale remaining budget and slip past the ceiling.
# Lock/flock failure leaves ROUND empty → the strict pre-cap behaviour (deny
# with findings), never a cap unlock. No delete path: HEAD movement orphans the
# file and the 24h sweep above reaps it.
ROUND=""; TRAJECTORY=""; CUM_BYTES=0
if command -v flock >/dev/null 2>&1; then
    # shellcheck disable=SC2016  # single quotes intentional: $1..$3 are bash -c positionals
    # Round number, trajectory, and cumulative bytes are computed from
    # SCHEMA-VALID lines only — BOTH the new 4-field form and the legacy 3-field
    # form. A corrupt/torn record matching neither can inflate none of the three.
    # set -e inside the critical section: a failed append (disk full, bad perms)
    # MUST abort before the round number / trajectory / bytes are emitted — a
    # half-done append that still printed "prior+1" would advance the cap off a
    # file that never got this round's line. On abort bash -c exits non-zero,
    # ROUNDS_OUT has no "|", ROUND stays empty → strict pre-cap deny (safe).
    # The schema regexes are END-ANCHORED so a prior crashed append's
    # newline-less final line merged with this record ("2 0 edge3 0 edge 40")
    # matches NEITHER and is simply not counted (an UNDERCOUNT — the safe
    # direction; it can never prematurely reach the cap). grep -c exits 1 on
    # ZERO matches (fresh file) — mapped to 0 — but >1 on a real error (aborts).
    # awk exits >0 on a read/processing error → abort under set -e. NEW=4-field,
    # LEG=legacy-3-field; the round count is NEW+LEG, bytes sum field 4 of NEW.
    ROUNDS_OUT=$(flock -w 2 "$ROUNDS_FILE.lock" bash -c '
        set -e
        f="$1"; line="$2"
        RE_NEW="^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$"
        RE_LEG="^[0-9]+ [0-9]+ [^[:space:]]+$"
        prior_new=0; prior_leg=0
        if [ -f "$f" ]; then
            prior_new=$(grep -cE "$RE_NEW" "$f" 2>/dev/null) \
                || { rc=$?; [ "$rc" -eq 1 ] && prior_new=0 || exit "$rc"; }
            prior_leg=$(grep -cE "$RE_LEG" "$f" 2>/dev/null) \
                || { rc=$?; [ "$rc" -eq 1 ] && prior_leg=0 || exit "$rc"; }
        fi
        case "$prior_new" in ""|*[!0-9]*) prior_new=0 ;; esac
        case "$prior_leg" in ""|*[!0-9]*) prior_leg=0 ;; esac
        printf "%s\n" "$line" >> "$f"
        # trajectory over BOTH schemas (field 1 = finding count), in file order.
        traj=$(awk "/$RE_NEW/||/$RE_LEG/{printf \"%s%s\", sep, \$1; sep=\"->\"}" "$f")
        # cumulative transmitted bytes = sum of field 4 over 4-field lines only
        # (legacy lines have no field 4 → contribute 0). Includes the line just
        # appended, so the ceiling sees THIS round'"'"'s bytes.
        bytes=$(awk "/$RE_NEW/{s+=\$4} END{printf \"%d\", s}" "$f")
        printf "%s|%s|%s" "$(( prior_new + prior_leg + 1 ))" "$traj" "$bytes"
    ' _ "$ROUNDS_FILE" "$FINDING_COUNT $MATERIAL_COUNT $SEV_SUMMARY $SENT_BYTES" 2>/dev/null)
    # ROUNDS_OUT = "round|trajectory|cumbytes" — parse right-to-left so a
    # trajectory (which never contains "|") can't be confused with the fields.
    if [[ "$ROUNDS_OUT" == *"|"*"|"* ]]; then
        ROUND="${ROUNDS_OUT%%|*}"
        _rest="${ROUNDS_OUT#*|}"
        TRAJECTORY="${_rest%|*}"
        CUM_BYTES="${_rest##*|}"
        [[ "$ROUND" =~ ^[0-9]+$ ]] || { ROUND=""; TRAJECTORY=""; CUM_BYTES=0; }
        [[ "$CUM_BYTES" =~ ^[0-9]+$ ]] || CUM_BYTES=0
    fi
fi
# --- ADR-019 ledger append: record THIS round's findings (fingerprint + text)
# so the NEXT round's prompt can suppress re-raises. Best-effort and entirely
# decoupled from the allow/deny decision — a failure here never blocks. Same
# flock/no-delete/sweep lifecycle as ROUNDS_FILE. Fingerprint = first 16 hex of
# sha256 over the NORMALIZED finding (lowercased, whitespace-collapsed, digits
# that look like line numbers dropped) so the same finding re-worded slightly or
# at a shifted line still matches. Text is newline-flattened + capped to keep
# the file line-oriented.
if [[ -n "$ROUND" ]] && command -v flock >/dev/null 2>&1; then
    # Ledger the parsed list findings AND the synthetic unparsed ones (a
    # prose-only reply or a material preamble). Without the synthetic entries a
    # prose/preamble finding would be memoryless and recur every round — exactly
    # the trickle ADR-019 removes. A helper flattens+normalizes+fingerprints one
    # finding into a ledger line.
    ledger_append_line() {
        local t="$1" norm fp flat
        norm=$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | tr -d '[:digit:]')
        fp=$(printf '%s' "$norm" | sha256sum | cut -c1-16)
        # Flatten to one line, then byte-cap. `cut -c` under the global LC_ALL=C
        # counts BYTES and can split a multibyte (e.g. Arabic) character at the
        # 400-byte boundary; that invalid UTF-8 would land in the ledger and later
        # in the prompt, where codex may reject it and trip fail-open. `iconv
        # -c -f UTF-8 -t UTF-8` drops any trailing incomplete sequence, leaving
        # only valid UTF-8. iconv is near-universal; if absent, fall back to
        # stripping bytes >=0x80 from the capped text (ASCII-only, always valid).
        flat=$(printf '%s' "$t" | tr '\n' ' ' | tr -s ' ' | cut -c1-400)
        if command -v iconv >/dev/null 2>&1; then
            flat=$(printf '%s' "$flat" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)
        else
            flat=$(printf '%s' "$flat" | LC_ALL=C tr -d '\200-\377')
        fi
        LEDGER_LINES+="$fp $ROUND $flat"$'\n'
    }
    LEDGER_LINES=""
    for fitem in "${FINDINGS[@]}"; do ledger_append_line "$fitem"; done
    # Synthetic entries for the unparsed material paths (so they gain memory too):
    #   - a prose-only reply (no list at all) → the raw REVIEW is the finding;
    #   - a material preamble before the first list item → that preamble text.
    if (( ${#FINDINGS[@]} == 0 )); then
        ledger_append_line "prose-unparsed: $REVIEW"
    elif [[ -n "${PREAMBLE//[[:space:]$'\n']/}" ]]; then
        ledger_append_line "preamble-unparsed: $PREAMBLE"
    fi
    if [[ -n "$LEDGER_LINES" ]]; then
        # shellcheck disable=SC2016
        flock -w 2 "$LEDGER_FILE.lock" bash -c 'printf "%s" "$2" >> "$1"' \
            _ "$LEDGER_FILE" "$LEDGER_LINES" 2>/dev/null || true
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

# --- ADR-019 three-tier round state machine ---------------------------------
# The ceiling is CAP-GATED (findings 3+13): nothing terminal happens below CAP —
# below the soft cap EVERY material finding is an ordinary retry-deny, exactly
# as before, regardless of the byte budget. At/above CAP:
#   AT_CEILING  = ROUND >= ROUND_MAX  OR  cumulative sent bytes >= DIFF_BUDGET
# defines the hard stop where the loop self-terminates. Between CAP and the
# ceiling is the NEW middle tier: material findings still DENY (Claude+Codex keep
# converging with memory+context) but WITHOUT owner escalation, so the loop can
# actually reach ROUND_MAX (finding 7). Escalation (a durable owner stop) fires
# ONLY at the ceiling and ONLY for a still-open [security]/[data-loss] finding
# (SEC_COUNT>0, findings 16/17) — the gate refusing to auto-merge a security
# hole. ADR-028 widens that stance: ANY material (BLOCKER) residue at the
# ceiling now denies and goes to the owner, not just security/data-loss. Only
# marginal (DEBT) residue self-terminates with a caveat.
AT_CEILING=0
if [[ -n "$ROUND" ]] && (( ROUND >= CAP )); then
    if (( ROUND >= ROUND_MAX )) || (( CUM_BYTES >= DIFF_BUDGET )); then
        AT_CEILING=1
    fi
fi

# --- Allow-with-caveat: (a) marginal-only at/above CAP (the classic CAP-STOPPED
# path), OR (b) at the ceiling with NO open material finding (ADR-028). Both
# surface every finding to the owner verbatim; the commit just stops being held
# hostage — (a) by edge/theoretical residue, (b) by non-security residue the
# convergence loop could not clear before the hard stop. Material findings below
# the ceiling never take this path; nor does a failed round counter (ROUND empty).
# FINDING_COUNT (not ${#FINDINGS[@]}) is the authoritative open-finding count: a
# prose-only reply has an EMPTY FINDINGS array but FINDING_COUNT=1 (one synthetic
# material finding). Using the array length would route a ceiling prose reply to
# the deny path instead of allow-with-caveat — and since SEC_COUNT already
# accounts for a security tag anywhere in the raw prose (findings 17/18), a
# non-security prose reply must self-terminate like any other non-security residue.
# ADR-022 quality-gate allow: in DEFAULT mode a marginal-only review
# ([hardening]/[edge]/[theoretical], MATERIAL_COUNT==0) allows IMMEDIATELY —
# round 1, not cap-gated, and independent of round-tracking health (the round
# number plays no part in the verdict; a flock failure must not turn a
# non-blocking review into a deny). The findings are surfaced under a labeled
# "Non-blocking debt" section — never silently dropped.
OPT_ALLOW=0
if (( ! SECURITY_MODE )) && (( FINDING_COUNT > 0 )) && (( MATERIAL_COUNT == 0 )); then
    OPT_ALLOW=1
fi
# ADR-028 (owner correction to ADR-019's blanket ceiling allow): the ceiling
# STOPS the loop, it does not override a material blocker. A BLOCKER — any
# MATERIAL finding — still denies at the ceiling and escalates to the owner for
# a decision; only MARGINAL (DEBT) residue self-terminates with a caveat. The
# old blanket allow existed because routine code could be held hostage by an
# endless trickle of exotic findings; ADR-028's classification rule removes that
# risk at the source (theoretical/defensive/cosmetic/edge findings MUST be
# tagged DEBT, and DEBT can never keep the loop alive), so the valve is no
# longer load-bearing and its cost — auto-merging a real correctness,
# compatibility, user-impact, data, security, or release-integrity defect purely
# because the round counter ran out — is no longer paid.
CEIL_ALLOW=0
if [[ -n "$ROUND" ]] && (( AT_CEILING )) && (( SEC_COUNT == 0 )) \
   && (( MATERIAL_COUNT == 0 )) && (( FINDING_COUNT > 0 )); then
    CEIL_ALLOW=1
fi
if (( OPT_ALLOW )) || { [[ -n "$ROUND" ]] && (( FINDING_COUNT > 0 )) && { { (( ROUND >= CAP )) && (( MATERIAL_COUNT == 0 )); } || (( CEIL_ALLOW )); }; }; then
    if (( OPT_ALLOW )); then
        HDR="✓ quality gate PASSED — $FINDING_COUNT non-blocking finding(s) routed to Non-blocking debt"
        # Deliberately NO cache marker for an optional-notes pass: a marker can
        # only carry counts, so a cached retry — possibly in a FRESH session
        # that never saw this review — could not re-surface the findings
        # verbatim (transparency rule). An identical retry therefore re-reviews
        # and re-lists everything; the cost is one extra review on a rare path
        # (this allow normally lands the commit on the same attempt).
        log_event system outcome "$(jq -cn --argjson n "$FINDING_COUNT" \
            --argjson round "${ROUND:-null}" \
            '{result:"passed", optional_review:true, findings:$n, round:$round}')"
        CTX="QUALITY GATE PASSED (ADR-022 default mode): no realistic-impact
defect found — every open finding is MARGINAL ([hardening]/[edge]/
[theoretical]), so the commit is ALLOWED in this round.

Non-blocking debt:
$REVIEW

Surface the findings above to the owner VERBATIM alongside the commit
(transparency rule — never silently dropped). Fixing them is the owner's
option, not a requirement for this commit. For the full adversarial
deep-security review, rerun via /ship --security (CODERV_GATE_SECURITY=1)."
    else
        if (( CEIL_ALLOW )) && (( MATERIAL_COUNT > 0 )); then
            WHY="ceiling reached (round $ROUND/$ROUND_MAX, ${CUM_BYTES}B/${DIFF_BUDGET}B budget) with only NON-security residue open"
            HDR="⚠ CEILING-STOPPED: round $ROUND — $MATERIAL_COUNT non-security material + marginal findings open; loop self-terminated, commit ALLOWED with caveat (findings go to the owner)"
        else
            WHY="round $ROUND reached the cap ($CAP) and EVERY open finding is MARGINAL ([edge]/[theoretical])"
            HDR="⚠ CAP-STOPPED: round $ROUND/$CAP — all $FINDING_COUNT open findings marginal; commit ALLOWED with caveat (findings go to the owner)"
        fi
        # The marker records the ceiling non-security material count so an identical
        # RETRY renders an accurate caveat (a ceiling material-residue allow must NOT
        # be described as "only MARGINAL findings"). ceiling=0 is the classic
        # marginal-only cap stop; ceiling=K>0 means K non-security material findings
        # self-terminated at the hard ceiling. Appended as a new field so a legacy
        # "cap_stopped round=N findings=M" marker (no ceiling=) still parses.
        # ADR-028: CEIL_ALLOW now requires MATERIAL_COUNT==0, so a NEW marker can
        # only ever carry ceiling=0. The field and its reader stay for markers
        # written by pre-ADR-028 versions of this hook, which can still be sitting
        # in a cache directory on this machine.
        CEIL_MAT=0; (( CEIL_ALLOW )) && CEIL_MAT="$MATERIAL_COUNT"
        publish_round_marker "$CACHE/$HASH" "$(printf 'cap_stopped round=%s findings=%s ceiling=%s' "$ROUND" "$FINDING_COUNT" "$CEIL_MAT")" "$ROUND"
        log_event system cap_stopped "$(jq -cn --argjson round "$ROUND" \
            --argjson n "$FINDING_COUNT" --argjson ceil "$CEIL_ALLOW" --arg traj "$TRAJECTORY" \
            '{round:$round, findings:$n, ceiling:($ceil==1), trajectory:$traj}')"
        log_event system outcome "$(jq -cn --argjson n "$FINDING_COUNT" \
            --argjson round "$ROUND" --arg traj "$TRAJECTORY" \
            '{result:"passed", cap_stopped:true, findings:$n, round:$round, trajectory:$traj}')"
        CTX="STOPPED (enforced by the gate): $WHY — the commit is ALLOWED with this
caveat instead of blocked (two-brain-convergence.md: the loop self-terminates on
convergence, not by escalating routine code to the human). Findings trajectory:
$TRAJECTORY. Surface ALL findings below to the owner VERBATIM alongside the
commit (transparency rule — never silently dropped); the owner remains the
arbiter and may still demand fixes.

$REVIEW"
    fi
    [[ -n "$TRUNC_NOTE" ]] && CTX+=$'\n\n'"$TRUNC_NOTE"
    [[ -n "$HIST_NOTE" ]] && CTX+=$'\n\n'"$HIST_NOTE"
    [[ -n "$DRIFT_NOTE" ]] && CTX+=$'\n\n'"$DRIFT_NOTE"
    allow_with_warning "$HDR" "$CTX"
fi

# --- Deny. Escalation (a durable owner stop) fires ONLY at the ceiling with a
# still-open [security]/[data-loss] finding (finding 7: NOT at the soft cap). In
# the middle tier (CAP<=ROUND<ROUND_MAX) and below the cap, a material finding is
# an ORDINARY retry-deny — Claude+Codex keep converging. Changed diffs always get
# fresh reviews; the gate never hard-locks the owner's work.
# ADR-028: escalation at the ceiling is no longer security-only. Any material
# BLOCKER that survives to the ceiling must escalate DURABLY — with escalated=0
# the identical retry re-passes per the adjudicate-then-retry contract, so a
# ceiling deny would be a one-round speed bump and the blocker would ship on the
# second attempt. "Surface that blocker to the owner for a decision" requires the
# deny to persist until the owner acts (fix the diff, or --approve it).
CAP_ESCALATED=0
if [[ -n "$ROUND" ]] && (( AT_CEILING )) && { (( SEC_COUNT > 0 )) || (( MATERIAL_COUNT > 0 )); }; then
    CAP_ESCALATED=1
fi
# Record this diff's own outcome in its marker so a cached retry acts on THIS
# verdict. The escalated flag (finding 9) distinguishes an ordinary/middle-tier
# deny (escalated=0 → identical retry re-passes per the adjudicate-then-retry
# contract, so the loop can reach ROUND_MAX) from a ceiling security block
# (escalated=1 → identical retry stays denied-escalated). No round recorded → no
# marker → the retry re-reviews.
[[ -n "$ROUND" ]] && publish_round_marker "$CACHE/$HASH" "$(printf 'denied round=%s material=%s escalated=%s' "$ROUND" "$MATERIAL_COUNT" "$CAP_ESCALATED")" "$ROUND"
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
    # ADR-028: the ceiling escalates on ANY material BLOCKER, so the headline and
    # the finding-class sentence adapt — a non-security blocker must not be
    # reported to the owner as a "security stop".
    if (( SEC_COUNT > 0 )); then
        CEIL_KIND="SECURITY STOP"
        CEIL_WHICH="$SEC_COUNT of $FINDING_COUNT open finding(s) are
[security]/[data-loss] — the gate will NOT auto-merge a security or data-loss
hole"
    else
        CEIL_KIND="BLOCKER STOP"
        CEIL_WHICH="$MATERIAL_COUNT of $FINDING_COUNT open finding(s) are
BLOCKERs (material impact on users, data, security/privacy, correctness,
compatibility, or release integrity) — the ceiling stops the review loop, it
does NOT override a blocker (ADR-028)"
    fi
    REASON="CEILING-REACHED $CEIL_KIND — ESCALATE TO THE OWNER (round $ROUND at
the hard ceiling: round_max $ROUND_MAX / budget ${CUM_BYTES}B of ${DIFF_BUDGET}B;
findings trajectory: $TRAJECTORY).
$CEIL_WHICH, so this attempt is DENIED
and the review loop is OVER. Only non-blocking DEBT residue self-terminates and
is allowed at the ceiling. Do NOT
fix-and-recommit again on your own judgment: STOP and present the owner the
findings below VERBATIM, plus the options (fix the blocking findings /
owner overrides the gate / park the work). The owner decides; you do not spend
another round. (After the owner decides: either the findings get fixed — a
changed diff earns a fresh review — or, on the owner's explicit in-chat approval,
the decision is recorded with $0 --approve <repo-dir> \"<the owner's words>\"
and the identical commit is retried; the recorded approval passes it once, with
a loud caveat, and is never yours to invent — ADR-023.) (two-brain-convergence.md:
ceiling, ADR-019.)

$REVIEW"
else
    REASON="CODEX REVIEW$MODE_TAG (commit paused once, per the AI workflow rules)$ROUND_NOTE:

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
owner decides, you do not keep re-committing.
If the OWNER explicitly decides to ship this exact diff AS-IS (their words, in
chat), you do not wait for the cap: record the decision and retry the identical
commit — $0 --approve <repo-dir> \"<the owner's words>\" — the approval is keyed
to this exact diff, passes it once, and the gate stays armed for everything else
(ADR-023). Never record an approval the owner did not explicitly give."
    # ADR-022: in default mode, marginal findings riding along with a material
    # deny are RE-LISTED verbatim under the Optional section (not just counted)
    # so the owner never has to re-parse severity tags to see which findings
    # block, and the fix batch targets only what does.
    if (( ! SECURITY_MODE )) && (( FINDING_COUNT > MATERIAL_COUNT )); then
        MARG_LIST=""
        for fitem in "${FINDINGS[@]}"; do
            # ADR-028: a marginal severity carrying a [blocker] declaration was
            # counted MATERIAL above, so it must NOT be re-listed here as
            # non-blocking — the two lists would contradict each other and the
            # owner would be told a blocking finding needs no fix.
            [[ "$(decl_label "$fitem")" == blocker ]] && continue
            case "$(sev_label "$fitem")" in
                edge|theoretical|hardening) MARG_LIST+="- $fitem"$'\n' ;;
            esac
        done
        # Count what was actually listed, not the arithmetic difference: the
        # [blocker]-declared marginals skipped above are material and must not
        # be counted as debt.
        MARG_N=$(grep -c '^- ' <<<"$MARG_LIST" 2>/dev/null || printf 0)
        if [[ -n "${MARG_LIST//[[:space:]$'\n']/}" ]]; then
            REASON+="

Non-blocking debt: the $MARG_N finding(s) below do NOT block and need no fix
for the retry; this deny is for the $MATERIAL_COUNT material finding(s) only.
Debt findings go to the owner at their discretion (or via the /ship --security
deep review):
$MARG_LIST"
        fi
    fi
fi
# ADR-028: a declaration that disagreed with its severity tag is never silently
# resolved — the owner sees that the reviewer classified against the contract.
[[ -n "$MISLABELED" ]] && REASON+="

Mislabeled finding(s) (severity tag wins over the [blocker]/[debt]
declaration): $MISLABELED"
[[ -n "$TRUNC_NOTE" ]] && REASON+=$'\n\n'"$TRUNC_NOTE"
[[ -n "$HIST_NOTE" ]] && REASON+=$'\n\n'"$HIST_NOTE"
[[ -n "$DRIFT_NOTE" ]] && REASON+=$'\n\n'"$DRIFT_NOTE"
if (( CAP_ESCALATED )); then
    # The escalation must be OWNER-visible, not only agent-context: a
    # systemMessage rides alongside the deny so the human sees the cap state
    # in the transcript without relying on the agent to relay it.
    # ADR-028: this line must track CEIL_KIND. Hardcoding "SECURITY STOP" and
    # $SEC_COUNT reported a correctness/compatibility/release-integrity ceiling
    # blocker to the owner as a security stop with "0 security/data-loss
    # finding(s) still open" — i.e. the one owner-visible line said nothing was
    # wrong at the exact moment a real blocker needed a decision. Same defect
    # the deny REASON above already fixed; the systemMessage was missed.
    if (( SEC_COUNT > 0 )); then
        CEIL_MSG_WHICH="$SEC_COUNT security/data-loss finding(s) still open"
    else
        CEIL_MSG_WHICH="$MATERIAL_COUNT blocker(s) still open (material impact — not security)"
    fi
    jq -n --arg r "$REASON" \
        --arg msg "⛔ codex-review-gate CEILING $CEIL_KIND: round $ROUND/$ROUND_MAX, $CEIL_MSG_WHICH — owner decision required (trajectory: $TRAJECTORY)" '{
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
