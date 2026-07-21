#!/usr/bin/env bash
# mint-eid.sh — regression test for the gate's mint_eid() on a DEGRADED host.
#
# mint_eid feeds the live-loop event log, a PURE swallowed side-effect: it must
# NEVER leak to hook stderr and must NEVER silently collapse the eid's
# uniqueness, even when `date` or /dev/urandom is broken/missing. This guards
# the [BUG] found at the gate: an unredirected `date` in mint_eid leaked stderr
# and a naive fix could yield an empty --$$-- token.
#
# Strategy: extract ONLY the mint_eid function body from the gate (the gate runs
# top-to-bottom off stdin, so we can't source it whole), eval it in a throwaway
# shell, then exercise it with a failing `date` shim on PATH and an unreadable
# /dev/urandom substitute. No network, no writes outside mktemp.
#
# <!-- claude-docs-toolkit -->
set -u
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATE="$REPO_ROOT/hooks/codex-review-gate.sh"
[[ -f "$GATE" ]] || { echo "FATAL: gate not found at $GATE"; exit 1; }

TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

# --- extract the mint_eid function body verbatim from the gate --------------
# From the `mint_eid() {` line through its closing `}` at column 0.
EIDFN="$TDIR/mint_eid.sh"
awk '/^mint_eid\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$GATE" > "$EIDFN"
[[ -s "$EIDFN" ]] || { echo "FATAL: could not extract mint_eid from gate"; exit 1; }

# A three-part, non-empty <time>-<pid>-<entropy> eid. Each field must be
# non-empty (no leading/trailing/double dash), so --$$-- style collapse fails.
SHAPE='^[0-9A-Za-z]+-[0-9]+-[0-9A-Za-z]+$'

run_case() {
    # run_case <label> <path-to-degrade-shell-snippet>
    local label="$1" degrade="$2" out err rc
    err="$TDIR/err"
    : > "$err"
    # Fresh subshell: load the fn, apply the degradation, mint one eid.
    # The `2>"$err"` MUST wrap mint_eid *inside* the subshell — a redirect on the
    # outer `out=$(...)` does NOT capture stderr from the nested `$(date)`
    # command substitution, so it would silently miss the very leak we test for.
    out=$(
        # shellcheck disable=SC1090
        source "$EIDFN"
        eval "$degrade"
        mint_eid 2>"$err"
    )
    rc=$?
    (( rc == 0 )) || bad "$label: mint_eid exited $rc"
    # (a) zero stderr — the invisible-logging contract
    if [[ -s "$err" ]]; then bad "$label: leaked stderr: $(tr '\n' ' ' <"$err")"; else ok; fi
    # (b) valid three-part non-empty shape — uniqueness contract survives
    if [[ "$out" =~ $SHAPE ]]; then ok; else bad "$label: bad eid shape: '$out'"; fi
}

echo "mint-eid degraded-host regression"

# 1. Healthy host — baseline: real date + real urandom.
run_case "healthy" ':'

# 2. `date` fails (shadowed by a shim that exits non-zero, writing to stderr).
DBIN="$TDIR/datebin"; mkdir -p "$DBIN"
cat > "$DBIN/date" <<'SH'
#!/usr/bin/env bash
echo "date: simulated failure" >&2
exit 127
SH
chmod +x "$DBIN/date"
run_case "date-fails" "export PATH='$DBIN:\$PATH'"

# 3. /dev/urandom unreadable AND date failing — worst case, both fallbacks fire.
#    We can't chmod /dev/urandom, so redefine od() to simulate an unreadable
#    source (od is what mint_eid uses to read it).
run_case "both-degraded" "export PATH='$DBIN:\$PATH'; od() { echo 'od: cannot read' >&2; return 1; }"

# 4. Uniqueness sanity — two mints differ even under degradation (entropy path).
a=$( source "$EIDFN"; export PATH="$DBIN:$PATH"; mint_eid ) 2>/dev/null
b=$( source "$EIDFN"; export PATH="$DBIN:$PATH"; mint_eid ) 2>/dev/null
if [[ -n "$a" && "$a" != "$b" ]]; then ok; else bad "degraded eids not unique: '$a' == '$b'"; fi

# 5. INTEGRATION — drive the WHOLE hook through a real docs-only skip on a
#    degraded host and prove the three contracts hold END-TO-END, not just at
#    the mint_eid function (cases 1-4 exercise the function in isolation; a leak
#    or an allow/deny change introduced by the surrounding log_skip/log_event
#    call path would slip past them):
#      (a) allow/deny UNCHANGED — a docs-only commit is a SILENT allow, so the
#          hook's STDOUT is exactly empty (deny is signalled by stdout JSON, not
#          by exit status — the hook always exits 0, so an exit-0 check alone
#          would pass even on a deny; stdout-empty is the real allow contract);
#      (b) ZERO hook stderr through the real call path (invisible-logging);
#      (c) the emitted event is specifically a gate_skipped/docs_only carrying a
#          valid three-part eid, with xid == "skip-docs_only-<eid>" (so an
#          empty_diff or other skip cannot satisfy the check by accident).
#    Degradation targets ONLY mint_eid's inputs: a `date` shim that fails the
#    nanosecond form `date +%s%N` (what mint_eid uses) but PASSES plain
#    `date +%s` (what log_event needs for its own ts) — otherwise log_event's jq
#    would drop the event and the test would fail for the wrong reason. Plus a
#    failing `od` shim so the entropy fallback also fires.
#    jq-guarded: only THIS case needs jq (to emit/read the event); cases 1-4 run
#    regardless, so the guard never silently drops existing degraded-host coverage.
if command -v jq >/dev/null 2>&1; then
    # A shim dir whose `date` fails ONLY the %s%N (nanosecond) form.
    IBIN="$TDIR/intbin"; mkdir -p "$IBIN"
    cat > "$IBIN/date" <<'SH'
#!/usr/bin/env bash
# Fail the nanosecond form mint_eid uses; delegate every other form (incl.
# `date +%s`, which log_event needs) to the real date so the event still emits.
for a in "$@"; do
    case "$a" in *%N*) echo "date: simulated %N failure" >&2; exit 127;; esac
done
exec /usr/bin/env -i PATH="/usr/bin:/bin" date "$@"
SH
    chmod +x "$IBIN/date"
    cat > "$IBIN/od" <<'SH'
#!/usr/bin/env bash
echo "od: simulated unreadable urandom" >&2
exit 1
SH
    chmod +x "$IBIN/od"

    # Hermetic repo: disable commit signing and any global hooksPath, so a host
    # with commit.gpgSign=true (no key) or a failing core.hooksPath can't make
    # the seed commit fail and drop us into an unborn repo that later fails for
    # the WRONG reason. Fail LOUDLY if init or the seed commit doesn't succeed.
    IREPO="$TDIR/intrepo"; mkdir -p "$IREPO"
    if ! (
        cd "$IREPO" || exit 1
        git init -q || exit 1
        git config user.email t@t.t && git config user.name t || exit 1
        git config commit.gpgSign false && git config core.hooksPath /dev/null || exit 1
        git commit -q --allow-empty -m init || exit 1
        printf 'x\n' > note.md          # docs-only change → the gate's docs_only skip
        git add note.md || exit 1
    ); then
        bad "integration: temp repo setup failed (init/seed) — skipping case 5 assertions"
    else
    ILOG="$TDIR/intlog.jsonl"
    IOUT="$TDIR/intout"; : > "$IOUT"
    IERR="$TDIR/interr"; : > "$IERR"
    IN=$(jq -cn --arg cmd "git -C $IREPO commit -m x" --arg cwd "$IREPO" \
             '{tool_input:{command:$cmd}, cwd:$cwd}')
    irc=0
    # stdout → a FILE (not $(...), which strips trailing newlines and would let a
    # blank-line hook regression pass the exact-empty check); exit status captured
    # separately so the allow/deny assertion is on bytes, per the approved spec.
    PATH="$IBIN:$PATH" \
    CODERV_LOOP_LOG="$ILOG" \
    CODERV_LOG_OFF=0 \
    bash "$GATE" <<<"$IN" >"$IOUT" 2>"$IERR" || irc=$?
    # (a) silent allow — stdout is EXACTLY empty (zero bytes). Subsumes and beats
    #     a no-deny check: a stray warning, a deny JSON line, or a lone blank line
    #     all make the file non-empty.
    if [[ -s "$IOUT" ]]; then bad "integration: hook stdout not empty (not a silent allow): $(tr '\n' ' ' <"$IOUT")"; else ok; fi
    (( irc == 0 )) || bad "integration: hook exited $irc (secondary sanity — expected 0)"
    # (b) zero hook stderr through the real call path — the invisible contract.
    if [[ -s "$IERR" ]]; then bad "integration: hook leaked stderr: $(tr '\n' ' ' <"$IERR")"; else ok; fi
    # (c) the docs_only skip emits EXACTLY ONE event (a spurious extra event —
    #     a duplicate, or an empty_diff — is itself a regression), and that sole
    #     event is a gate_skipped/docs_only with a valid eid and a correlated xid.
    nlines=$(grep -c '' "$ILOG" 2>/dev/null || echo 0)
    if [[ "$nlines" != "1" ]]; then
        bad "integration: expected exactly 1 emitted event, got $nlines"
    else
        ev=$(cat "$ILOG")
        etype=$(jq -r '.type'           <<<"$ev" 2>/dev/null)
        ersn=$(jq -r '.payload.reason'  <<<"$ev" 2>/dev/null)
        ieid=$(jq -r '.eid'             <<<"$ev" 2>/dev/null)
        ixid=$(jq -r '.xid'             <<<"$ev" 2>/dev/null)
        if [[ "$etype" != "gate_skipped" || "$ersn" != "docs_only" ]]; then
            bad "integration: sole event is not gate_skipped/docs_only: type='$etype' reason='$ersn'"
        elif [[ ! "$ieid" =~ $SHAPE ]]; then
            bad "integration: bad event eid shape: '$ieid'"
        elif [[ "$ixid" != "skip-docs_only-$ieid" ]]; then
            bad "integration: xid not correlated to eid: '$ixid' != 'skip-docs_only-$ieid'"
        else
            ok
        fi
    fi
    fi  # close the hermetic-setup guard
else
    echo "  ~ integration case (5) skipped — jq not available"
fi

# 6. REGRESSION-PROTECT THE COLLISION FIX — the degraded-entropy path must use a
#    SUCCESSFULLY-CREATED mktemp token, not bare $RANDOM$RANDOM. Shim mktemp so it
#    actually CREATES its file under a case-specific TMPDIR and returns a name with
#    a known marker tail; force od to fail; then prove (a) the eid's entropy segment
#    derives from the mktemp token (reverting the fix to $RANDOM$RANDOM makes this
#    FAIL), (b) mint_eid removed the created file (create-then-remove), and (c) no
#    eid* file leaks in the scoped TMPDIR. Not a global /tmp glob (flaky under
#    concurrent gate runs) — a case-specific dir asserted empty.
M6DIR="$TDIR/m6"; mkdir -p "$M6DIR"
M6BIN="$TDIR/m6bin"; mkdir -p "$M6BIN"
# A mktemp shim that really creates the file (so create-then-remove is testable)
# and whose name carries a recognisable marker ("Z9MARKER") the eid must contain.
cat > "$M6BIN/mktemp" <<'SH'
#!/usr/bin/env bash
# Emulate `mktemp <template>`: create a real file whose suffix includes a marker.
tmpl="${!#}"                       # last arg is the template
dir="$(dirname "$tmpl")"
f="$dir/eidZ9MARKER$$"
: > "$f" || exit 1
printf '%s\n' "$f"
SH
chmod +x "$M6BIN/mktemp"
r6=$( source "$EIDFN"; export TMPDIR="$M6DIR"; export PATH="$M6BIN:$PATH"; od() { return 1; }; mint_eid ) 2>/dev/null
# (a) entropy segment (3rd field) must carry the mktemp marker
r6ent="${r6##*-}"
if [[ "$r6ent" == *"Z9MARKER"* ]]; then ok; else bad "case6: eid entropy not from mktemp token: '$r6' (fix reverted?)"; fi
# (b)+(c) the created file must have been removed by mint_eid — scoped dir is empty
if compgen -G "$M6DIR/eid*" >/dev/null 2>&1; then bad "case6: mktemp file leaked (not removed): $(echo "$M6DIR"/eid*)"; else ok; fi

# 7. EMPTY-DIFF SKIP INTEGRATION — the second gate_skipped path. Drive the hook
#    through an empty-diff commit (staged==HEAD, clean worktree) on a degraded
#    host; assert a SILENT allow (stdout exactly empty), zero stderr, and exactly
#    one gate_skipped/empty_diff event with a valid correlated eid. Proves the
#    skip machinery is reason-parameterised, not docs_only-only.
if command -v jq >/dev/null 2>&1; then
    E7REPO="$TDIR/e7repo"; mkdir -p "$E7REPO"
    if ! (
        cd "$E7REPO" || exit 1
        git init -q || exit 1
        git config user.email t@t.t && git config user.name t || exit 1
        git config commit.gpgSign false && git config core.hooksPath /dev/null || exit 1
        git commit -q --allow-empty -m init || exit 1
        # no staged change, clean worktree → the gate's empty-diff skip
    ); then
        bad "case7: empty-diff repo setup failed"
    else
        E7LOG="$TDIR/e7log.jsonl"; E7OUT="$TDIR/e7out"; E7ERR="$TDIR/e7err"; : > "$E7OUT"; : > "$E7ERR"
        E7IN=$(jq -cn --arg cmd "git -C $E7REPO commit -m x" --arg cwd "$E7REPO" \
                 '{tool_input:{command:$cmd}, cwd:$cwd}')
        e7rc=0
        PATH="$IBIN:$PATH" CODERV_LOOP_LOG="$E7LOG" CODERV_LOG_OFF=0 \
            bash "$GATE" <<<"$E7IN" >"$E7OUT" 2>"$E7ERR" || e7rc=$?
        (( e7rc == 0 )) || bad "case7: hook exited $e7rc (expected 0 — a nonzero exit is not an allow)"
        if [[ -s "$E7OUT" ]]; then bad "case7: empty-diff not a silent allow (stdout non-empty): $(tr '\n' ' ' <"$E7OUT")"; else ok; fi
        if [[ -s "$E7ERR" ]]; then bad "case7: hook leaked stderr: $(tr '\n' ' ' <"$E7ERR")"; else ok; fi
        e7n=$(grep -c '' "$E7LOG" 2>/dev/null || echo 0)
        if [[ "$e7n" != "1" ]]; then
            bad "case7: expected exactly 1 event, got $e7n"
        else
            e7ev=$(cat "$E7LOG"); e7t=$(jq -r '.type' <<<"$e7ev"); e7r=$(jq -r '.payload.reason' <<<"$e7ev")
            e7eid=$(jq -r '.eid' <<<"$e7ev"); e7xid=$(jq -r '.xid' <<<"$e7ev")
            if [[ "$e7t" != "gate_skipped" || "$e7r" != "empty_diff" ]]; then bad "case7: sole event not gate_skipped/empty_diff: type='$e7t' reason='$e7r'"
            elif [[ ! "$e7eid" =~ $SHAPE ]]; then bad "case7: bad eid shape: '$e7eid'"
            elif [[ "$e7xid" != "skip-empty_diff-$e7eid" ]]; then bad "case7: xid not correlated: '$e7xid'"
            else ok; fi
        fi
    fi
else
    echo "  ~ empty-diff case (7) skipped — jq not available"
fi

# 8. FINAL DEGRADED BRANCH — both od AND mktemp fail → the $RANDOM$RANDOM last
#    resort. Assert zero stderr, a valid three-part eid, AND that the entropy
#    segment is EXACTLY the deterministic $RANDOM$RANDOM concatenation for a
#    known seed. $RANDOM is a seeded PRNG, so RANDOM=<seed> makes the two
#    expansions deterministic; we compute the EXPECTED value by seeding a
#    reference shell identically. A regression to any FIXED value (e.g. rnd=1)
#    would not equal this expected concatenation and FAILS. mint_eid's earlier
#    subshells (date/od/mktemp) don't consume the parent's $RANDOM, so seeding
#    immediately before the call is sound.
E8SEED=4242
e8exp=$( RANDOM=$E8SEED; printf '%s%s' "$RANDOM" "$RANDOM" )   # expected $RANDOM$RANDOM
e8err="$TDIR/e8err"; : > "$e8err"
r8=$( source "$EIDFN"; od() { return 1; }; mktemp() { return 1; }; RANDOM=$E8SEED; mint_eid 2>"$e8err" )
if [[ -s "$e8err" ]]; then bad "case8: leaked stderr on both-fail: $(tr '\n' ' ' <"$e8err")"; else ok; fi
if [[ "$r8" =~ $SHAPE ]]; then ok; else bad "case8: bad eid shape on both-fail: '$r8'"; fi
# entropy segment (3rd field) must EQUAL the deterministic $RANDOM$RANDOM value
r8ent="${r8##*-}"
if [[ "$r8ent" == "$e8exp" ]]; then ok; else bad "case8: entropy not the \$RANDOM\$RANDOM last-resort: got '$r8ent' expected '$e8exp'"; fi

# 9. MERGE-INCOMING SKIP INTEGRATION — the third gate_skipped path. A merge (or
#    cherry-pick/revert/rebase) on a CLEAN worktree has no outgoing diff, so the
#    gate can't review the incoming commits — it emits gate_skipped/merge_incoming
#    and ALLOWS-WITH-WARNING (a loud "NOT reviewed" notice, still an allow). On a
#    degraded host, assert: exactly one gate_skipped/merge_incoming event with a
#    valid correlated eid; and the allow-with-warning oracle — stdout is NON-EMPTY
#    JSON with a non-empty .systemMessage and NO permissionDecision=="deny" (an
#    empty stdout would FAIL this, so it can't pass on silence).
if command -v jq >/dev/null 2>&1; then
    M9REPO="$TDIR/m9repo"; mkdir -p "$M9REPO"
    if ! (
        cd "$M9REPO" || exit 1
        git init -q || exit 1
        git config user.email t@t.t && git config user.name t || exit 1
        git config commit.gpgSign false && git config core.hooksPath /dev/null || exit 1
        git commit -q --allow-empty -m init || exit 1
        # clean worktree, no staged change → a `git merge` has nothing to review
    ); then
        bad "case9: merge repo setup failed"
    else
        M9LOG="$TDIR/m9log.jsonl"; M9OUT="$TDIR/m9out"; M9ERR="$TDIR/m9err"; : > "$M9OUT"; : > "$M9ERR"
        M9IN=$(jq -cn --arg cmd "git -C $M9REPO merge --no-ff somebranch" --arg cwd "$M9REPO" \
                 '{tool_input:{command:$cmd}, cwd:$cwd}')
        m9rc=0
        PATH="$IBIN:$PATH" CODERV_LOOP_LOG="$M9LOG" CODERV_LOG_OFF=0 \
            bash "$GATE" <<<"$M9IN" >"$M9OUT" 2>"$M9ERR" || m9rc=$?
        (( m9rc == 0 )) || bad "case9: hook exited $m9rc (expected 0 — allow-with-warning still exits 0)"
        if [[ -s "$M9ERR" ]]; then bad "case9: hook leaked stderr: $(tr '\n' ' ' <"$M9ERR")"; else ok; fi
        # allow-with-warning: stdout must be ONE well-formed JSON object (validate
        # the WHOLE output with jq -e first — a valid object followed by malformed
        # trailing data must FAIL, not slip through a lenient field read), carrying
        # a non-empty systemMessage and no deny decision.
        if [[ ! -s "$M9OUT" ]]; then
            bad "case9: empty stdout (expected allow-with-warning JSON)"
        elif ! jq -e . "$M9OUT" >/dev/null 2>&1; then
            bad "case9: stdout is not one well-formed JSON object: $(tr '\n' ' ' <"$M9OUT")"
        else
            m9sys=$(jq -r '.systemMessage // ""' "$M9OUT" 2>/dev/null)
            m9deny=$(jq -r '.hookSpecificOutput.permissionDecision // ""' "$M9OUT" 2>/dev/null)
            if [[ -z "$m9sys" ]]; then bad "case9: no systemMessage warning in stdout"
            elif [[ "$m9deny" == "deny" ]]; then bad "case9: merge_incoming produced a DENY (expected allow-with-warning)"
            else ok; fi
        fi
        # exactly one gate_skipped/merge_incoming event with a correlated eid
        m9n=$(grep -c '' "$M9LOG" 2>/dev/null || echo 0)
        if [[ "$m9n" != "1" ]]; then
            bad "case9: expected exactly 1 event, got $m9n"
        else
            m9ev=$(cat "$M9LOG"); m9t=$(jq -r '.type' <<<"$m9ev"); m9r=$(jq -r '.payload.reason' <<<"$m9ev")
            m9eid=$(jq -r '.eid' <<<"$m9ev"); m9xid=$(jq -r '.xid' <<<"$m9ev")
            if [[ "$m9t" != "gate_skipped" || "$m9r" != "merge_incoming" ]]; then bad "case9: sole event not gate_skipped/merge_incoming: type='$m9t' reason='$m9r'"
            elif [[ ! "$m9eid" =~ $SHAPE ]]; then bad "case9: bad eid shape: '$m9eid'"
            elif [[ "$m9xid" != "skip-merge_incoming-$m9eid" ]]; then bad "case9: xid not correlated: '$m9xid'"
            else ok; fi
        fi
    fi
else
    echo "  ~ merge-incoming case (9) skipped — jq not available"
fi

echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
