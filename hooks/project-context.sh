#!/usr/bin/env bash
# project-context — SessionStart hook for Claude Code
#
# Injects a live project map into every new session's context: one line per
# project (newest docs/SESSIONS.md entry + last-touched date), sorted by most
# recent activity, plus a standing rule to Read the real docs before working.
#
# Why a hook (not memory): agent memory is notes the model may skip or let go
# stale. A SessionStart hook runs in the harness, every session, and reads the
# actual files at start time — it cannot be forgotten and cannot go stale.
#
# Configuration:
#   CODERV_PROJECTS_DIR — root folder scanned for */docs/SESSIONS.md
#                         (default: /home/appuser/apps, else ~/apps)
#
# <!-- claude-docs-toolkit -->
set -o pipefail

APPS="${CODERV_PROJECTS_DIR:-/home/appuser/apps}"
[[ -d "$APPS" ]] || APPS="$HOME/apps"
[[ -d "$APPS" ]] || exit 0   # nothing to map on this machine — stay silent

# mtime + path, portable across GNU (Linux) and BSD (macOS) stat.
list_sessions() {
  find "$APPS" -maxdepth 4 -name SESSIONS.md -path '*/docs/*' 2>/dev/null |
    while IFS= read -r f; do
      mt=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null) || continue
      printf '%s %s\n' "$mt" "$f"
    done | sort -rn | head -10 | cut -d' ' -f2-
}

ctx="ACTIVE PROJECT MAP — auto-injected every session by the project-context SessionStart hook.
STANDING RULE: before working on ANY project below, Read its CLAUDE.md file(s) and the newest entries of the listed docs/SESSIONS.md (plus docs/DECISIONS.md + docs/KNOWN-ISSUES.md when changing that area). This map is a pointer, never a substitute. Projects sorted by most recent activity:"

found=0
while IFS= read -r f; do
  found=1
  proj=${f#"$APPS"/}; proj=${proj%%/*}
  sub=${f#"$APPS"/"$proj"/}; sub=${sub%%docs/SESSIONS.md}; sub=${sub%/}
  latest=$(grep -m1 '^## ' "$f" 2>/dev/null | cut -c4-200)
  mts=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null)
  mt=$(date -u -d "@$mts" +%F 2>/dev/null || date -u -r "$mts" +%F 2>/dev/null)
  ctx+="
- ${proj}${sub:+ (${sub})} — $f (updated $mt)
  latest: ${latest:-(no entries)}"
done < <(list_sessions)

[[ "$found" -eq 1 ]] || exit 0   # no documented projects — inject nothing

jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
