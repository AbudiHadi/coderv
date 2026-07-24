#!/usr/bin/env bash
# grounding-gate — PreToolUse hook for Claude Code (Edit|Write|MultiEdit|NotebookEdit)
#
# Blocks the session's first CODE edit inside any project that has a doc
# system (CLAUDE.md + docs/) unless a grounding receipt exists — written by
# /before after it actually read the docs, or by an explicit skip declaration.
# The agent cannot ignore the docs and start from scratch: the door is locked,
# not advised.
#
# Never blocks: documentation edits (docs/**, CLAUDE.md, root *.md), anything
# under ~/.claude, /tmp, or projects without the doc system.
#
# Receipt: ~/.claude/coderlap/receipts/<project-path-slug>
#   Written by /before (mode=full) or by a conscious skip (mode=skip).
#   Valid when written during the current session (mtime >= session start,
#   read from the transcript's first timestamp; small clock slack allowed).
#
# Kill switch: CODERV_GATES_OFF=1
#
# <!-- claude-docs-toolkit -->
set -o pipefail

[[ "${CODERV_GATES_OFF:-0}" == "1" ]] && exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Heredoc feeds python its program via stdin, so the hook's JSON input must
# travel via the environment — piping both through stdin loses one of them.
CODERV_HOOK_INPUT=$(cat) python3 - <<'PY'
import datetime, json, os, sys

try:
    data = json.loads(os.environ.get("CODERV_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)

tool_input = data.get("tool_input") or {}
path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
if not path:
    sys.exit(0)
path = os.path.abspath(path)
home = os.path.expanduser("~")

# Harness/state/temp areas are never gated.
for prefix in (os.path.join(home, ".claude"), "/tmp", "/var/tmp"):
    if path == prefix or path.startswith(prefix + os.sep):
        sys.exit(0)

# Find the enclosing CoderLap project: nearest ancestor with CLAUDE.md + docs/.
d = os.path.dirname(path)
root = None
while len(d) > 1 and d != home:
    if os.path.isfile(os.path.join(d, "CLAUDE.md")) and os.path.isdir(os.path.join(d, "docs")):
        root = d
        break
    d = os.path.dirname(d)
if root is None:
    sys.exit(0)  # no doc system here — the gate does not apply

# Documentation edits are never blocked (handoffs, ADRs, doc fixes must flow).
# Only the project-root docs/ counts — src/docs/foo.py is code, not docs.
rel_parts = os.path.relpath(path, root).split(os.sep)
if len(rel_parts) > 1 and rel_parts[0] == "docs":
    sys.exit(0)
if path.endswith(".md") and len(rel_parts) == 1:
    sys.exit(0)

# The slug must be a legal FILENAME on every OS (0.15.1): Windows forbids
# ':' in filenames, so a drive-rooted project (D:\...) used to produce an
# unsatisfiable slug — no receipt could ever exist and the gate locked every
# code edit in the project permanently. Both separators become dashes and
# ':' is stripped; on Linux this is a byte-for-byte no-op. The /before,
# /ship, /lint and /coderv slug snippets (cygpath -w + tr) resolve to this
# same string — writer and reader must never disagree.
slug = root.replace(os.sep, "-")
if os.altsep:
    slug = slug.replace(os.altsep, "-")
slug = slug.replace(":", "")
receipt = os.path.join(home, ".claude", "coderlap", "receipts", slug)

def session_start_epoch():
    """First timestamp in the transcript = when this session began."""
    try:
        with open(data.get("transcript_path") or "") as f:
            for line in f:
                try:
                    ts = json.loads(line).get("timestamp")
                except Exception:
                    continue
                if ts:
                    return datetime.datetime.fromisoformat(
                        ts.replace("Z", "+00:00")).timestamp()
    except Exception:
        pass
    return None

if os.path.isfile(receipt):
    start = session_start_epoch()
    # Valid when written during this session; if the session start can't be
    # read, fall back to a freshness window so the gate fails open, not shut.
    if start is not None:
        if os.path.getmtime(receipt) >= start - 120:
            sys.exit(0)
    elif (datetime.datetime.now().timestamp() - os.path.getmtime(receipt)) < 8 * 3600:
        sys.exit(0)

reason = (
    "GROUNDING GATE (coderlap): first code edit in %s blocked — no grounding "
    "receipt for this session.\n"
    "This project has a doc system; work starts from it, never from scratch. "
    "Do ONE of these, then retry the edit:\n"
    "  1. Run /before <task> — it reads CLAUDE.md + docs, checks prior art, "
    "states a plan, and writes the receipt.\n"
    "  2. Genuinely trivial fix (typo / one-liner)? Declare a conscious skip:\n"
    "     mkdir -p ~/.claude/coderlap/receipts && printf '{\"mode\":\"skip\",\"reason\":\"<why>\"}' > '%s'\n"
    "Docs-only edits (docs/, CLAUDE.md) are never blocked." % (root, receipt)
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
PY
