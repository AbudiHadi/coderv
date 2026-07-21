#!/usr/bin/env bash
# gate-cap.sh — lifecycle test for the codex-review-gate round cap
# (two-brain-convergence.md CAP-STOPPED, enforced in the machine).
#
# Everything runs against a THROWAWAY $HOME and a throwaway git repo; the
# real codex CLI is replaced by a shim on $PATH that replays a canned review
# from $FAKE_REVIEW. No network, no real reviewer, no writes outside mktemp.
#
# Covers: severity parsing (all 5 tags + mixed + untagged), round persistence
# and trajectory, cap-allow on marginal-only, cap-deny escalation on material,
# prose replies staying material, HEAD-move reset, concurrent fresh reviews
# getting distinct rounds (flock read+append atomicity), and the
# CODERV_GATE_ROUND_CAP validation fallback.
#
# <!-- claude-docs-toolkit -->
set -u
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATE="$REPO_ROOT/hooks/codex-review-gate.sh"
[[ -f "$GATE" ]] || { echo "FATAL: gate not found at $GATE"; exit 1; }
for dep in jq git flock; do
    command -v "$dep" >/dev/null 2>&1 || { echo "FATAL: $dep missing"; exit 1; }
done

TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT
export HOME="$TDIR/home"
mkdir -p "$HOME"

# --- fake codex shim -------------------------------------------------------
# `codex login status` succeeds; `codex exec ... -o <file> <prompt>` swallows
# stdin (the gate pipes the diff in — with pipefail an unread pipe would turn
# printf's SIGPIPE into a bogus review-failed) and copies $FAKE_REVIEW to the
# -o target.
BIN="$TDIR/bin"
mkdir -p "$BIN"
cat > "$BIN/codex" <<'SHIM'
#!/usr/bin/env bash
case "${1:-}" in
    login) exit 0 ;;
    exec)
        cat >/dev/null   # drain the piped diff
        # FAKE_DELAY holds the "review" open so concurrency tests can force
        # two gate runs to overlap deterministically.
        [[ -n "${FAKE_DELAY:-}" ]] && sleep "$FAKE_DELAY"
        out=""
        prev=""
        for a in "$@"; do
            [[ "$prev" == "-o" ]] && out="$a"
            prev="$a"
        done
        [[ -n "$out" && -n "${FAKE_REVIEW:-}" ]] && cat "$FAKE_REVIEW" > "$out"
        exit 0
        ;;
esac
exit 0
SHIM
chmod +x "$BIN/codex"
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

REVIEW_FILE="$TDIR/review.txt"
export FAKE_REVIEW="$REVIEW_FILE"

run_gate() {
    # fresh diff each call so the (repo,HEAD,diff) cache never short-circuits
    jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE"
}
# Fault-injection tests (append failure, unreadable marker) rely on filesystem
# permissions the ROOT user bypasses. CAN_DROP_PRIV is true when we can run a
# single gate invocation as an unprivileged user (nobody) so those permissions
# actually bite; otherwise those checks SKIP loudly rather than pass silently.
CAN_DROP_PRIV=0
NOBODY_GID=""
if [[ "$(id -u)" != "0" ]]; then
    CAN_DROP_PRIV=1   # already unprivileged: plain perms suffice
elif command -v setpriv >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
    # Resolve nobody's REAL primary group — it is `nobody` on some distros,
    # `nogroup` on others; a hardcoded group makes setpriv fail there and the
    # empty output would masquerade as gate behavior.
    NOBODY_GID=$(id -g nobody 2>/dev/null)
    [[ "$NOBODY_GID" =~ ^[0-9]+$ ]] && CAN_DROP_PRIV=2   # root, drop via setpriv
fi
# $TDIR itself is mode 0700 from mktemp -d — nobody cannot even traverse into it
# to reach $HOME/$REPO/cache. Grant traversal on the whole throwaway root so a
# dropped-privilege gate run can reach its inputs (the specific fault is arranged
# by the caller on the narrower target).
[[ "$CAN_DROP_PRIV" == "2" ]] && chmod 0755 "$TDIR"
# Run one gate invocation, as nobody when we are root (CAN_DROP_PRIV==2). setpriv
# failure is made LOUD (a bracketed marker in the output) so a check can detect
# it rather than misread empty output as an allow.
run_gate_faulty() {
    local payload
    payload=$(jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
                 '{tool_input:{command:$cmd}, cwd:$cwd}')
    if [[ "$CAN_DROP_PRIV" == "2" ]]; then
        # Root-owned throwaway repo run as nobody would trip git's dubious-
        # ownership guard (git rev-parse fails → the gate exits without
        # reviewing → empty output that looks like an allow). Mark every repo
        # safe for the dropped user via GIT_CONFIG_* env (no writable HOME
        # needed). setpriv keeps the caller's env unless we clear it, so the
        # gate inherits these.
        printf '%s' "$payload" \
          | setpriv --reuid nobody --regid "$NOBODY_GID" --clear-groups \
              env HOME="$HOME" PATH="$PATH" FAKE_REVIEW="$FAKE_REVIEW" \
                  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' \
                  bash "$GATE" 2>/dev/null \
          || printf '{"__setpriv_failed__":true}'
    else
        printf '%s' "$payload" | bash "$GATE"
    fi
}
bump_diff() { echo "change $RANDOM $1" >> "$REPO/app.sh"; }
rounds_file() {
    local f
    for f in "$HOME/.claude/coderlap/codex-reviewed"/rounds-*; do
        [[ -f "$f" && "$f" != *.lock ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}
new_head() {
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "advance"
    rm -f "$HOME/.claude/coderlap/codex-reviewed"/rounds-*   # isolate scenarios
}

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check() { # check <desc> <condition-exit-status>
    if [[ "$2" == "0" ]]; then ok "$1"; else fail "$1"; fi
}

is_deny()  { jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$1" >/dev/null 2>&1; }
is_allow() { ! is_deny "$1"; }
reason()   { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<<"$1"; }
sysmsg()   { jq -r '.systemMessage // ""' <<<"$1"; }
ctx()      { jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$1"; }

MATERIAL_REVIEW='1. [BUG][correctness] app.sh:1 — wrong result on valid input. Fix: X.'
MARGINAL_REVIEW='1. [BUG][edge] app.sh:1 — bounded recoverable oddity on weird input.
2. [BUG][theoretical] app.sh:2 — cannot occur under real execution.'
UNTAGGED_REVIEW='1. [BUG] app.sh:1 — a finding whose severity tag is missing.'
PROSE_REVIEW='This diff has problems but I will not enumerate them as a list.'
FIVETAG_REVIEW='1. [BUG][data-loss] a
2. [BUG][security] b
3. [BUG][correctness] c
4. [BUG][edge] d
5. [BUG][theoretical] e
6. [BUG][data-loss][edge] two severity tags = untagged = material
7. [BUG] parser accepts "[edge]" in user input — quoted tag in evidence must not classify'

echo "T1: material finding, round 1 -> deny with round + trajectory"
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t1; OUT=$(run_gate)
is_deny "$OUT"; check "denies" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "reason names round 1" $?
grep -q "trajectory: 1" <<<"$(reason "$OUT")"; check "reason carries trajectory" $?
[[ -z "$(sysmsg "$OUT")" ]]; check "no owner escalation below cap" $?

echo "T2: marginal-only, round 2 (< cap) -> still denies, trajectory grows"
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
bump_diff t2; OUT=$(run_gate)
is_deny "$OUT"; check "denies below cap even when marginal" $?
grep -q "round 2 of cap 3" <<<"$(reason "$OUT")"; check "round 2 counted" $?
grep -q "trajectory: 1->2" <<<"$(reason "$OUT")"; check "trajectory 1->2" $?

echo "T3: marginal-only, round 3 (= cap) -> CAP-STOPPED ALLOW with caveat"
bump_diff t3; OUT=$(run_gate)
is_allow "$OUT"; check "allows at cap when all findings marginal" $?
grep -q "CAP-STOPPED" <<<"$(sysmsg "$OUT")"; check "systemMessage says CAP-STOPPED" $?
grep -q "round 3/3" <<<"$(sysmsg "$OUT")"; check "systemMessage carries round/cap" $?
grep -q "theoretical" <<<"$(ctx "$OUT")"; check "findings surfaced verbatim in context" $?
grep -q '"cap_stopped":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "cap_stopped logged" $?

echo "T4: material at round >= cap -> CAP-REACHED deny + owner systemMessage"
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t4; OUT=$(run_gate)
is_deny "$OUT"; check "material stays blocked at cap" $?
grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "reason switches to escalation" $?
grep -q "CAP-REACHED" <<<"$(sysmsg "$OUT")"; check "owner-visible systemMessage on deny" $?
grep -q '"type":"cap_escalated"' "$HOME/.claude/coderlap/loop-events.jsonl"; check "cap_escalated logged" $?

echo "T5: durable escalation — next material round stays escalated"
bump_diff t5; OUT=$(run_gate)
is_deny "$OUT" && grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "round 5 still escalation-worded" $?

echo "T6: HEAD move selects a fresh state file; old state survives (no delete path)"
OLD_RF=$(rounds_file)
OLD_SUM=$(sha256sum < "$OLD_RF")
git -C "$REPO" add -A && git -C "$REPO" commit -qm advance   # HEAD moves; NO state deletion
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
bump_diff t6; OUT=$(run_gate)
is_deny "$OUT"; check "fresh HEAD starts denying again" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "counter reset to round 1 via the new key" $?
NEW_RF=""
for f in "$HOME/.claude/coderlap/codex-reviewed"/rounds-*; do
    [[ -f "$f" && "$f" != *.lock && "$f" != "$OLD_RF" ]] && NEW_RF="$f"
done
[[ -n "$NEW_RF" ]]; check "a distinct state file exists for the new HEAD" $?
[[ "$(sha256sum < "$OLD_RF")" == "$OLD_SUM" ]]; check "old HEAD's state file untouched" $?

echo "T7: untagged findings never unlock the cap"
new_head
printf '%s\n' "$UNTAGGED_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t7-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "untagged severity = material -> deny at round 3" $?
grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "escalates instead of allowing" $?

echo "T8: prose reply (no parseable list) never unlocks the cap"
new_head
printf '%s\n' "$PROSE_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t8-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "prose reply = material -> deny at round 3" $?

echo "T9: severity from the leading tag cluster only; multiple/quoted tags = material"
new_head
printf '%s\n' "$FIVETAG_REVIEW" > "$REVIEW_FILE"
bump_diff t9; OUT=$(run_gate)
RF=$(rounds_file)
[[ -n "$RF" ]]; check "rounds file exists" $?
LINE=$(tail -1 "$RF")
[[ "$LINE" == "7 5 data-loss,security,correctness,edge,theoretical,untagged,untagged" ]]; check "line = '7 5 <5 tags + 2 untagged>' (got: $LINE)" $?

echo "T10: invalid CODERV_GATE_ROUND_CAP falls back to 3; valid cap honored"
new_head
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
bump_diff t10a; OUT=$(CODERV_GATE_ROUND_CAP=abc run_gate)
is_deny "$OUT" && grep -q "of cap 3" <<<"$(reason "$OUT")"; check "cap=abc -> falls back to 3 (denies round 1)" $?
new_head
bump_diff t10b; OUT=$(CODERV_GATE_ROUND_CAP=1 run_gate)
is_allow "$OUT" && grep -q "round 1/1" <<<"$(sysmsg "$OUT")"; check "cap=1 honored (marginal allows at round 1)" $?

echo "T11: concurrent fresh reviews get distinct rounds (flock atomicity)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t11
OUT_A_F="$TDIR/out-a"; OUT_B_F="$TDIR/out-b"
# FAKE_DELAY holds both reviews open past each other's start, so BOTH runs
# are past the cache check before either publishes its marker — the test
# always exercises two real appends, never a cache dedupe.
export FAKE_DELAY=1
run_gate > "$OUT_A_F" & P1=$!
run_gate > "$OUT_B_F" & P2=$!
wait "$P1" "$P2"
unset FAKE_DELAY
RF=$(rounds_file)
LINES=$(grep -c . "$RF" 2>/dev/null)
[[ "$LINES" == "2" ]]; check "exactly two rounds appended (got: $LINES)" $?
R_A=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$OUT_A_F" | grep -o 'round [0-9]*' | head -1)
R_B=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$OUT_B_F" | grep -o 'round [0-9]*' | head -1)
[[ -n "$R_A" && -n "$R_B" && "$R_A" != "$R_B" ]]; check "the two rounds are distinct ($R_A vs $R_B)" $?

echo "T12: material prose BEFORE the list marker never unlocks the cap"
new_head
printf '%s\n' 'CRITICAL: this corrupts data on every run.

1. [BUG][edge] app.sh:1 — minor residue.' > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t12-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "preamble prose = material -> deny at round 3" $?
grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "escalates instead of allowing" $?
RF=$(rounds_file); LINE=$(tail -1 "$RF")
[[ "$LINE" == "2 1 edge,preamble-unparsed" ]]; check "preamble counted in BOTH totals (got: $LINE)" $?

echo "T13: identical retry over CAP-REACHED stays DENIED until the owner overrides"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t13-$i"; OUT=$(run_gate); done
is_deny "$OUT" && grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "round 3 material -> CAP-REACHED deny" $?
OUT=$(run_gate)   # same diff, no bump, NO override
is_deny "$OUT"; check "identical retry WITHOUT override stays denied" $?
grep -q "CODERV_GATE_OWNER_OVERRIDE" <<<"$(reason "$OUT")"; check "deny names the owner-override signal" $?
grep -q "CAP-REACHED escalation open" <<<"$(sysmsg "$OUT")"; check "owner-visible systemMessage on the retry deny" $?
OUT=$(CODERV_GATE_OWNER_OVERRIDE=1 run_gate)   # the owner's explicit call
is_allow "$OUT"; check "owner override passes the identical retry" $?
grep -q "OWNER OVERRIDE" <<<"$(sysmsg "$OUT")"; check "override caveat is loud" $?
grep -q '"owner_override":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "owner_override logged" $?
grep -q '"over_cap_escalation":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "over_cap_escalation logged" $?

echo "T14: an LGTM'd changed diff is never denied by an EARLIER escalation at the same HEAD"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t14-$i"; OUT=$(run_gate); done
grep -q "CAP-REACHED" <<<"$(reason "$OUT")"; check "escalation established at this HEAD" $?
printf '%s\n' "LGTM" > "$REVIEW_FILE"
bump_diff t14-fix; OUT=$(run_gate)
is_allow "$OUT"; check "changed diff reviews LGTM and passes" $?
OUT=$(run_gate)   # identical retry of the LGTM'd diff
is_allow "$OUT"; check "cached LGTM retry passes — not falsely denied by the old escalation" $?
if grep -q "CAP-REACHED" <<<"$(sysmsg "$OUT")"; then
    fail "LGTM retry wrongly carries escalation"
else
    ok "LGTM retry carries no escalation caveat"
fi

echo "T15: retry of a CAP-STOPPED diff keeps its caveat"
new_head
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t15-$i"; OUT=$(run_gate); done
grep -q "CAP-STOPPED" <<<"$(sysmsg "$OUT")"; check "cap-allow established" $?
OUT=$(run_gate)   # identical retry
is_allow "$OUT"; check "cap-stopped retry still passes" $?
grep -q "marginal findings still stand" <<<"$(sysmsg "$OUT")"; check "retry repeats the caveat (never silent)" $?

CACHE_DIR="$HOME/.claude/coderlap/codex-reviewed"
# The most-recently-written cache MARKER (sha256 hex name, not rounds-*/*.lock).
latest_marker() {
    local newest="" f
    for f in "$CACHE_DIR"/*; do
        [[ -f "$f" ]] || continue
        case "${f##*/}" in rounds-*|*.lock|*.tmp.*) continue ;; esac
        [[ -z "$newest" || "$f" -nt "$newest" ]] && newest="$f"
    done
    [[ -n "$newest" ]] && printf '%s' "$newest"
}
# Count published markers (sha256-named files, not rounds-*/*.lock/*.tmp.*) via
# a glob — no `ls | grep` (SC2010) so the suite stays shellcheck-clean.
count_markers() {
    local n=0 f
    for f in "$CACHE_DIR"/*; do
        [[ -f "$f" ]] || continue
        case "${f##*/}" in rounds-*|*.lock|*.tmp.*) continue ;; esac
        n=$((n+1))
    done
    printf '%s' "$n"
}

echo "T16: F1 — a failed rounds APPEND (set -e) leaves ROUND empty (no cap advance, no marker)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t16
if [[ "$CAN_DROP_PRIV" == "0" ]]; then
    echo "  SKIP  append-failure — cannot drop privileges (root without usable setpriv/nobody)"
else
    # Exercise the `set -e`-guarded APPEND specifically (not the flock-open
    # path): flock must SUCCEED, then the `printf >> "$ROUNDS_FILE"` must FAIL.
    # So: pre-create a world-writable lock (flock can open it) and pre-create the
    # rounds file itself UNWRITABLE to the append's user. Root bypasses perms, so
    # the gate runs as nobody; the cache dir stays traversable (0755) but the
    # rounds file is 0444 → nobody's append fails → set -e aborts → ROUND empty →
    # pre-cap deny with NO marker published.
    CANON=$(readlink -f "$REPO" 2>/dev/null || echo "$REPO")
    HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
    RF_KEY=$(sha256sum <<<"${CANON}@${HEAD_SHA}" | cut -d' ' -f1)   # EXACT production key
    RF_PATH="$CACHE_DIR/rounds-$RF_KEY"
    mkdir -p "$CACHE_DIR"; chmod 0755 "$CACHE_DIR"
    : > "$RF_PATH.lock"; chmod 0666 "$RF_PATH.lock"   # flock CAN open this
    : > "$RF_PATH";      chmod 0444 "$RF_PATH"        # append CANNOT write this
    [[ "$CAN_DROP_PRIV" == "2" ]] && chmod -R a+rX "$HOME" "$REPO" 2>/dev/null
    chmod 0444 "$RF_PATH"   # reassert (the -R above would re-grant nothing, but be explicit)
    MARKERS_BEFORE=$(count_markers)
    OUT=$(run_gate_faulty)
    ! grep -q "__setpriv_failed__" <<<"$OUT"; check "privilege drop succeeded (setpriv ran)" $?
    is_deny "$OUT"; check "failed append -> still denies" $?
    grep -q "round tracking unavailable this run" <<<"$(reason "$OUT")"; check "reason says tracking unavailable (ROUND empty)" $?
    ! grep -q "round [0-9]* of cap" <<<"$(reason "$OUT")"; check "no numbered round asserted" $?
    MARKERS_AFTER=$(count_markers)
    [[ "$MARKERS_AFTER" == "$MARKERS_BEFORE" ]]; check "no cache marker published on failed append (got $MARKERS_BEFORE -> $MARKERS_AFTER)" $?
    chmod 0644 "$RF_PATH" 2>/dev/null; rm -f "$RF_PATH" "$RF_PATH.lock" 2>/dev/null
fi
echo "T16b: F1 — a grep I/O ERROR (status >1) inside the lock aborts -> ROUND empty (not silently 0)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# The gate maps grep status 1 (zero matches) to prior=0 but must ABORT on a real
# read error (status >1), so a broken read never yields a numbered round off a
# reset count. Shim a `grep` that returns 2 ONLY for the rounds-schema counter
# call (matched by the EXACT production pattern), delegating everything else to
# the real grep so detection/logging still work.
# TWO things this test must get right (both were bugs in an earlier draft):
#  1. the counter grep only runs when the rounds file EXISTS ([ -f "$f" ]), so
#     pre-create the current-HEAD rounds file with a valid line (else grep is
#     skipped entirely and the shim never fires);
#  2. the shim must match the LITERAL production arg "^[0-9]+ [0-9]+ [^[:space:]]+$"
#     — with a real trailing `$`, no backslash escape.
GREPSHIM_BIN="$TDIR/grepshim"; mkdir -p "$GREPSHIM_BIN"
REAL_GREP=$(command -v grep)
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # these are the GENERATED shim's literals, not ours to expand
  printf 'for a in "$@"; do\n'
  # shellcheck disable=SC2016
  printf '    [ "$a" = %q ] && exit 2\n' '^[0-9]+ [0-9]+ [^[:space:]]+$'
  printf 'done\n'
  # shellcheck disable=SC2016
  printf 'exec %q "$@"\n' "$REAL_GREP"
} > "$GREPSHIM_BIN/grep"
chmod +x "$GREPSHIM_BIN/grep"
# Pre-create the rounds file for THIS (repo,HEAD) so the counter grep actually runs.
CANON16=$(readlink -f "$REPO" 2>/dev/null || echo "$REPO")
HSHA16=$(git -C "$REPO" rev-parse HEAD)
RF16="$CACHE_DIR/rounds-$(sha256sum <<<"${CANON16}@${HSHA16}" | cut -d' ' -f1)"
mkdir -p "$CACHE_DIR"; printf '1 1 correctness\n' > "$RF16"
bump_diff t16b
OUT=$(jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$GREPSHIM_BIN:$PATH" bash "$GATE")
is_deny "$OUT"; check "grep I/O error -> still denies" $?
grep -q "round tracking unavailable this run" <<<"$(reason "$OUT")"; check "grep error -> ROUND empty (tracking unavailable)" $?
! grep -q "round [0-9]* of cap" <<<"$(reason "$OUT")"; check "grep error -> no numbered round (not silently 0)" $?
rm -f "$RF16" "$RF16.lock" 2>/dev/null

echo "T17: F4 — tracking-unavailable deny carries the literal 'round unknown — trajectory unavailable'"
# The canonical no-tracking trigger is a MISSING flock (ROUND never recorded).
# Build a PATH that has every tool the gate needs EXCEPT flock, so the gate's
# `command -v flock` fails for one run — root-agnostic, no privilege drop.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
NOFLOCK_BIN="$TDIR/nfbin"; mkdir -p "$NOFLOCK_BIN"
for tool in jq git awk grep sed sha256sum cat mktemp mv rm find readlink stat date timeout tr sort cut dirname bash mkdir chmod; do
    src=$(command -v "$tool" 2>/dev/null) && ln -sf "$src" "$NOFLOCK_BIN/$tool"
done
ln -sf "$BIN/codex" "$NOFLOCK_BIN/codex"
bump_diff t17
OUT=$(jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$NOFLOCK_BIN" bash "$GATE")
is_deny "$OUT"; check "flock missing -> still denies (cap not applied)" $?
grep -q "round unknown — trajectory unavailable" <<<"$(reason "$OUT")"; check "deny note carries the explicit no-tracking literals" $?
grep -q "round cap was NOT applied" <<<"$(reason "$OUT")"; check "deny note states the cap was not applied" $?

echo "T18: F2 — a garbled cache marker is DENIED on retry, never a fall-through allow"
new_head
printf '%s\n' "LGTM" > "$REVIEW_FILE"
bump_diff t18; OUT=$(run_gate)
is_allow "$OUT"; check "clean diff first passes (LGTM, marker written)" $?
MK=$(latest_marker)
[[ -n "$MK" && "$(cat "$MK")" == "lgtm" ]]; check "an atomic 'lgtm' marker was published" $?
# Corrupt the marker in place to simulate a torn/unknown write, then retry the
# IDENTICAL diff so the cache fast-path reads the garbled marker.
printf 'denied round=9 material' > "$MK"     # denied-prefix but malformed tail
OUT=$(run_gate)
is_deny "$OUT"; check "garbled 'denied' marker (bad tail) -> DENIED, not allowed" $?
grep -q "could not be parsed" <<<"$(reason "$OUT")"; check "deny reason names the unparseable escalation" $?
printf 'wat totally unknown token' > "$MK"    # not lgtm/denied/cap_stopped at all
OUT=$(run_gate)
is_deny "$OUT"; check "unknown marker token -> DENIED (closed classifier, no fall-through)" $?
# A cap_stopped marker of the right SHAPE but violating the invariants
# (round >= cap, findings > 0) must NOT auto-allow: "round=0 findings=0" is
# semantically impossible for a real cap-stop and is treated as a torn write.
printf 'cap_stopped round=0 findings=0' > "$MK"
OUT=$(run_gate)
is_deny "$OUT"; check "invariant-violating cap_stopped (round=0 findings=0) -> DENIED, not allowed" $?
# A well-formed cap_stopped marker (round>=cap, findings>0) DOES ride with caveat.
printf 'cap_stopped round=3 findings=2' > "$MK"
OUT=$(run_gate)
is_allow "$OUT"; check "valid cap_stopped marker (round=3 findings=2) -> ALLOW with caveat" $?
grep -q "marginal findings still stand" <<<"$(sysmsg "$OUT")"; check "valid cap_stopped retry carries the caveat" $?
# Leading-zero fields must be read base-10, not octal: a bare (( 08 >= CAP ))
# is a Bash arithmetic ERROR that would leave CAP_RIDE=0 and WRONGLY allow the
# retry of an open denial. Both marker kinds must survive an "08" field.
printf 'denied round=08 material=01' > "$MK"    # 8>=cap(3), 1>0 -> stays escalated
OUT=$(run_gate)
is_deny "$OUT"; check "octal-looking denied marker (round=08) -> DENIED, no arith error bypass" $?
printf 'cap_stopped round=09 findings=08' > "$MK"   # 9>=cap, 8>0 -> valid cap-stop
OUT=$(run_gate)
is_allow "$OUT"; check "octal-looking cap_stopped (round=09 findings=08) -> ALLOW, parsed base-10" $?
# Denied markers must satisfy their invariants too, not just the shape: round<1
# is impossible, and an at/above-cap denial with material=0 would skip the
# mandatory escalation. Both must route to the unverified deny, never allow.
printf 'denied round=0 material=1' > "$MK"      # round<1 -> impossible
OUT=$(run_gate)
is_deny "$OUT"; check "impossible denied (round=0) -> DENIED, no fall-through allow" $?
printf 'denied round=9 material=0' > "$MK"      # at-cap denial with material=0 -> escalation must not be skipped
OUT=$(run_gate)
is_deny "$OUT"; check "impossible denied (round>=cap, material=0) -> DENIED, escalation not skipped" $?
printf 'denied round=1 material=1' > "$MK"      # valid BELOW-cap denial -> adjudicate-then-retry passes
OUT=$(run_gate)
is_allow "$OUT"; check "valid below-cap denied (round=1) retry -> ALLOW (adjudicate-then-retry contract)" $?
# An oversized numeric field must NOT wrap under 64-bit arithmetic: a marker
# like "denied round=18446744073709551617 material=1" (2^64+1) would 10#-wrap to
# round=1 (< cap) and clear the escalation. Fields are bounded to 1-9 digits, so
# an oversized field fails the anchored match and routes to the unverified deny.
printf 'denied round=18446744073709551617 material=1' > "$MK"
OUT=$(run_gate)
is_deny "$OUT"; check "oversized denied round (2^64+1) -> DENIED, no 64-bit wrap bypass" $?
grep -q "could not be parsed" <<<"$(reason "$OUT")"; check "oversized denied marker routed to the unverified deny" $?
printf 'cap_stopped round=18446744073709551617 findings=1' > "$MK"
OUT=$(run_gate)
is_deny "$OUT"; check "oversized cap_stopped round (2^64+1) -> DENIED, no wrap-to-allow" $?
printf 'lgtm' > "$MK"                          # restore the valid pass marker
OUT=$(run_gate)
is_allow "$OUT"; check "valid 'lgtm' marker still passes (classifier not over-broad)" $?
# A marker that EXISTS as a regular file but cannot be READ must not be
# downgraded to a pass: `cat` yields "" for both a read failure and a legacy-
# empty marker, so the gate distinguishes them (via cat's exit status). The
# fast-path only enters on `-f` (a real file), so a directory can't exercise
# this branch — the marker stays a regular file with read stripped. Root
# bypasses chmod, so the gate runs as nobody (run_gate_faulty); if privilege
# drop isn't available the check SKIPS LOUDLY (never a silent pass).
if [[ "$CAN_DROP_PRIV" == "0" ]]; then
    echo "  SKIP  unreadable-marker deny — cannot drop privileges (root without usable setpriv/nobody)"
else
    printf 'denied round=9 material=1' > "$MK"
    # Make the tree traversable/readable for nobody, THEN strip the marker to
    # 0000 (the recursive chmod would otherwise restore read on it — it lives
    # under $HOME — and the gate would read a valid marker instead of failing).
    [[ "$CAN_DROP_PRIV" == "2" ]] && chmod -R a+rX "$HOME" "$REPO" 2>/dev/null
    chmod 0000 "$MK"
    OUT=$(run_gate_faulty)
    ! grep -q "__setpriv_failed__" <<<"$OUT"; check "privilege drop succeeded (setpriv ran)" $?
    is_deny "$OUT"; check "unreadable marker (read fails) -> DENIED, never a fall-through pass" $?
    grep -q "could not be parsed" <<<"$(reason "$OUT")"; check "unreadable marker routed to the unverified-escalation deny" $?
    chmod 0644 "$MK" 2>/dev/null
fi
rm -f "$MK" 2>/dev/null

echo "T19: F3 — torn rounds-lines (blank tail AND junk multi-token tail) excluded from count+trajectory"
new_head
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
bump_diff t19a; OUT=$(run_gate)   # round 1 -> writes a clean line
RF=$(rounds_file)
# Inject TWO torn lines the end-anchored schema (^N M <one-non-space-token>$)
# must reject: a blank-summary tail, and a junk MULTI-token tail. Both have a
# valid "count material" numeric prefix — the anchoring is what excludes them.
printf '5 5 \n' >> "$RF"             # blank summary field
printf '9 9 edge junk tail\n' >> "$RF"   # extra whitespace-separated tokens
bump_diff t19b; OUT=$(run_gate)   # this run reads RF (torn lines must be ignored)
# Only clean lines count: #1 (t19a) and this run (#2) → round 2, not inflated by
# the two torn lines. Trajectory prints each clean line's FINDING COUNT ($1);
# MARGINAL_REVIEW has 2 findings, so both clean rounds show 2 → "2->2". The
# torn lines' prefixes (5 and 9) must NOT appear.
grep -q "round 2 of cap 3" <<<"$(reason "$OUT")"; check "torn lines excluded from the round count (round 2, not inflated)" $?
grep -q "trajectory: 2->2" <<<"$(reason "$OUT")"; check "torn lines excluded from the trajectory (2->2, no 5/9 junk)" $?
! grep -qE "trajectory:[^\"]*[59]" <<<"$(reason "$OUT")"; check "no torn-line prefix (5 or 9) leaked into the trajectory" $?

echo "T20: marker publication is MONOTONIC — a lower round never overwrites a higher one"
# Two concurrent reviews of the IDENTICAL diff can be assigned different rounds;
# if a lower-round outcome's write lands last it must NOT clobber a higher-round
# marker (which would send the next retry down the wrong cached path). Source the
# publish helpers and exercise the invariant directly (a real race is not
# deterministically reproducible; the guard it relies on is).
MONO_DIR=$(mktemp -d)
# shellcheck source=/dev/null
source <(sed -n '/^write_marker() {/,/^}/p; /^publish_round_marker() {/,/^}/p' "$GATE")
MMF="$MONO_DIR/marker"
printf 'cap_stopped round=3 findings=2' > "$MMF"
publish_round_marker "$MMF" "denied round=2 material=0" "2"   # lower round, must be rejected
[[ "$(cat "$MMF")" == "cap_stopped round=3 findings=2" ]]; check "round-2 publish does NOT overwrite the round-3 marker" $?
publish_round_marker "$MMF" "denied round=4 material=1" "4"   # higher round, must win
[[ "$(cat "$MMF")" == "denied round=4 material=1" ]]; check "round-4 publish DOES supersede the round-3 marker" $?
# Equal round + equal severity (denied vs denied): the existing marker is kept
# (both are blocking escalations of the same diff/round — equivalent, so no
# need to churn the file; ordering is by (round, severity), ties keep incumbent).
publish_round_marker "$MMF" "denied round=4 material=2" "4"
[[ "$(cat "$MMF")" == "denied round=4 material=1" ]]; check "equal round + equal severity keeps the incumbent denied marker" $?
# Severity precedence at EQUAL round: a late cap_stopped (allow-with-caveat, rank
# 1) must NEVER downgrade a same-round denied (block, rank 2) — otherwise the next
# retry reads cap_stopped and is allowed when it should stay blocked. Test BOTH
# publication orders.
printf 'denied round=4 material=1' > "$MMF"
publish_round_marker "$MMF" "cap_stopped round=4 findings=1" "4"   # lower severity, same round
[[ "$(cat "$MMF")" == "denied round=4 material=1" ]]; check "equal-round cap_stopped does NOT downgrade a denied escalation" $?
# The reverse order IS a safe upgrade toward blocking: a denied supersedes a
# same-round cap_stopped.
printf 'cap_stopped round=4 findings=1' > "$MMF"
publish_round_marker "$MMF" "denied round=4 material=1" "4"        # higher severity, same round
[[ "$(cat "$MMF")" == "denied round=4 material=1" ]]; check "equal-round denied DOES supersede a cap_stopped (upgrade toward blocking)" $?
# A strictly-higher round still wins regardless of severity direction (a later
# cap_stopped at round 5 legitimately supersedes a round-4 denied for a diff that
# was re-reviewed to a cap-stop — round dominates when it differs).
printf 'denied round=4 material=1' > "$MMF"
publish_round_marker "$MMF" "cap_stopped round=5 findings=1" "5"
[[ "$(cat "$MMF")" == "cap_stopped round=5 findings=1" ]]; check "strictly-higher round wins even downgrading severity" $?
printf 'denied round=4 material=1' > "$MMF"    # restore for the LGTM tests below
# Concurrent-verdict disagreement: the hash keys the DIFF, not the verdict, so a
# late-finishing LGTM (round 0) of the SAME diff must NEVER erase a deny/cap_stop
# escalation marker — otherwise the next identical retry reads 'lgtm' and allows.
publish_round_marker "$MMF" "lgtm" "0"
[[ "$(cat "$MMF")" == "denied round=4 material=1" ]]; check "late LGTM (round 0) does NOT clobber a round-bearing deny marker" $?
printf 'cap_stopped round=3 findings=2' > "$MMF"
publish_round_marker "$MMF" "lgtm" "0"
[[ "$(cat "$MMF")" == "cap_stopped round=3 findings=2" ]]; check "late LGTM does NOT clobber a cap_stopped marker either" $?
# An oversized round field in an EXISTING marker must not wrap and look 'low',
# letting a real (in-range) round overwrite it: >=10 digits is kept as unbeatably
# high, so even a genuine higher-looking round cannot clobber the corrupt record.
printf 'denied round=18446744073709551617 material=1' > "$MMF"
publish_round_marker "$MMF" "denied round=5 material=1" "5"
[[ "$(cat "$MMF")" == "denied round=18446744073709551617 material=1" ]]; check "oversized existing round treated as high — round-5 publish does NOT wrap-and-clobber" $?
# Edge: an existing round-bearing marker whose round field is itself malformed
# (had_round=1 but cur=0). A round-0 lgtm must STILL be refused — the '-eq 0'
# clause, not the '-lt cur' clause, is what protects this torn-deny case.
printf 'denied round=xyz material=1' > "$MMF"
publish_round_marker "$MMF" "lgtm" "0"
[[ "$(cat "$MMF")" == "denied round=xyz material=1" ]]; check "lgtm does NOT clobber a round-bearing marker with a malformed round field" $?
# A fresh marker file (no existing round) accepts any publish, incl. lgtm.
rm -f "$MMF"
publish_round_marker "$MMF" "lgtm" "0"
[[ "$(cat "$MMF")" == "lgtm" ]]; check "lgtm publishes onto a fresh (no-marker) hash" $?
rm -rf "$MONO_DIR"

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
exit 0
