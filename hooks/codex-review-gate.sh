#!/usr/bin/env bash
# codex-review-gate — PreToolUse hook for Claude Code (Bash)
#
# Machine gate for the owner's two-model AI workflow: before any commit-
# creating git command runs, the outgoing diff goes to Codex CLI for
# adversarial review. Findings block the commit ONCE — Claude adjudicates
# them (transparency rule: rejected findings must be reported to the owner)
# and a retry of the same diff passes. A changed diff is reviewed afresh.
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
find "$CACHE" -type f -mmin +1440 -delete 2>/dev/null
[[ -f "$CACHE/$HASH" ]] && exit 0

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

PROMPT='You are the independent adversarial reviewer in a two-model workflow.
Review this outgoing git diff for correctness bugs, edge cases, security,
and data integrity. Style nits do not count. Reply with a short numbered
list of REAL findings only. If nothing significant, reply exactly: LGTM'

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
printf '%s' "${DIFF:0:150000}" | timeout 180 codex exec --skip-git-repo-check \
    -s read-only -o "$OUT" "$PROMPT" >/dev/null 2>&1
RC=$?
REVIEW=$(cat "$OUT" 2>/dev/null); rm -f "$OUT"

if [[ $RC -ne 0 || -z "$REVIEW" ]]; then
    allow_with_warning \
        "⚠ codex-review-gate: review failed (rc=$RC) — commit NOT reviewed" \
        "CODEX REVIEW FAILED (exit $RC, possibly a timeout). Tell the owner explicitly; per the AI workflow rules a skipped review must never stay silent."
fi

touch "$CACHE/$HASH"

if [[ "$REVIEW" =~ ^[[:space:]]*LGTM[[:space:].!]*$ ]]; then
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
    jq -n --arg msg "$MSG" --arg ctx "$CTX" '{
        systemMessage: $msg,
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }'
    exit 0
fi

REASON="CODEX ADVERSARIAL REVIEW (commit paused once, per the AI workflow rules):

$REVIEW

Adjudicate each finding: fix what is real BEFORE committing; findings you
reject MUST be listed to the owner with your reason (transparency rule —
never silently dropped). Then retry the commit — this exact diff will not
be blocked again; if you change files, the new diff gets a fresh review."
[[ -n "$TRUNC_NOTE" ]] && REASON+=$'\n\n'"$TRUNC_NOTE"
[[ -n "$HIST_NOTE" ]] && REASON+=$'\n\n'"$HIST_NOTE"
jq -n --arg r "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
    }
}'
exit 0
