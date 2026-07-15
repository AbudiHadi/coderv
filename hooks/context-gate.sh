#!/usr/bin/env bash
# context-gate — Stop hook for Claude Code
#
# Reads the REAL context usage from the session transcript (last main-chain
# API call's input token count) and enforces the dumb-zone boundary:
#   - warn  at CODERV_CTX_WARN_PCT  (default 60%) — systemMessage to the user
#   - block at CODERV_CTX_BLOCK_PCT (default 75%) — the agent is told the only
#     sanctioned move is writing the session handoff, then a fresh session.
#
# The block fires ONCE per session (marker file) so "one more tiny thing"
# afterwards doesn't re-trap the user in handoff loops. stop_hook_active is
# honoured so the hook never fights the harness.
#
# Config (env): CODERV_CONTEXT_WINDOW (default 200000),
#               CODERV_CTX_WARN_PCT, CODERV_CTX_BLOCK_PCT
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

# Current context size = input side of the LAST main-chain API call.
# (Never SUM across messages — that overcounts massively. Sidechain/subagent
# entries are skipped: their windows are their own.)
usage = None
try:
    with open(data.get("transcript_path") or "") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("isSidechain"):
                continue
            u = (obj.get("message") or {}).get("usage")
            if u and "input_tokens" in u:
                usage = u
except Exception:
    sys.exit(0)
if not usage:
    sys.exit(0)

ctx = (usage.get("input_tokens") or 0) \
    + (usage.get("cache_read_input_tokens") or 0) \
    + (usage.get("cache_creation_input_tokens") or 0)

window = int(os.environ.get("CODERV_CONTEXT_WINDOW", "200000"))
warn_pct = int(os.environ.get("CODERV_CTX_WARN_PCT", "60"))
block_pct = int(os.environ.get("CODERV_CTX_BLOCK_PCT", "75"))
pct = round(100 * ctx / window)

state_dir = os.path.join(os.path.expanduser("~"), ".claude", "coderlap", "state")
os.makedirs(state_dir, exist_ok=True)
sid = data.get("session_id") or "unknown"
block_marker = os.path.join(state_dir, "ctxgate-" + sid)
warn_marker = os.path.join(state_dir, "ctxwarn-" + sid)

# Context dropped well below the warn zone (compaction happened): re-arm both
# gates, otherwise a session that compacted once has no dumb-zone protection
# for the rest of its life.
if pct < warn_pct - 10:
    for m in (block_marker, warn_marker):
        try:
            os.remove(m)
        except OSError:
            pass
    sys.exit(0)

if pct >= block_pct and not os.path.exists(block_marker):
    with open(block_marker, "w") as f:
        f.write(str(pct))
    print(json.dumps({
        "decision": "block",
        "reason": (
            f"CONTEXT GATE (coderlap): {pct}% of the context window is used "
            f"(~{ctx:,} of {window:,} tokens). Past this point quality degrades "
            "and compaction will corrupt state — the dumb zone. Do NOT start new "
            "work. The only sanctioned moves now: (1) finish the current atomic "
            "step if one is mid-flight, (2) write the session handoff per "
            "/session — paste RAW command outputs (git status, git log, "
            "versions) VERBATIM, never paraphrase state — then (3) tell the "
            "user to start a fresh session, which resumes from the handoff. "
            "This gate fires once per session (it re-arms after compaction)."
        ),
    }))
    sys.exit(0)

if pct >= warn_pct:
    # Warn once per 5%-bucket, not every turn.
    prev = -1
    try:
        with open(warn_marker) as f:
            prev = int(f.read().strip())
    except Exception:
        pass
    bucket = pct // 5
    if bucket > prev:
        with open(warn_marker, "w") as f:
            f.write(str(bucket))
        if pct >= block_pct:
            msg = (f"⚠ coderlap context gate: {pct}% — past the {block_pct}% "
                   "hard gate. Wrap up NOW: /session, then a fresh session.")
        else:
            msg = (f"⚠ coderlap context gate: {pct}% of context used — wrap up "
                   f"and run /session before {block_pct}% (hard gate).")
        print(json.dumps({"systemMessage": msg}))
sys.exit(0)
PY
