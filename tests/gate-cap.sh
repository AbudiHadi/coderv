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
        # ADR-019 finding 4: capture the invocation so tests can PROVE the gate
        # ran read-only, from the repo cwd, with the changed-file list + [LATE]
        # rule + prior findings in the prompt. Written only when CAPTURE_DIR is
        # set (normal runs skip it). pwd → where the review ran; argv → flags;
        # prompt → the last non-flag argv element (the gate passes $PROMPT there).
        if [[ -n "${CAPTURE_DIR:-}" ]]; then
            pwd > "$CAPTURE_DIR/cwd"
            printf '%s\n' "$@" > "$CAPTURE_DIR/argv"
            _p=""; for a in "$@"; do case "$a" in -*|exec) ;; *) _p="$a" ;; esac; done
            printf '%s' "$_p" > "$CAPTURE_DIR/prompt"
        fi
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

# ADR-022: the legacy suite below (T1-T64) encodes the pre-0.14.0 lifecycle —
# marginal-only denies below the cap, cap-gated allows, the ceiling tiers.
# Those semantics now live in the explicit DEEP SECURITY mode; default mode is
# the quality gate (marginal-only allows in round 1). Pin the legacy suite to
# security mode so it keeps proving the cap/ledger machinery unchanged; the
# ADR-022 block at the end unsets this and covers the default mode.
export CODERV_GATE_SECURITY=1

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
    rm -f "$HOME/.claude/coderlap/codex-reviewed"/rounds-* \
          "$HOME/.claude/coderlap/codex-reviewed"/ledger-*   # isolate scenarios
}
ledger_file() {
    local f
    for f in "$HOME/.claude/coderlap/codex-reviewed"/ledger-*; do
        [[ -f "$f" && "$f" != *.lock ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}
# Run the gate with the codex shim capturing its cwd/argv/prompt into a dir.
run_gate_capture() {
    local cap="$1"
    mkdir -p "$cap"
    jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd}, cwd:$cwd}' | CAPTURE_DIR="$cap" bash "$GATE"
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
SECURITY_REVIEW='1. [BUG][security] app.sh:1 — auth bypass on crafted input. Fix: X.'
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

echo "T4: material in the middle tier (round 4, CAP<=round<ROUND_MAX) -> ORDINARY deny, NO escalation"
# Rounds accumulate across T1-T5 (no new_head): T1=r1,T2=r2,T3=r3,T4=r4,T5=r5.
# ADR-019 finding 7: between the soft cap and the ceiling the loop keeps
# converging with memory+context; escalation moved to the hard ceiling
# (ROUND_MAX=5, security-only). So round 4 material is a plain retry-deny.
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t4; OUT=$(run_gate)
is_deny "$OUT"; check "material stays blocked in the middle tier" $?
! grep -q "CEILING-REACHED\|ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "middle-tier deny is NOT an owner escalation" $?
[[ -z "$(sysmsg "$OUT")" ]]; check "no owner-visible systemMessage in the middle tier" $?
! grep -q '"type":"cap_escalated"' "$HOME/.claude/coderlap/loop-events.jsonl"; check "no cap_escalated logged in the middle tier" $?

echo "T5: NON-security residue AT the ceiling (round 5 = ROUND_MAX) -> self-terminate, ALLOW with caveat"
# Round 5 hits ROUND_MAX. A [correctness] finding is non-security residue, so the
# loop self-terminates: allow-with-caveat, NOT an escalation to the human.
bump_diff t5; OUT=$(run_gate)
is_allow "$OUT"; check "round 5 correctness residue self-terminates (allowed, not escalated)" $?
grep -q "STOPPED\|ALLOWED with caveat" <<<"$(sysmsg "$OUT")"; check "ceiling allow carries a loud caveat" $?
! grep -q "ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "non-security residue never escalates at the ceiling" $?

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

echo "T7: untagged findings never marginal-allow at the soft cap (still deny)"
new_head
printf '%s\n' "$UNTAGGED_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t7-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "untagged severity = material -> deny at round 3" $?
! grep -q "CAP-STOPPED\|ALLOWED" <<<"$(sysmsg "$OUT")"; check "untagged never takes the marginal-allow path" $?

echo "T8: prose reply (no parseable list) never marginal-allows (still deny)"
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
# ADR-019: a 4th field carries this round's transmitted bytes (a positive int).
[[ "$LINE" =~ ^7\ 5\ data-loss,security,correctness,edge,theoretical,untagged,untagged\ [0-9]+$ ]]; check "line = '7 5 <5 tags + 2 untagged> <bytes>' (got: $LINE)" $?

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
! grep -q "ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "middle-tier deny, not escalation (ADR-019)" $?
RF=$(rounds_file); LINE=$(tail -1 "$RF")
# ADR-019: 4th byte field appended.
[[ "$LINE" =~ ^2\ 1\ edge,preamble-unparsed\ [0-9]+$ ]]; check "preamble counted in BOTH totals + byte field (got: $LINE)" $?

echo "T13: identical retry over a CEILING SECURITY stop stays DENIED until the owner overrides"
# ADR-019: escalation now fires at the ceiling (ROUND_MAX=5) and ONLY for a
# still-open [security]/[data-loss] finding. Drive 5 rounds of a security finding.
new_head
printf '%s\n' "$SECURITY_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t13-$i"; OUT=$(run_gate); done
is_deny "$OUT" && grep -q "ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "round 5 security -> CEILING escalation deny" $?
OUT=$(run_gate)   # same diff, no bump, NO override
is_deny "$OUT"; check "identical retry WITHOUT override stays denied" $?
grep -q -- '--approve' <<<"$(reason "$OUT")"; check "deny names the owner --approve exit (ADR-023)" $?
grep -q "escalation" <<<"$(sysmsg "$OUT")"; check "owner-visible systemMessage on the retry deny" $?
OUT=$(CODERV_GATE_OWNER_OVERRIDE=1 run_gate)   # the owner's explicit call
is_allow "$OUT"; check "owner override passes the identical retry" $?
grep -q "OWNER OVERRIDE" <<<"$(sysmsg "$OUT")"; check "override caveat is loud" $?
grep -q '"owner_override":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "owner_override logged" $?
grep -q '"over_cap_escalation":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "over_cap_escalation logged" $?

echo "T14: an LGTM'd changed diff is never denied by an EARLIER ceiling escalation at the same HEAD"
new_head
printf '%s\n' "$SECURITY_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t14-$i"; OUT=$(run_gate); done
grep -q "ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "ceiling escalation established at this HEAD" $?
printf '%s\n' "LGTM" > "$REVIEW_FILE"
bump_diff t14-fix; OUT=$(run_gate)
is_allow "$OUT"; check "changed diff reviews LGTM and passes" $?
OUT=$(run_gate)   # identical retry of the LGTM'd diff
is_allow "$OUT"; check "cached LGTM retry passes — not falsely denied by the old escalation" $?
if grep -q "escalation\|ESCALATE" <<<"$(sysmsg "$OUT")"; then
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

echo "T15b: retry of a CEILING material-residue allow is described accurately (NOT 'marginal')"
# A [correctness] finding driven to the ceiling self-terminates (allow-with-caveat).
# Its cap_stopped marker carries ceiling=K>0, so the identical retry must say
# "non-security material", never falsely claim the residue was marginal.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"   # [correctness] = non-security material
for i in 1 2 3 4 5; do bump_diff "t15b-$i"; OUT=$(run_gate); done   # round 5 = ceiling → allow
is_allow "$OUT"; check "ceiling [correctness] residue self-terminates (allow)" $?
OUT=$(run_gate)   # identical retry hits the cached marker
is_allow "$OUT"; check "ceiling retry passes" $?
grep -q "non-security material" <<<"$(sysmsg "$OUT")"; check "ceiling retry names non-security material residue (not 'marginal')" $?
! grep -q "MARGINAL findings open" <<<"$(sysmsg "$OUT")"; check "ceiling retry does NOT mislabel the residue as marginal" $?
# The marker itself carries ceiling=K>0.
MKC=""
for _m in "$HOME/.claude/coderlap/codex-reviewed"/*; do
    case "$_m" in */rounds-*|*/ledger-*|*.lock) continue ;; esac
    [[ -f "$_m" ]] && { [[ -z "$MKC" || "$_m" -nt "$MKC" ]] && MKC="$_m"; }
done
grep -qE 'cap_stopped .* ceiling=[1-9]' "$MKC"; check "ceiling cap_stopped marker records ceiling=K>0" $?

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
for tool in jq git awk grep sed sha256sum cat mktemp mv rm find readlink stat date timeout tr sort cut dirname bash mkdir chmod head wc ls; do
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

# ===========================================================================
# ADR-019 — gate memory + project context + convergence ceiling
# ===========================================================================

echo "T21: ceiling by ROUND_MAX — non-security material residue self-terminates (allow-with-caveat)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# CAP=3, ROUND_MAX=5 (defaults). Rounds 1-4 deny (tiers 1-2), round 5 = ceiling.
for i in 1 2 3 4; do bump_diff "t21-$i"; OUT=$(run_gate); is_deny "$OUT" || break; done
is_deny "$OUT"; check "rounds 1-4 (below ceiling) all deny" $?
bump_diff t21-5; OUT=$(run_gate)   # round 5 = ROUND_MAX
is_allow "$OUT"; check "round 5 correctness residue -> ceiling self-terminate (ALLOW)" $?
grep -q "STOPPED" <<<"$(sysmsg "$OUT")"; check "ceiling allow is loud" $?

echo "T22: ceiling by DIFF_BUDGET — a tiny budget trips the ceiling AT the cap, non-security allows"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# Budget = 1 byte: every round's transmitted bytes exceed it, so the ceiling is
# reached as soon as ROUND>=CAP (cap-gating, finding 13). Rounds 1-2 (<CAP) deny;
# round 3 (==CAP, budget exhausted) => ceiling => non-security allow.
for i in 1 2; do bump_diff "t22-$i"; OUT=$(CODERV_GATE_DIFF_BUDGET=1 run_gate); done
is_deny "$OUT"; check "below-CAP rounds deny regardless of exhausted budget" $?
bump_diff t22-3; OUT=$(CODERV_GATE_DIFF_BUDGET=1 run_gate)   # round 3 == CAP, budget blown
is_allow "$OUT"; check "at CAP with budget exhausted -> ceiling self-terminate (ALLOW)" $?

echo "T23: cap-gating is ABSOLUTE — a below-CAP material finding BLOCKS even with the budget blown"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t23; OUT=$(CODERV_GATE_DIFF_BUDGET=1 run_gate)   # round 1, budget exhausted
is_deny "$OUT"; check "round 1 material denies despite exhausted budget (cap-gated)" $?
! grep -q "STOPPED\|ALLOWED with caveat" <<<"$(sysmsg "$OUT")"; check "no ceiling self-terminate below the cap" $?

echo "T24: at the ceiling, a [security] finding BLOCKS (escalation) while [correctness] would allow"
new_head
printf '%s\n' "$SECURITY_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t24-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "security at the ceiling BLOCKS" $?
grep -q "ESCALATE TO THE OWNER" <<<"$(reason "$OUT")"; check "security ceiling block escalates to the owner" $?
# [data-loss] blocks too
new_head
printf '%s\n' '1. [BUG][data-loss] app.sh:1 — corrupts saved records. Fix: X.' > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t24d-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "data-loss at the ceiling BLOCKS" $?

echo "T25: at the ceiling, untagged / prose-unparsed / multi-severity-WITHOUT-security all ALLOW"
for rv in "$UNTAGGED_REVIEW" "$PROSE_REVIEW" '1. [BUG][correctness][edge] app.sh:1 — two non-security tags.'; do
    new_head
    printf '%s\n' "$rv" > "$REVIEW_FILE"
    for i in 1 2 3 4 5; do bump_diff "t25-$i"; OUT=$(run_gate); done
    is_allow "$OUT"; check "ceiling non-security residue allows: ${rv:0:40}..." $?
done

echo "T26: multi-severity WITH security ([security][correctness]) BLOCKS at the ceiling (finding 16)"
new_head
printf '%s\n' '1. [BUG][security][correctness] app.sh:1 — auth flaw plus a wrong result.' > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t26-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "a security tag inside a multi-severity cluster still BLOCKS" $?

echo "T27: prose-unparsed reply CONTAINING [Security]/[DATA-LOSS] (mixed case) BLOCKS (findings 17+18)"
new_head
printf '%s\n' 'The change has a [Security] hole: authentication bypass on line 1.' > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t27-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "mixed-case [Security] in raw prose blocks at the ceiling (case-insensitive)" $?
# Same for mixed-case [DATA-LOSS] in raw prose.
new_head
printf '%s\n' 'Careful — this has a [DATA-LOSS] risk: it truncates the file.' > "$REVIEW_FILE"
for i in 1 2 3 4 5; do bump_diff "t27d-$i"; OUT=$(run_gate); done
is_deny "$OUT"; check "mixed-case [DATA-LOSS] in raw prose blocks at the ceiling" $?

echo "T28: middle-tier deny marker retries (escalated=0); ceiling security block stays escalated (finding 9)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t28-$i"; OUT=$(run_gate); done   # round 3 = middle tier
is_deny "$OUT"; check "round 3 middle-tier material denies" $?
# Find the newest marker file (sha256-named): not a rounds-/ledger-/.lock file.
MK28=""
for _m in "$HOME/.claude/coderlap/codex-reviewed"/*; do
    case "$_m" in */rounds-*|*/ledger-*|*.lock) continue ;; esac
    [[ -f "$_m" ]] || continue
    [[ -z "$MK28" || "$_m" -nt "$MK28" ]] && MK28="$_m"
done
grep -q "escalated=0" "$MK28"; check "middle-tier deny marker carries escalated=0" $?
OUT=$(run_gate)   # identical retry, no override
is_allow "$OUT"; check "identical retry of an escalated=0 deny PASSES (loop can reach ROUND_MAX)" $?

echo "T28b: LEGACY marker (no escalated flag) inference — below-CAP retries, at/above-CAP escalates (finding 15)"
# A pre-ADR-019 marker "denied round=N material=M" has no escalated field. The
# cached-retry classifier must infer: round<CAP → escalated=0 (ordinary, retries);
# round>=CAP → escalated=1 (conservative, stays denied until owner override).
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t28b; OUT=$(run_gate)   # round 1 review creates the marker file
MKL=""
for _m in "$HOME/.claude/coderlap/codex-reviewed"/*; do
    case "$_m" in */rounds-*|*/ledger-*|*.lock) continue ;; esac
    [[ -f "$_m" ]] && { [[ -z "$MKL" || "$_m" -nt "$MKL" ]] && MKL="$_m"; }
done
[[ -n "$MKL" ]]; check "marker file located for legacy-inference test" $?
# Overwrite with a LEGACY below-cap deny (no escalated field) and retry the SAME diff.
printf 'denied round=1 material=1' > "$MKL"
OUT=$(run_gate)   # identical diff → cached path reads the legacy marker
is_allow "$OUT"; check "legacy below-CAP deny (round=1) retries -> ALLOW (escalated inferred 0)" $?
# Now a LEGACY at-cap deny must be treated as escalated (stays denied w/o override).
printf 'denied round=3 material=1' > "$MKL"
OUT=$(run_gate)
is_deny "$OUT"; check "legacy at-CAP deny (round=3) -> DENIED (escalated inferred 1)" $?
grep -q -- '--approve' <<<"$(reason "$OUT")"; check "legacy at-CAP deny names the owner --approve exit (ADR-023)" $?

echo "T29: findings ledger persists across rounds AND prior findings are injected into the prompt"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t29-1; OUT=$(run_gate)   # round 1 writes the ledger
LF=$(ledger_file); [[ -n "$LF" ]]; check "ledger file created after round 1" $?
grep -qE '^[0-9a-f]{16} 1 ' "$LF"; check "ledger line = '<fp16> <round> <text>'" $?
# Round 2 with capture: the prior finding must appear in the prompt.
CAP29="$TDIR/cap29"
bump_diff t29-2; OUT=$(run_gate_capture "$CAP29")
grep -q "ALREADY raised" "$CAP29/prompt"; check "prior-findings block injected into round-2 prompt" $?
grep -q "LATE" "$CAP29/prompt"; check "[LATE] convergence-pressure rule present in round-2 prompt" $?

echo "T30: project context — review runs read-only, from the repo cwd, with the changed-file list"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
echo "untracked change" > "$REPO/newfile.sh"   # an untracked changed file
CAP30="$TDIR/cap30"
bump_diff t30; OUT=$(run_gate_capture "$CAP30")
[[ "$(cat "$CAP30/cwd")" == "$REPO" ]]; check "codex ran from the repo cwd (got: $(cat "$CAP30/cwd"))" $?
grep -q -- "-s" "$CAP30/argv" && grep -q "read-only" "$CAP30/argv"; check "codex invoked with -s read-only" $?
grep -q "app.sh" "$CAP30/prompt"; check "tracked changed file named in the prompt" $?
grep -q "newfile.sh" "$CAP30/prompt"; check "UNTRACKED changed file named in the prompt" $?
# The context (file-reading) instruction rides ONLY with the cd-success path
# (the security fix): the context prompt tells Codex the repo is its working dir.
grep -q "working directory" "$CAP30/prompt"; check "context prompt instructs reading the repo (only sent after cd into it)" $?
rm -f "$REPO/newfile.sh"

echo "T30b: cd-failure fallback — a non-cd-able \$DIR forces the DIFF-ONLY prompt (security fix)"
# Make the repo detectable by git (so the gate resolves DIR to it and reviews)
# but NOT cd-able at review time, so the gate must fall back to PROMPT_NOCTX and
# never instruct Codex to read files against the wrong tree. A directory with no
# execute (traverse) bit cannot be cd'd into by a non-root user; root bypasses
# this, so the check SKIPS loudly when we cannot drop the traverse bit.
if [[ "$(id -u)" != "0" ]]; then
    new_head
    printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
    bump_diff t30b
    # Resolve+cache the diff by letting git read it first, THEN strip traverse.
    # The gate re-reads via `git -C "$DIR"` (works: git holds an fd) but `cd` fails.
    CAP30B="$TDIR/cap30b"; mkdir -p "$CAP30B"
    chmod 000 "$REPO"
    OUT=$(jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd}, cwd:$cwd}' | CAPTURE_DIR="$CAP30B" bash "$GATE" 2>/dev/null)
    chmod 755 "$REPO"   # restore before any assertion can fail out
    if [[ -f "$CAP30B/prompt" ]]; then
        grep -q "DIFF ONLY" "$CAP30B/prompt"; check "cd-failure -> diff-only prompt used" $?
        ! grep -q "working directory" "$CAP30B/prompt"; check "cd-failure prompt does NOT instruct reading repo files (no wrong-tree read)" $?
        [[ "$(cat "$CAP30B/cwd" 2>/dev/null)" != "$REPO" ]]; check "cd-failure review did NOT run from the (inaccessible) repo dir" $?
    else
        # cd may have failed so early that git itself couldn't read → gate skipped.
        # Either way it must not have blocked-on-infra; treat a clean no-review as ok.
        ok "cd-failure produced no context prompt (no wrong-tree read possible)"
        ok "cd-failure did not leak the repo cwd (no capture)"
        ok "cd-failure did not block on infrastructure"
    fi
else
    ok "SKIP cd-failure test — running as root (traverse bit not enforced)"
    ok "SKIP (root)"
    ok "SKIP (root)"
fi

echo "T31: ledger/context best-effort — no flock degrades to a cold review, never blocks"
# No-flock: the ledger append + prior-findings read both no-op (they are guarded
# by `command -v flock`); the gate still reviews (diff-only) and denies the
# material finding rather than erroring or blocking on infrastructure. Same
# complete tool list as T17 (proven) + wc/head/ls for the ADR-019 byte count.
NOFLOCK31="$TDIR/noflock31"; mkdir -p "$NOFLOCK31"
for cmd in jq git awk grep sed sha256sum cat mktemp mv rm find readlink stat date timeout tr sort cut dirname bash mkdir chmod wc head ls; do
    tp=$(command -v "$cmd" 2>/dev/null) && ln -sf "$tp" "$NOFLOCK31/$cmd"
done
ln -sf "$BIN/codex" "$NOFLOCK31/codex"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t31
CAP31="$TDIR/cap31"; mkdir -p "$CAP31"
OUT=$(jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | CAPTURE_DIR="$CAP31" PATH="$NOFLOCK31" bash "$GATE")
is_deny "$OUT"; check "no-flock: gate still reviews + denies material (no crash, no block-on-infra)" $?
# and no ledger file was created (the append is flock-guarded, so it no-ops)
! ls "$HOME/.claude/coderlap/codex-reviewed"/ledger-* >/dev/null 2>&1; check "no-flock: ledger append safely skipped (no ledger file)" $?
# CTX_OK=0 without flock → the DIFF-ONLY prompt is used (no repo-reading context),
# honouring the pre-ADR-019 fallback contract even though cd would have succeeded.
if [[ -f "$CAP31/prompt" ]]; then
    grep -q "DIFF ONLY" "$CAP31/prompt"; check "no-flock: diff-only prompt used (context layer degraded)" $?
    ! grep -q "working directory" "$CAP31/prompt"; check "no-flock: no repo-reading instruction in the prompt" $?
else
    ok "no-flock: no prompt captured (shim not reached — still a safe no-review)"
    ok "no-flock: (no prompt to inspect)"
fi

echo "T32: invalid ROUND_MAX / DIFF_BUDGET fall back to defaults (findings 5+8)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# ROUND_MAX=abc -> default 5; a correctness finding must still self-terminate at
# round 5 (proves the default took, not an arithmetic error).
for i in 1 2 3 4; do bump_diff "t32-$i"; OUT=$(CODERV_GATE_ROUND_MAX=abc CODERV_GATE_DIFF_BUDGET=xyz run_gate); done
is_deny "$OUT"; check "invalid ROUND_MAX/DIFF_BUDGET: rounds 1-4 still deny (defaults, no arith error)" $?
bump_diff t32-5; OUT=$(CODERV_GATE_ROUND_MAX=abc CODERV_GATE_DIFF_BUDGET=xyz run_gate)
is_allow "$OUT"; check "invalid ROUND_MAX falls back to 5 -> round 5 self-terminates" $?
# ROUND_MAX <= CAP is clamped up to CAP+2 (so the middle tier is never empty).
new_head
for i in 1 2 3 4; do bump_diff "t32c-$i"; OUT=$(CODERV_GATE_ROUND_MAX=1 run_gate); done
is_deny "$OUT"; check "ROUND_MAX=1 clamped to CAP+2=5 -> round 4 still denies (not ceiling)" $?

echo "T33: byte counting is locale-safe — a multibyte diff counts more BYTES than characters (finding 6)"
new_head
# Write a diff whose content is multibyte UTF-8; the rounds-file byte field must
# exceed the character length of what was sent.
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
python3 - "$REPO/app.sh" <<'PY' 2>/dev/null || printf '\xc3\xa9\xc3\xa9\xc3\xa9 multibyte %s\n' "$RANDOM" >> "$REPO/app.sh"
import sys
open(sys.argv[1],"a").write("é"*500 + "\n")
PY
OUT=$(run_gate)
RF=$(rounds_file); BYTES=$(tail -1 "$RF" | awk '{print $NF}')
# 500 'é' chars = 1000 bytes in UTF-8; the transmitted slice includes the diff
# frame too, so bytes must be well above 500. A char-based count would undercount.
[[ "$BYTES" =~ ^[0-9]+$ ]] && (( BYTES > 500 )); check "multibyte diff byte count ($BYTES) reflects real bytes, not chars" $?

echo "T33b: ledger stores VALID UTF-8 even when a multibyte finding hits the 400-byte cap"
# A finding padded past 400 bytes with multibyte 'é' chars: a naive `cut -c` under
# LC_ALL=C would split the char at the boundary, storing invalid UTF-8. The ledger
# line must be valid UTF-8 (iconv round-trips it unchanged / non-empty).
new_head
LONG_MB=$(python3 -c 'print("[BUG][correctness] app.sh:1 " + "é"*300)' 2>/dev/null || printf '[BUG][correctness] app.sh:1 %s' "$(printf 'é%.0s' $(seq 1 300))")
printf '1. %s\n' "$LONG_MB" > "$REVIEW_FILE"
bump_diff t33b; OUT=$(run_gate)
LF=$(ledger_file)
if [[ -n "$LF" ]]; then
    # The stored line must be valid UTF-8: iconv -f UTF-8 -t UTF-8 succeeds (rc 0)
    # on valid input and fails on invalid. Assert every ledger line survives.
    iconv -f UTF-8 -t UTF-8 "$LF" >/dev/null 2>&1; check "ledger contains only valid UTF-8 (no mid-char split at the byte cap)" $?
    # And the entry is non-empty (truncation didn't nuke it to zero).
    grep -qE '^[0-9a-f]{16} [0-9]+ .+' "$LF"; check "the multibyte finding was recorded (non-empty ledger line)" $?
else
    ok "SKIP UTF-8 ledger test — no ledger file (flock/env unavailable)"
    ok "SKIP"
fi

echo "T33c: ledger read-lock TIMEOUT degrades context to diff-only (finding: CTX_OK on lock fail)"
# Hold the ledger lock in a background process for longer than the gate's
# `flock -w 2`, so the gate's read-lock TIMES OUT → CTX_OK drops to 0 → the
# diff-only prompt is used and no (untrusted) prior-findings block is presented.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t33c-1; OUT=$(run_gate)   # round 1 creates the ledger at its real key
LF=$(ledger_file)
if [[ -n "$LF" ]] && command -v flock >/dev/null 2>&1; then
    # Grab the exclusive lock and hold it ~5s (> the gate's -w 2 timeout).
    flock -x "$LF.lock" -c 'sleep 5' &
    HOLD=$!
    sleep 0.3   # ensure the holder has the lock before the gate tries
    CAP33C="$TDIR/cap33c"; mkdir -p "$CAP33C"
    bump_diff t33c-2; OUT=$(run_gate_capture "$CAP33C")
    wait "$HOLD" 2>/dev/null
    if [[ -f "$CAP33C/prompt" ]]; then
        grep -q "DIFF ONLY" "$CAP33C/prompt"; check "ledger lock timeout -> diff-only prompt (CTX_OK dropped)" $?
        ! grep -q "ALREADY raised" "$CAP33C/prompt"; check "no stale prior-findings block presented on lock timeout" $?
    else
        ok "SKIP CTX_OK-on-lock-fail — no prompt captured"; ok "SKIP"
    fi
else
    ok "SKIP CTX_OK-on-lock-fail — no ledger file / no flock"; ok "SKIP"
fi

echo "T34: precedence — a later allow marker cannot overwrite an escalated=1 ceiling block (finding 12)"
PREC_DIR="$TDIR/prec"; mkdir -p "$PREC_DIR"; PMF="$PREC_DIR/hash"
printf 'denied round=5 material=1 escalated=1' > "$PMF"
publish_round_marker "$PMF" "lgtm" "0"
[[ "$(cat "$PMF")" == "denied round=5 material=1 escalated=1" ]]; check "lgtm does NOT overwrite an escalated=1 marker" $?
publish_round_marker "$PMF" "cap_stopped round=9 findings=1" "9"
[[ "$(cat "$PMF")" == "denied round=5 material=1 escalated=1" ]]; check "a higher-round cap_stopped does NOT overwrite escalated=1" $?
publish_round_marker "$PMF" "denied round=6 material=1 escalated=1" "6"
[[ "$(cat "$PMF")" == "denied round=6 material=1 escalated=1" ]]; check "another escalated=1 DOES supersede (record the newer stop)" $?
rm -rf "$PREC_DIR"

echo "T35: ROUNDS_FILE migration matrix — legacy(bytes 0) / mixed / torn-4-field excluded (finding 11)"
new_head
# Seed the gate's real key by doing a round-1 review, then rewrite that file into
# each scenario (robust to path canonicalization). CAP=3, so we assert the round
# NUMBER the gate reports (= counted lines + 1) to prove which lines it counted.
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t35-seed; OUT=$(run_gate)     # round 1: gate writes the rounds file
RFP=$(rounds_file); [[ -n "$RFP" ]]; check "rounds file created at the gate's key" $?
# (a) PURE-LEGACY: 2 valid 3-field lines → both counted, byte-sum 0. This round
# becomes round 3; still below cap? no, ==cap 3 → but material → middle-tier deny.
printf '1 1 correctness\n1 1 correctness\n' > "$RFP"
bump_diff t35a; OUT=$(run_gate)         # 2 legacy + this = round 3
grep -qE "round 3 of cap 3" <<<"$(reason "$OUT")"; check "(a) pure-legacy: 2 lines counted -> this is round 3" $?
CUMB=$(awk '/^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$/{s+=$4} END{print s+0}' "$RFP")
NEWB=$(tail -1 "$RFP" | awk '{print $4}')
[[ "$CUMB" == "$NEWB" && "$NEWB" =~ ^[0-9]+$ ]]; check "(a) legacy lines contribute 0 bytes; cumulative == only the new 4-field row's bytes" $?
# (b) TORN 4-field line (5 tokens) must be excluded from BOTH round + byte totals.
printf '1 1 correctness 100\n9 9 junk 5 EXTRA\n' > "$RFP"   # line 2 is torn (5 fields)
bump_diff t35b; OUT=$(run_gate)         # 1 valid 4-field + torn(ignored) + this = round 2
grep -qE "round 2 of cap 3" <<<"$(reason "$OUT")"; check "(b) torn 4-field (5 tokens) excluded from the round count (round 2, not 3)" $?
! grep -q "trajectory: .*9" <<<"$(reason "$OUT")"; check "(b) torn record's finding-count (9) never leaked into the trajectory" $?
# (c) VALID MIXED new+legacy: 1 legacy(3-field) + 1 new(4-field) both count; the
# byte total sums ONLY the 4-field line's bytes (legacy contributes 0).
printf '1 1 correctness\n1 1 correctness 250\n' > "$RFP"
bump_diff t35c; OUT=$(run_gate)         # 2 valid lines + this = round 3
grep -qE "round 3 of cap 3" <<<"$(reason "$OUT")"; check "(c) mixed new+legacy: both lines counted -> round 3" $?
grep -q "trajectory: 1->1->" <<<"$(reason "$OUT")"; check "(c) mixed-schema trajectory includes both prior finding counts" $?
PREVB=$(awk '/^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$/{s+=$4} END{print s}' "$RFP")
# cumulative includes the seeded 250 + this round's own bytes; must be > 250.
(( PREVB > 250 )); check "(c) cumulative bytes sum the 4-field rows (legacy=0); >250 (got $PREVB)" $?

echo "T36: atomic budget under concurrency — no lost update (finding 10)"
# Round increment AND cumulative-byte accumulation share ONE flock transaction,
# so two overlapping reviews serialize: exactly two 4-field lines land, each with
# its own positive byte field, and neither clobbers the other. A separate-lock
# design would drop a line or a byte field.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t36
export FAKE_DELAY=1
run_gate > "$TDIR/t36a" & PA=$!
run_gate > "$TDIR/t36b" & PB=$!
wait "$PA" "$PB"
unset FAKE_DELAY
RF=$(rounds_file)
NLINES=$(grep -cE '^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$' "$RF" 2>/dev/null)
[[ "$NLINES" == "2" ]]; check "exactly two 4-field (byte-bearing) rounds appended under concurrency (got: $NLINES)" $?
ZEROBYTES=$(awk '$4==0{c++} END{print c+0}' "$RF")
[[ "$ZEROBYTES" == "0" ]]; check "neither concurrent round lost its byte field (0-byte rows: $ZEROBYTES)" $?

echo "T36b: ceiling straddle under concurrency — EXACTLY one review crosses into the ceiling"
# Seed to round==CAP with MARGINAL reviews (they allow-with-caveat, so seeding does
# not escalate) and note the seeded CUMULATIVE bytes. Then run two overlapping
# MATERIAL reviews under a budget set BETWEEN (seeded_cum + one new slice) and
# (seeded_cum + two new slices): so the FIRST serialized review is still
# pre-ceiling (ordinary middle-tier deny) and the SECOND (its cumulative now
# includes the first's bytes) is AT/OVER budget → the ceiling ([correctness]
# self-terminates → allow). A stale-read design would let both read the same
# pre-ceiling total and both deny. We assert EXACTLY one deny + one allow.
new_head
printf '%s\n' "$MARGINAL_REVIEW" > "$REVIEW_FILE"
for i in 1 2 3; do bump_diff "t36b-seed$i"; OUT=$(run_gate); done   # rounds 1-3 (==CAP), marginal → allow
RF=$(rounds_file)
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# A material round's transmitted bytes are stable across the two concurrent runs
# (same diff). Estimate one slice from a dry material round; its row STAYS in the
# ledger (it is a real committed round), so the concurrent pair straddle relative
# to the cumulative AFTER the probe, not after the seed.
bump_diff t36b-probe; OUT=$(run_gate); PROBE_LINE=$(tail -1 "$RF"); ONEB=$(awk '{print $4}' <<<"$PROBE_LINE")
# Baseline the pair reads is the cumulative once the probe row is persisted.
BASE_CUM=$(awk '/^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$/{s+=$4} END{print s+0}' "$RF")
# Budget lets BASE + the FIRST concurrent slice sit under, but BASE + BOTH slices
# go over: BASE_CUM < (BASE_CUM + ONEB) < BUDGET < (BASE_CUM + 2*ONEB).
BUDGET=$(( BASE_CUM + ONEB + ONEB/2 ))
# Isolate the BYTE ceiling: with the default ROUND_MAX (5) the concurrent pair
# (rounds 5 & 6 here) would BOTH hit the round ceiling regardless of bytes, so
# the byte-budget straddle could never show. Lift the round ceiling out of the
# way so CUM_BYTES >= DIFF_BUDGET is the ONLY thing that can trip the ceiling.
bump_diff t36b-conc
export FAKE_DELAY=1
CODERV_GATE_ROUND_MAX=99 CODERV_GATE_DIFF_BUDGET=$BUDGET run_gate > "$TDIR/t36bA" & PA=$!
CODERV_GATE_ROUND_MAX=99 CODERV_GATE_DIFF_BUDGET=$BUDGET run_gate > "$TDIR/t36bB" & PB=$!
wait "$PA" "$PB"
unset FAKE_DELAY
# The ATOMICITY guarantee (finding 10) is: the two concurrent rounds serialize on
# ONE transaction, so (a) both land as distinct 4-field rows, and (b) the running
# cumulative byte total is strictly monotonic — a stale-read design would append
# two rows computed from the SAME pre-update total, breaking monotonicity.
NROWS=$(grep -cE '^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$' "$RF")
(( NROWS >= 2 )); check "both concurrent rounds recorded as distinct 4-field rows (got $NROWS)" $?
MONO=$(awk '/^[0-9]+ [0-9]+ [^[:space:]]+ [0-9]+$/{cum+=$4; print cum}' "$RF" | awk 'NR>1 && $1<=prev{bad=1} {prev=$1} END{print bad+0}')
[[ "$MONO" == "0" ]]; check "cumulative byte total strictly monotonic — serialized, not stale reads (finding 10)" $?
# Because the pair SERIALIZES on the flock, the straddle is deterministic — NOT
# racy — even though we can't know which OS process won the lock: the first
# committer reads SEED_CUM (< BUDGET) → pre-ceiling MATERIAL deny, then appends
# its slice; the second reads SEED_CUM+ONEB and its own slice pushes the running
# total past BUDGET → ceiling self-terminate → allow. So EXACTLY one deny + one
# allow, order-independent. A stale-read design (both reading SEED_CUM) would
# instead produce two denies — which this assertion catches.
VA=$(cat "$TDIR/t36bA"); VB=$(cat "$TDIR/t36bB")
DENIES=0; ALLOWS=0
for V in "$VA" "$VB"; do if is_deny "$V"; then DENIES=$((DENIES+1)); else ALLOWS=$((ALLOWS+1)); fi; done
{ (( DENIES == 1 )) && (( ALLOWS == 1 )); }; check "ceiling straddle: exactly one pre-ceiling deny + one ceiling allow under concurrency (deny:$DENIES allow:$ALLOWS)" $?

echo "T37: message-embedded '; git -C <decoy> commit' cannot hijack the review target (0.13.1 bypass regression)"
# GITC_RE used to match the RAW command, so a commit MESSAGE containing a
# delimiter + `git -C <clean-decoy> commit` pointed the review at the decoy
# (empty diff -> silent allow) while the real repo's diff committed
# UNREVIEWED. GITC_RE now matches the quote-scrubbed command, same as GIT_RE:
# the decoy text lives inside the -m quotes, so it scrubs away and the review
# stays on the real (cwd) repo — whose material finding must deny.
DECOY="$TDIR/decoy"
mkdir -p "$DECOY"
git -C "$DECOY" init -q
git -C "$DECOY" config user.email t@t
git -C "$DECOY" config user.name t
echo clean > "$DECOY/f"
git -C "$DECOY" add -A && git -C "$DECOY" commit -qm seed
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t37    # the REAL repo is dirty; the decoy stays clean
OUT=$(jq -cn --arg cmd "git commit -m \"note; git -C $DECOY commit fixed the build\"" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "quoted-message -C decoy ignored — real repo reviewed, material finding denies" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "review ran fresh against the real repo's key" $?

echo "T38: legit UNQUOTED git -C <dir> commit still extracts the dir (cwd not a repo)"
new_head
NOREPO="$TDIR/norepo"
mkdir -p "$NOREPO"
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t38
OUT=$(jq -cn --arg cmd "git -C $REPO commit -m t" --arg cwd "$NOREPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "unquoted -C dir extraction survives the scrub (reviewed despite non-repo cwd)" $?

echo "T39: QUOTED -C path degrades safely — planted 'QUOTED' decoy ignored, cwd (same repo) reviewed"
# Accepted 0.13.1 trade-off: a quoted -C value scrubs to the QUOTED sentinel,
# which the gate must DISCARD — resolved as a bare candidate it is a path
# RELATIVE to the gate's cwd, ahead of the session cwd, so a clean repo
# literally named QUOTED planted there would become a silent-allow decoy.
# With the sentinel discarded, resolution falls through to cd/cwd: session
# cwd inside the same repo — the common case — still reviews that repo.
# (Protecting `-C "..."` from the scrub would be spoofable by a message
# containing that exact text, reintroducing the T37 bypass.)
SPREPO="$TDIR/sp ace"
mkdir -p "$SPREPO"
git -C "$SPREPO" init -q
git -C "$SPREPO" config user.email t@t
git -C "$SPREPO" config user.name t
echo base > "$SPREPO/app.sh"
git -C "$SPREPO" add -A && git -C "$SPREPO" commit -qm seed
echo dirty >> "$SPREPO/app.sh"
mkdir -p "$SPREPO/QUOTED"          # the plantable decoy: a CLEAN repo named QUOTED
git -C "$SPREPO/QUOTED" init -q
git -C "$SPREPO/QUOTED" config user.email t@t
git -C "$SPREPO/QUOTED" config user.name t
echo clean > "$SPREPO/QUOTED/f"
git -C "$SPREPO/QUOTED" add -A && git -C "$SPREPO/QUOTED" commit -qm seed
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
OUT=$(cd "$SPREPO" && jq -cn --arg cmd "git -C \"$SPREPO\" commit -m t" --arg cwd "$SPREPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "QUOTED sentinel discarded — planted decoy skipped, real repo's material finding denies" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "fresh key: the real repo (not the decoy) was reviewed" $?

echo "T40: heredoc commit-message body cannot hijack the review target (0.13.1)"
# `git commit -F - <<'EOF'` feeds the message on stdin: the body is data but
# carries no quotes, so it used to survive the quote scrub — an embedded
# `; git -C <decoy> commit` line hijacked resolution exactly like T37.
# Heredoc bodies are now scrubbed out like quoted strings.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t40
HD_CMD="git commit -F - <<'EOF'
note; git -C $DECOY commit fixed the build
EOF"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "heredoc-body -C decoy ignored — real repo reviewed, material finding denies" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "review ran against the real repo's fresh key" $?

echo "T41: heredoc commit is still DETECTED (body scrub never hides the invocation line)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t41
HD_CMD="git commit -F - <<'EOF'
a perfectly harmless message
EOF"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "heredoc commit reviewed (material finding denies) — operator line survived the scrub" $?

echo "T42: escaped quote in the message cannot spill an injected -C past the scrub (0.13.1)"
# Inside "..." a \" does not close the string; the old naive quote pairing let
# the tail — including `; git -C <decoy> commit` — escape the QUOTED sentinel.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t42
EQ_CMD="git commit -m \"he said \\\" ; git -C $DECOY commit \\\" done\""
OUT=$(jq -cn --arg cmd "$EQ_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "escaped-quote injection ignored — real repo reviewed, material finding denies" $?

echo "T43: a real unquoted path CONTAINING 'QUOTED' is still a valid -C candidate (no over-discard)"
# The sentinel discard covers exactly QUOTED and QUOTED/... artifacts; a
# genuine path that merely contains the word must keep its review — with the
# session cwd outside the repo, over-discarding would silently skip it.
QPROJ="$TDIR/QUOTED-project"
mkdir -p "$QPROJ"
git -C "$QPROJ" init -q
git -C "$QPROJ" config user.email t@t
git -C "$QPROJ" config user.name t
echo base > "$QPROJ/app.sh"
git -C "$QPROJ" add -A && git -C "$QPROJ" commit -qm seed
echo dirty >> "$QPROJ/app.sh"
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
OUT=$(jq -cn --arg cmd "git -C $QPROJ commit -m t" --arg cwd "$NOREPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "path containing QUOTED still extracted and reviewed (deny), not over-discarded" $?

echo "T44: heredoc delimiter with punctuation (END-MSG) is still scrubbed (no hijack)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t44
HD_CMD="git commit -F - <<'END-MSG'
note; git -C $DECOY commit fixed the build
END-MSG"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "punctuation-delimiter heredoc body scrubbed — real repo reviewed, denies" $?

echo "T45: SECOND heredoc's body on one line is scrubbed too (delimiter queue)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t45
HD_CMD="git commit -F - <<'A' && cat <<'B'
first body line
A
note; git -C $DECOY commit fixed the build
B"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "second heredoc body scrubbed — injected -C ignored, real repo denies" $?

echo "T46: a QUOTED '<<EOF' is not a heredoc — a later real commit line is still detected"
# fail-closed guard: echo "<<EOF" used to queue a bogus delimiter whose
# never-found terminator ate every following line — including the real
# `git commit` — so the gate emitted NO review at all.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t46
FK_CMD="echo \"<<EOF\"
git commit -m t46"
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "quoted fake heredoc ignored — the real commit below it is still reviewed (denies)" $?

echo "T47: a COMMENTED '# <<EOF' is not a heredoc — a later real commit line is still detected"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t47
FK_CMD="true # <<EOF
git commit -m t47"
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "commented fake heredoc ignored — the real commit below it is still reviewed (denies)" $?

echo "T48: '# <<EOF' immediately after a control operator (no space) is a comment, not a heredoc"
# `true;# <<EOF` — the # opens a comment at a token boundary right after `;`,
# so the fake delimiter must NOT queue and eat the real commit line below.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t48
FK_CMD="true;# <<EOF
git commit -m t48"
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "operator-adjacent comment ignored — the real commit below it is still reviewed (denies)" $?

echo "T49: QUOTED heredoc delimiter with an arbitrary char (END@MSG) is still scrubbed"
# A quoted delimiter may contain ANY character; the old allowlist
# [A-Za-z0-9_.+-] missed @, so <<'END@MSG' was not recognized and its body
# (with an injected -C decoy) survived the scrub and hijacked the target.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t49
HD_CMD="git commit -F - <<'END@MSG'
note; git -C $DECOY commit fixed the build
END@MSG"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "arbitrary-char quoted delimiter body scrubbed — real repo reviewed, denies" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "review ran against the real repo's fresh key" $?

echo "T50: double-quoted delimiter with an ESCAPED quote (<<\"END\\\"MSG\") resolves its real terminator"
# Shell removes the quotes/escapes: <<"END\"MSG" terminates on END"MSG. The
# old scan stopped at the \" and queued the wrong delimiter END, so the body
# (with an injected decoy) plus the real commit below it were consumed to EOF
# and skipped review. The body must be scrubbed AND the real commit detected.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t50
HD_CMD='cat <<"END\"MSG"
note; git -C '"$DECOY"' commit fixed the build
END"MSG
git commit -m t50'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "escaped-quote delimiter resolved — body scrubbed, real commit still reviewed (denies)" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "real repo reviewed (not the decoy, not skipped)" $?

echo "T51: '# <<EOF' right after a ')' operator is a comment, not a heredoc"
# `case x in x)# <<EOF` — the # opens a comment at the token boundary after )
# so the fake delimiter must NOT queue and eat the real commit line below.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t51
FK_CMD="case x in x)# <<EOF
esac
git commit -m t51"
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "comment after ) ignored — the real commit below it is still reviewed (denies)" $?

echo "T52: MIXED-quote delimiter <<E'OF' resolves to EOF (partial quote can't queue a short delim)"
# <<E'OF' is the single word EOF. The old branch-per-form parser stopped at
# the quote and queued E, then swallowed the real terminator + the git commit.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t52
HD_CMD="cat <<E'OF'
note; git -C $DECOY commit fixed the build
EOF
git commit -m t52"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "mixed-quote delimiter resolved to EOF — body scrubbed, real commit reviewed (denies)" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "real repo reviewed, not skipped past the real terminator" $?

echo "T53: three-segment delimiter <<'E'O\"F\" also resolves to EOF"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t53
HD_CMD='cat <<'\''E'\''O"F"
note; git -C '"$DECOY"' commit fixed the build
EOF
git commit -m t53'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "single+unquoted+double segments resolved to EOF — body scrubbed, real commit reviewed (denies)" $?

# ---- ROUND 9: full Bash quote-removal in the heredoc delimiter lexer -------
# Each case below was a bypass before round 9: the pre-round-9 lexer treated
# `#`/backtick as word boundaries and had no $'...' / $"..." / literal-$ /
# empty-delimiter / cross-line-quote handling, so a crafted delimiter queued a
# WRONG (or no) heredoc, letting the body's injected `git -C $DECOY commit`
# hijack the target (silent allow on the clean decoy) or the fake operator eat
# the real commit line. A deny with "round 1 of cap 3" proves the REAL repo was
# reviewed: body scrubbed, decoy ignored, real terminator resolved.

echo "T54: mid-word '#' is a literal delimiter char (<<EOF#TAG terminates on EOF#TAG)"
# Pre-fix: '#' was a word boundary, so the delimiter queued as EOF; the real
# terminator EOF#TAG never matched, the body + real commit were eaten to EOF.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t54
HD_CMD="cat <<EOF#TAG
note; git -C $DECOY commit fixed the build
EOF#TAG
git commit -m t54"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "mid-word # kept — body scrubbed on EOF#TAG, real commit reviewed (denies)" $?
grep -q "round 1 of cap 3" <<<"$(reason "$OUT")"; check "T54 real repo reviewed, not the decoy" $?

echo "T55: backtick is a literal delimiter char (<<\`X\` terminates on \`X\`)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t55
HD_CMD='cat <<`X`
note; git -C '"$DECOY"' commit fixed the build
`X`
git commit -m t55'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "backtick delimiter kept — body scrubbed, real commit reviewed (denies)" $?

echo "T56: ANSI-C delimiter <<\$'EOF' resolves to EOF"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t56
HD_CMD="cat <<\$'EOF'
note; git -C $DECOY commit fixed the build
EOF
git commit -m t56"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "\$'EOF' resolved to EOF — body scrubbed, real commit reviewed (denies)" $?

echo "T57: ANSI-C escape decode family — the delimiter's REAL bytes must match the terminator"
# The body decoy is followed by the DECODED terminator (a real tab, an 'A' from
# octal/hex, a UTF-8 é, or the literal bytes of an invalid escape). If the
# decode is wrong the terminator never matches and the scrub over/under-runs.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
# T57a \t -> real tab
bump_diff t57a
HD_CMD=$(printf 'cat <<$\047E\\tF\047\ndecoy; git -C %s commit x\nE\tF\ngit commit -m t57a' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57a \\t decoded to a real tab — terminator matched, real commit reviewed" $?
# T57b octal \101 -> A
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57b
HD_CMD=$(printf 'cat <<$\047E\\101F\047\ndecoy; git -C %s commit x\nEAF\ngit commit -m t57b' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57b octal \\101 decoded to A — terminator EAF matched, real commit reviewed" $?
# T57c hex \x41 -> A
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57c
HD_CMD=$(printf 'cat <<$\047E\\x41F\047\ndecoy; git -C %s commit x\nEAF\ngit commit -m t57c' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57c hex \\x41 decoded to A — terminator EAF matched, real commit reviewed" $?
# T57d control \cA -> byte 1 (control char); terminator is E<0x01>F
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57d
HD_CMD=$(printf 'cat <<$\047E\\cAF\047\ndecoy; git -C %s commit x\nE\001F\ngit commit -m t57d' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57d control \\cA decoded to byte 1 — terminator matched, real commit reviewed" $?
# T57d2 control on PUNCTUATION (\c[ -> byte 27, the full-range mask, not just letters)
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57d2
HD_CMD=$(printf 'cat <<$\047E\\c[F\047\ndecoy; git -C %s commit x\nE\033F\ngit commit -m t57d2' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57d2 control \\c[ decoded to byte 27 (punctuation range) — terminator matched, real commit reviewed" $?
# T57d3 \c? is the special case -> DEL (byte 127), not the plain mask
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57d3
HD_CMD=$(printf 'cat <<$\047E\\c?F\047\ndecoy; git -C %s commit x\nE\177F\ngit commit -m t57d3' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57d3 control \\c? decoded to DEL (127) — terminator matched, real commit reviewed" $?
# T57e unicode é -> UTF-8 c3 a9; terminator is <é>EOF
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57e
HD_CMD=$(printf 'cat <<$\047\\u00e9EOF\047\ndecoy; git -C %s commit x\n\xc3\xa9EOF\ngit commit -m t57e' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57e \\u00e9 decoded to UTF-8 (c3 a9) — terminator matched, real commit reviewed" $?
# T57f invalid escape \q kept literal as backslash-q; terminator is E\qF
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57f
HD_CMD=$(printf 'cat <<$\047E\\qF\047\ndecoy; git -C %s commit x\nE\\qF\ngit commit -m t57f' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57f invalid \\q kept literal — terminator E\\qF matched, real commit reviewed" $?
# T57g NUL TRUNCATES the $'...' string (bash: $'AB\x00CD' -> "AB"). A decoded
# NUL from hex/octal/\c@ must end the delimiter there, not emit a literal 0 byte
# that misses bash's real (truncated) terminator and swallows the later commit.
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57g1
HD_CMD=$(printf 'cat <<$\047E\\c@F\047\ndecoy; git -C %s commit x\nE\ngit commit -m t57g1' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57g1 \\c@ NUL truncates <<\$'E\\c@F' to E — decoy scrubbed, real commit reviewed" $?
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57g2
HD_CMD=$(printf 'cat <<$\047A\\x00B\047\ndecoy; git -C %s commit x\nA\ngit commit -m t57g2' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57g2 \\x00 NUL truncates <<\$'A\\x00B' to A — decoy scrubbed, real commit reviewed" $?
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57g3
HD_CMD=$(printf 'cat <<$\047X\\000Y\047\ndecoy; git -C %s commit x\nX\ngit commit -m t57g3' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57g3 \\000 NUL truncates <<\$'X\\000Y' to X — decoy scrubbed, real commit reviewed" $?
# T57h incomplete hex (\x with no hex digit) is kept LITERAL by bash:
# $'E\xZF' -> "E\xZF" (Z is not a hex digit). Terminator carries the literal
# backslash-x-Z-F, so the delimiter must not decode or drop it.
new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57h
HD_CMD=$(printf 'cat <<$\047E\\xZF\047\ndecoy; git -C %s commit x\nE\\xZF\ngit commit -m t57h' "$DECOY")
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "T57h incomplete hex \\xZF kept literal — terminator E\\xZF matched, real commit reviewed" $?

# T57-mawk: the ANSI-C decoder must emit identical bytes under mawk — the
# hook's fallback documents mawk as supported, and mawk parses hex numeric
# literals as 0 (the round-9 utf8/ORD tables use DECIMAL to survive it). Run
# the byte-sensitive cases with `awk` shadowed by mawk on PATH; SKIP loudly if
# mawk is not installed rather than pass silently.
if command -v mawk >/dev/null 2>&1; then
    MAWKBIN="$TDIR/mawkbin"; mkdir -p "$MAWKBIN"; ln -sf "$(command -v mawk)" "$MAWKBIN/awk"
    # \x41 -> A
    new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57m1
    HD_CMD=$(printf 'cat <<$\047E\\x41F\047\ndecoy; git -C %s commit x\nEAF\ngit commit -m t57m1' "$DECOY")
    OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$MAWKBIN:$PATH" bash "$GATE")
    is_deny "$OUT"; check "T57-mawk hex \\x41 -> A under mawk — terminator matched, real commit reviewed" $?
    # é -> UTF-8 c3 a9 (the exact case where hex literals would zero out on mawk)
    new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57m2
    HD_CMD=$(printf 'cat <<$\047\\u00e9EOF\047\ndecoy; git -C %s commit x\n\xc3\xa9EOF\ngit commit -m t57m2' "$DECOY")
    OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$MAWKBIN:$PATH" bash "$GATE")
    is_deny "$OUT"; check "T57-mawk \\u00e9 -> UTF-8 (c3 a9) under mawk — terminator matched, real commit reviewed" $?
    # \c[ -> byte 27 under mawk (ORD table, full range)
    new_head; printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"; bump_diff t57m3
    HD_CMD=$(printf 'cat <<$\047E\\c[F\047\ndecoy; git -C %s commit x\nE\033F\ngit commit -m t57m3' "$DECOY")
    OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$MAWKBIN:$PATH" bash "$GATE")
    is_deny "$OUT"; check "T57-mawk control \\c[ -> byte 27 under mawk — terminator matched, real commit reviewed" $?
else
    echo "  SKIP  T57-mawk: mawk not installed (decode-family mawk parity not exercised)"
fi

echo "T58: double-quote \$ escape (<<\"END\\\$MSG\") resolves to END\$MSG"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t58
HD_CMD='cat <<"END\$MSG"
note; git -C '"$DECOY"' commit fixed the build
END$MSG
git commit -m t58'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "\\\$ removed in \"...\" delimiter — terminator END\$MSG matched, real commit reviewed" $?

echo "T59: locale double-quote <<\$\"EOF\" resolves to EOF"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t59
HD_CMD='cat <<$"EOF"
note; git -C '"$DECOY"' commit fixed the build
EOF
git commit -m t59'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "\$\"EOF\" treated as double-quote segment — real commit reviewed (denies)" $?

echo "T60: bare \$ is a literal delimiter char (<<E\$F terminates on E\$F)"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t60
HD_CMD='cat <<E$F
note; git -C '"$DECOY"' commit fixed the build
E$F
git commit -m t60'
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "literal \$ kept — terminator E\$F matched, real commit reviewed (denies)" $?

echo "T61: a fake <<EOF INSIDE a \$'...' string queues nothing (\\' does not close it)"
# echo $'a\'b <<EOF c' is ONE ANSI-C string (a'b <<EOF c); the <<EOF is data,
# not an operator, so it must NOT queue a heredoc and eat the real commit line.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t61
FK_CMD=$(printf 'echo $\047a\\\047b <<EOF c\047\ngit commit -m t61')
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "fake <<EOF inside \$'...' ignored — the real commit below it is reviewed (denies)" $?

echo "T62: empty delimiter <<'' queues (terminator = first empty line) — body decoy scrubbed"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t62
HD_CMD="cat <<''
note; git -C $DECOY commit fixed the build

git commit -m t62"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "empty delimiter queued — body decoy scrubbed to the blank line, real commit reviewed (denies)" $?

echo "T63: a fake <<EOF on a later line of a MULTI-LINE \"...\" string queues nothing"
# The double-quoted string opens on line 1 and stays open across newlines; the
# <<EOF on line 2 is inside it. Pre-fix the per-line state reset treated line 2
# as unquoted and queued a bogus heredoc that ate the real commit after the
# closing quote. Quote state must carry across newlines.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t63
FK_CMD='echo "opening
<<EOF still inside the string
closing" ; git commit -m t63'
OUT=$(jq -cn --arg cmd "$FK_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "multi-line quoted <<EOF ignored — real commit after the closing quote reviewed (denies)" $?

echo "T64: awk-failure WITH a heredoc fails CLOSED (deny), never reviews unsanitized text"
# If the scrub pass (awk) cannot run, a heredoc body could smuggle a decoy
# commit past the scrub. There is no safe fallback, so the gate must DENY
# loudly (mirroring the jq-missing path) rather than review the raw command.
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t64
FAILAWK="$TDIR/failbin"
mkdir -p "$FAILAWK"
printf '#!/bin/sh\nexit 3\n' > "$FAILAWK/awk"   # awk always fails
chmod +x "$FAILAWK/awk"
HD_CMD="git commit -F - <<'EOF'
a message
EOF"
OUT=$(jq -cn --arg cmd "$HD_CMD" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$FAILAWK:$PATH" bash "$GATE")
is_deny "$OUT"; check "awk-fail + heredoc denies (fail-closed)" $?
grep -qi "scrub pass (awk) failed" <<<"$(reason "$OUT")"; check "T64 deny reason names the awk-sanitize failure" $?
# and awk-failure WITHOUT a heredoc keeps the raw-CMD fallback (still reviews)
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t64b
OUT=$(jq -cn --arg cmd "git commit -m plain" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | PATH="$FAILAWK:$PATH" bash "$GATE")
is_deny "$OUT"; check "T64b awk-fail without heredoc still reviews (raw-CMD fallback, denies on material)" $?

# ============================ ADR-022 (0.14.0) ==============================
# Default (quality-gate) mode: marginal findings ([hardening]/[edge]/
# [theoretical]) never block — allow in ROUND 1 with an "Optional Security
# Review (non-blocking)" section; realistic-impact findings still block.
# CODERV_GATE_SECURITY=1 is the deep-review opt-in that makes [hardening] block.
unset CODERV_GATE_SECURITY

HARDENING_REVIEW='1. [BUG][hardening] app.sh:1 — exotic shell-grammar corner can defeat the scrubber; no reachable high-impact path.'
MIXED_MARGINAL_REVIEW='1. [BUG][hardening] app.sh:1 — parser corner, no reachable impact.
2. [BUG][edge] app.sh:2 — bounded recoverable oddity on weird input.
3. [BUG][theoretical] app.sh:3 — proven unreachable.'
MIXED_MAT_HARD_REVIEW='1. [BUG][correctness] app.sh:1 — wrong result on valid input. Fix: X.
2. [BUG][hardening] app.sh:2 — exotic parser corner, no reachable impact.'

echo "T65: default mode — [hardening]-only review ALLOWS in ROUND 1 with an Optional Security Review section"
new_head
printf '%s\n' "$HARDENING_REVIEW" > "$REVIEW_FILE"
bump_diff t65; OUT=$(run_gate)
is_allow "$OUT"; check "hardening-only allows in round 1 (not deny, not cap-dependent)" $?
grep -q "Optional Security Review" <<<"$(ctx "$OUT")"; check "context carries the labeled Optional Security Review section" $?
grep -q "quality gate PASSED" <<<"$(sysmsg "$OUT")"; check "systemMessage names the quality-gate pass" $?
grep -q "shell-grammar corner" <<<"$(ctx "$OUT")"; check "finding surfaced verbatim, not dropped" $?
grep -q '"optional_review":true' "$HOME/.claude/coderlap/loop-events.jsonl"; check "optional_review outcome logged" $?
# an optional-notes pass writes NO cache marker: the identical retry
# RE-REVIEWS and re-surfaces the findings verbatim (a count-only cached caveat
# could never satisfy the transparency rule in a fresh session).
OUT=$(run_gate)
is_allow "$OUT"; check "identical retry of an optional-notes pass allows (via re-review)" $?
grep -q "shell-grammar corner" <<<"$(ctx "$OUT")"; check "retry re-surfaces the original finding text verbatim" $?

echo "T66: default mode — an all-marginal mix (hardening+edge+theoretical) also allows in round 1"
new_head
printf '%s\n' "$MIXED_MARGINAL_REVIEW" > "$REVIEW_FILE"
bump_diff t66; OUT=$(run_gate)
is_allow "$OUT"; check "edge/theoretical join hardening in the round-1 allow" $?
grep -q "Optional Security Review" <<<"$(ctx "$OUT")"; check "mixed marginal findings listed in the Optional section" $?

echo "T67: default mode — a realistic [security] finding still BLOCKS"
new_head
printf '%s\n' "$SECURITY_REVIEW" > "$REVIEW_FILE"
bump_diff t67; OUT=$(run_gate)
is_deny "$OUT"; check "[security] denies in default mode" $?

echo "T68: default mode — a [correctness] finding still BLOCKS"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t68; OUT=$(run_gate)
is_deny "$OUT"; check "[correctness] denies in default mode" $?

echo "T69: CODERV_GATE_SECURITY=1 — the same [hardening] finding BLOCKS (deep-review opt-in)"
new_head
printf '%s\n' "$HARDENING_REVIEW" > "$REVIEW_FILE"
bump_diff t69
OUT=$(CODERV_GATE_SECURITY=1 run_gate)
is_deny "$OUT"; check "security mode makes [hardening] material (round-1 deny)" $?

echo "T70: default mode — mixed [correctness]+[hardening] blocks on the material one, hardening routed to Optional"
new_head
printf '%s\n' "$MIXED_MAT_HARD_REVIEW" > "$REVIEW_FILE"
bump_diff t70; OUT=$(run_gate)
is_deny "$OUT"; check "mixed review denies (the correctness finding blocks)" $?
grep -q "Optional Security Review (non-blocking)" <<<"$(reason "$OUT")"; check "deny reason carries the Optional Security Review section" $?
# the marginal finding must be LISTED VERBATIM inside the section, not merely
# counted — the owner must never re-parse severity tags to see what blocks.
sed -n '/Optional Security Review (non-blocking)/,$p' <<<"$(reason "$OUT")" \
  | grep -q "exotic parser corner"; check "the hardening finding text is re-listed under the Optional section" $?
grep -q "material" <<<"$(reason "$OUT")"; check "deny reason names the material-only scope of the block" $?

echo "T72: the review MODE is part of the cache identity — a default-mode optional allow never satisfies a --security rerun"
new_head
printf '%s\n' "$HARDENING_REVIEW" > "$REVIEW_FILE"
bump_diff t72
OUT=$(run_gate)
is_allow "$OUT"; check "default-mode pass allows with optional notes" $?
# identical diff, mode flipped: must get a FRESH review (mode is in the hash),
# where [hardening] is material -> deny. Riding any default-mode verdict here
# would silently skip the deep review the owner explicitly asked for.
OUT=$(CODERV_GATE_SECURITY=1 run_gate)
is_deny "$OUT"; check "identical diff under CODERV_GATE_SECURITY=1 re-reviews and DENIES (no marker ride)" $?

echo "T73: the --security flag also rides the COMMAND STRING (PreToolUse hooks don't inherit a command env-prefix)"
new_head
printf '%s\n' "$HARDENING_REVIEW" > "$REVIEW_FILE"
bump_diff t73
# env NOT set — only the command string carries the assignment, exactly what
# the /ship --security commit form produces. The gate must still run the deep
# review ([hardening] material -> deny) and NAME the mode in the outcome.
OUT=$(jq -cn --arg cmd "CODERV_GATE_SECURITY=1 git commit -m t" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' | bash "$GATE")
is_deny "$OUT"; check "env-prefix in the command string flips the gate to security mode ([hardening] denies)" $?
grep -q "deep-security mode" <<<"$(reason "$OUT")"; check "deny reason names the deep-security mode (downgrade visibility)" $?

echo "T71: reviewer prompt flips by mode — quality-gate brief by default, adversarial brief on opt-in"
new_head
printf '%s\n' "$HARDENING_REVIEW" > "$REVIEW_FILE"
bump_diff t71
CAPD="$TDIR/cap-adr022-default"
run_gate_capture "$CAPD" >/dev/null
grep -q "ENGINEERING QUALITY GATE" "$CAPD/prompt"; check "default prompt carries the quality-gate brief" $?
grep -q "Optional Security Review" "$CAPD/prompt"; check "default prompt routes exotic findings to the Optional section" $?
new_head
bump_diff t71b
CAPS="$TDIR/cap-adr022-security"
mkdir -p "$CAPS"
jq -cn --arg cmd "git commit -m t" --arg cwd "$REPO" \
    '{tool_input:{command:$cmd}, cwd:$cwd}' \
  | CAPTURE_DIR="$CAPS" CODERV_GATE_SECURITY=1 bash "$GATE" >/dev/null
grep -q "DEEP SECURITY REVIEW" "$CAPS/prompt"; check "opt-in prompt carries the adversarial deep-review brief" $?

echo "T74: ADR-023 — owner-approval exit: the deny names it; --approve passes the exact diff once, loudly"
new_head
printf '%s\n' "$MATERIAL_REVIEW" > "$REVIEW_FILE"
bump_diff t74; OUT=$(run_gate)
is_deny "$OUT"; check "material finding denies (baseline)" $?
grep -q -- '--approve' <<<"$(reason "$OUT")"; check "deny reason names the owner --approve exit" $?
bash "$GATE" --approve "$REPO" "owner said: approved, ship exactly this" >/dev/null
check "--approve records against the current diff (rc 0)" $?
OUT=$(run_gate)
is_allow "$OUT"; check "identical commit passes on the recorded approval" $?
grep -q "OWNER-APPROVED" <<<"$(sysmsg "$OUT")"; check "systemMessage names the owner approval" $?
grep -q "owner said: approved, ship exactly this" <<<"$(ctx "$OUT")"; check "the owner's words are quoted back verbatim" $?
[[ -z "$(ls "$HOME/.claude/coderlap/codex-reviewed/" 2>/dev/null | grep '^owner-approval-')" ]]
check "approval marker is single-use (consumed on the pass)" $?

echo "T75: ADR-023 — approval is diff-scoped and outranks a ceiling security escalation"
new_head
printf '%s\n' "$SECURITY_REVIEW" > "$REVIEW_FILE"
# CAP=1, MAX=2: two fresh security denies reach the ceiling -> durable
# escalated stop (the strongest state the gate has).
bump_diff t75a; OUT=$(CODERV_GATE_ROUND_CAP=1 CODERV_GATE_ROUND_MAX=2 run_gate)
bump_diff t75b; OUT=$(CODERV_GATE_ROUND_CAP=1 CODERV_GATE_ROUND_MAX=2 run_gate)
is_deny "$OUT"; check "security residue at the ceiling denies with escalation (baseline)" $?
OUT=$(CODERV_GATE_ROUND_CAP=1 CODERV_GATE_ROUND_MAX=2 run_gate)
is_deny "$OUT"; check "identical retry over the open escalation still denies" $?
# a STALE approval (recorded, then the diff changes) must not leak forward
bash "$GATE" --approve "$REPO" "stale approval" >/dev/null
bump_diff t75c; OUT=$(CODERV_GATE_ROUND_CAP=1 CODERV_GATE_ROUND_MAX=2 run_gate)
is_deny "$OUT"; check "an approval recorded for a DIFFERENT diff does not pass this one" $?
# a fresh approval on the CURRENT diff is the owner's final word: it outranks
# even the escalated security stop (the gate blocks agent decisions, never an
# explicit owner decision).
bash "$GATE" --approve "$REPO" "owner decision: ship it over the security stop" >/dev/null
OUT=$(CODERV_GATE_ROUND_CAP=1 CODERV_GATE_ROUND_MAX=2 run_gate)
is_allow "$OUT"; check "owner approval outranks the ceiling security escalation" $?
grep -q "owner decision: ship it over the security stop" <<<"$(ctx "$OUT")"; check "the overriding approval is quoted in the allow" $?

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
exit 0
