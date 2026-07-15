#!/usr/bin/env bash
# compact-rehydrate — SessionStart hook for Claude Code (matcher: compact)
#
# Fires only when a session resumes AFTER COMPACTION — the #1 source of state
# hallucination: compacted summaries describe intent ("shipped v1.2") that may
# never have happened. Injects a live ground-truth snapshot (git status, last
# commits, version files) with a standing instruction: when the summary and
# the snapshot conflict, the snapshot wins.
#
# Kill switch: CODERV_GATES_OFF=1
#
# <!-- claude-docs-toolkit -->
set -o pipefail

[[ "${CODERV_GATES_OFF:-0}" == "1" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // ""' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)

# Belt and braces: settings.json matches on "compact", but verify anyway so a
# looser wiring never sprays snapshots into every startup.
[[ "$SOURCE" == "compact" ]] || exit 0
[[ -d "$CWD" ]] || exit 0
cd "$CWD" || exit 0

snap=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  snap+="\$ git status --short   (first 20 lines)
$(git status --short 2>/dev/null | head -20)
\$ git log -3 --oneline
$(git log -3 --oneline 2>/dev/null)"
  if [[ -f VERSION ]]; then
    snap+="
\$ cat VERSION
$(cat VERSION 2>/dev/null)"
  fi
  if [[ -f package.json ]]; then
    snap+="
package.json version: $(grep -m1 '"version"' package.json 2>/dev/null | sed 's/[ ",]//g')"
  fi
else
  snap+="(not a git repository)
\$ ls   (first 15 entries)
$(ls 2>/dev/null | head -15)"
fi

ctx="POST-COMPACTION GROUND TRUTH — auto-injected by the compact-rehydrate hook.
This session just resumed from a compacted summary. Summaries describe INTENT and can misstate STATE — a prior claim of \"shipped / committed / done\" may be false. The snapshot below is reality at resume time (cwd: $CWD). When the summary and the snapshot conflict, THE SNAPSHOT WINS. Re-verify any state claim (git, versions, running services) with real commands before repeating it or building on it.

$snap"

jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
