#!/usr/bin/env bash
# context-gate — Stop hook for Claude Code
#
# Enforces the dumb-zone boundary using ABSOLUTE occupied-context tokens, not a
# percentage of the model's context window (ADR-012). The "dumb zone" (context
# rot / lost-in-the-middle) sets in at an absolute amount of occupied context —
# ~150-200k — regardless of how many tokens the model will admit. A 1M window
# does NOT mean quality survives to 750k; dividing usage by a huge window (or by
# a stale 200k default) reports the wrong number and gates at the wrong place.
#
# The gate fires at:
#     limit = min( CODERV_CTX_BUDGET , CODERV_CTX_WINDOW * CODERV_CTX_SAFETY_PCT/100 )
#   - block at `limit`      — the agent is told the only sanctioned move is
#     writing the session handoff, then a fresh session.
#   - warn  at 0.75 * limit — systemMessage to the user to wrap up.
# `CODERV_CTX_BUDGET` (the absolute quality floor) is the real guard; the window
# term is only a ceiling so genuinely small-window models still get caught.
#
# The block fires ONCE per session (marker file) so "one more tiny thing"
# afterwards doesn't re-trap the user in handoff loops. stop_hook_active is
# honoured so the hook never fights the harness. Both gates re-arm after
# compaction (context drops well below the warn line).
#
# Config (env):
#   CODERV_CTX_BUDGET      absolute quality-budget tokens   (default 180000)
#   CODERV_CTX_WINDOW      model's real context window      (default 1000000)
#   CODERV_CTX_SAFETY_PCT  window fraction for the ceiling  (default 90)
# Back-compat: CODERV_CONTEXT_WINDOW (old window var) is still read as a
# fallback for CODERV_CTX_WINDOW. The old percentage knobs
# CODERV_CTX_WARN_PCT/CODERV_CTX_BLOCK_PCT are superseded by the absolute
# budget and are ignored if set (see CHANGELOG / ADR-012 for the migration).
# Kill switch:  CODERV_GATES_OFF=1
#
# <!-- claude-docs-toolkit -->
set -o pipefail

[[ "${CODERV_GATES_OFF:-0}" == "1" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Housekeeping: markers older than 7 days are dead sessions.
find "$HOME/.claude/coderlap/state" -maxdepth 1 -name 'ctx*' -mtime +7 -delete 2>/dev/null

# Heredoc feeds python its program via stdin, so the hook's JSON input must
# travel via the environment — piping both through stdin loses one of them.
CODERV_HOOK_INPUT=$(cat) python3 - <<'PY'
import json, os, sys

try:
    data = json.loads(os.environ.get("CODERV_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

# Already blocked this turn and the agent is continuing because of us —
# let it stop normally now. Prevents infinite block loops.
if data.get("stop_hook_active"):
    sys.exit(0)


def _int_env(name, default):
    """Read a positive int from env; fall back on missing/blank/invalid/<=0."""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        val = int(raw)
    except (TypeError, ValueError):
        return default
    return val if val > 0 else default


def _usage_tokens(u):
    """Occupied context after this call = the call's total input (uncached
    input + cache read + cache creation — disjoint sets, no double-count) PLUS
    its output_tokens. At Stop time the assistant's just-generated response is
    carried into the next turn's context, so leaving it out undercounts and can
    let a large response cross the budget without tripping the gate."""
    if not isinstance(u, dict):
        return None
    if "input_tokens" not in u:
        return None
    return (u.get("input_tokens") or 0) \
        + (u.get("cache_read_input_tokens") or 0) \
        + (u.get("cache_creation_input_tokens") or 0) \
        + (u.get("output_tokens") or 0)


# --- Source the current occupied-context size --------------------------------
# The input side of the LAST main-chain API call in the transcript — an
# unambiguous per-call figure (uncached input + cache read + cache creation).
# Never SUM across transcript messages (that overcounts massively); sidechain/
# subagent entries are skipped, their windows are their own. We deliberately do
# NOT trust any consolidated `usage` field on the hook payload: whether it is
# per-call or cumulative-across-the-session is unverified, and a cumulative
# value would overcount and block healthy sessions — the transcript's last call
# is the one figure we can reason about.
ctx = None
try:
    with open(data.get("transcript_path") or "") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("isSidechain"):
                continue
            t = _usage_tokens((obj.get("message") or {}).get("usage"))
            if t is not None:
                ctx = t
except Exception:
    sys.exit(0)
if ctx is None:
    sys.exit(0)

# --- Compute the absolute trigger limit --------------------------------------
budget = _int_env("CODERV_CTX_BUDGET", 180000)
window = _int_env("CODERV_CTX_WINDOW",
                  _int_env("CODERV_CONTEXT_WINDOW", 1000000))
safety_pct = _int_env("CODERV_CTX_SAFETY_PCT", 90)
if safety_pct > 100:  # a "fraction of window" above 100% would push the
    safety_pct = 100  # ceiling past the real window — clamp so it still bites.

ceiling = window * safety_pct // 100
block_at = min(budget, ceiling) if ceiling > 0 else budget
warn_at = (block_at * 3) // 4  # 0.75 * limit, integer tokens

state_dir = os.path.join(os.path.expanduser("~"), ".claude", "coderlap", "state")
os.makedirs(state_dir, exist_ok=True)
sid = data.get("session_id") or "unknown"
block_marker = os.path.join(state_dir, "ctxgate-" + sid)
warn_marker = os.path.join(state_dir, "ctxwarn-" + sid)


def k(n):
    return f"{round(n / 1000)}k"


# Context dropped well below the warn line (compaction happened): re-arm both
# gates, otherwise a session that compacted once has no dumb-zone protection
# for the rest of its life. Re-arm margin is 1/6 of the limit (was a fixed 10
# percentage points — that scaled badly as an absolute gap once the limit grew).
if ctx < warn_at - (block_at // 6):
    for m in (block_marker, warn_marker):
        try:
            os.remove(m)
        except OSError:
            pass
    sys.exit(0)

if ctx >= block_at and not os.path.exists(block_marker):
    with open(block_marker, "w") as f:
        f.write(str(ctx))
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"CONTEXT GATE (coderlap): ~{ctx:,} tokens of context are in use — "
            f"past the {block_at:,}-token dumb-zone budget. Past this point "
            "quality degrades and compaction will corrupt state. Do NOT start "
            "new work. The recommended moves now: (1) finish the current "
            "atomic step if one is mid-flight, (2) write the session handoff "
            "per /session — paste RAW command outputs (git status, git log, "
            "versions) VERBATIM, never paraphrase state — then (3) tell the "
            "user to start a fresh session, which resumes from the handoff. "
            "This is a one-shot Stop nudge (it does not hard-block your next "
            "action — a subsequent Stop proceeds normally); it fires once per "
            "session and re-arms after compaction. The user is the final "
            "authority and may tell you to continue in this session anyway."
        ),
    }))
    sys.exit(0)

if ctx >= warn_at:
    # Warn once per 10k-token bucket, not every turn.
    prev = -1
    try:
        with open(warn_marker) as f:
            prev = int(f.read().strip())
    except Exception:
        pass
    bucket = ctx // 10000
    if bucket > prev:
        with open(warn_marker, "w") as f:
            f.write(str(bucket))
        if ctx >= block_at:
            msg = (f"⚠ coderlap context gate: ~{k(ctx)} tokens — past the "
                   f"{k(block_at)} hard budget. Wrap up NOW: /session, then a "
                   "fresh session.")
        else:
            msg = (f"⚠ coderlap context gate: ~{k(ctx)} of {k(block_at)} tokens "
                   "of context used — wrap up and run /session before the "
                   "hard budget.")
        print(json.dumps({"systemMessage": msg}))
sys.exit(0)
PY
