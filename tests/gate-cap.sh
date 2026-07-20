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

echo
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
exit 0
