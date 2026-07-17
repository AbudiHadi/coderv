#!/usr/bin/env bash
# Claude Docs Toolkit installer
# Copies skills to one or more host CLI skill directories, and installs the
# coderv-router hook (Claude Code only).
#
# Hosts:
#   --claude  (default)  ~/.claude/skills/
#   --codex              ~/.codex/skills/
#   --gemini             ~/.gemini/skills/
#   --all                all three
#
# Hook behavior:
#   The hooks are Claude-Code-specific and installed only when the Claude
#   target is selected (--claude or --all). Codex and Gemini fall back to the
#   in-skill TRIGGER blocks.
#     coderv-router    (UserPromptSubmit) — suggests the right skill per prompt
#     project-context  (SessionStart)     — injects a live project map (newest
#                      SESSIONS.md entry per project) so every session starts
#                      knowing where work left off. Scans CODERV_PROJECTS_DIR
#                      (default /home/appuser/apps, else ~/apps).
#     grounding-gate   (PreToolUse)       — blocks the first code edit in a
#                      doc-system project until /before wrote a receipt
#     compact-rehydrate(SessionStart)     — after compaction, injects a git
#                      ground-truth snapshot ("the snapshot wins")
#     context-gate     (Stop)             — warns at 60% context, hard-blocks
#                      at 75% (the dumb zone); CODERV_GATES_OFF=1 disables all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
HOOKS_SRC="$SCRIPT_DIR/hooks"

CLAUDE_HOME="${HOME}/.claude"
CODEX_HOME="${HOME}/.codex"
GEMINI_HOME="${HOME}/.gemini"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION_STR=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "?")
echo -e "${BLUE}CoderLap Docs Toolkit v${VERSION_STR} — installer${NC}"
echo

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo -e "${RED}Error:${NC} $SKILLS_SRC not found. Run install.sh from the toolkit repo root."
  exit 1
fi

# ---------- Parse flags ----------
FORCE=0
UNINSTALL=0
TARGET_CLAUDE=0
TARGET_CODEX=0
TARGET_GEMINI=0
EXPLICIT_TARGET=0

for arg in "$@"; do
  case "$arg" in
    --force|-f)  FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --claude)    TARGET_CLAUDE=1; EXPLICIT_TARGET=1 ;;
    --codex)     TARGET_CODEX=1;  EXPLICIT_TARGET=1 ;;
    --gemini)    TARGET_GEMINI=1; EXPLICIT_TARGET=1 ;;
    --all)       TARGET_CLAUDE=1; TARGET_CODEX=1; TARGET_GEMINI=1; EXPLICIT_TARGET=1 ;;
    --help|-h)
      cat <<EOF
Usage: ./install.sh [TARGET...] [--force] [--uninstall]

Targets (default: --claude):
  --claude     Install to ~/.claude/skills/  (also installs coderv-router hook)
  --codex      Install to ~/.codex/skills/   (skills only — no hook system)
  --gemini     Install to ~/.gemini/skills/  (skills only — no hook system)
  --all        Install to all three

Options:
  --force      Overwrite existing files without asking
  --uninstall  Remove toolkit skills + hook from selected target(s)
  --help       Show this message

Examples:
  ./install.sh                    # claude only (default)
  ./install.sh --all              # claude + codex + gemini
  ./install.sh --codex --gemini   # both, skip claude
  ./install.sh --uninstall --all  # remove from everywhere
EOF
      exit 0
      ;;
  esac
done

# Default to Claude when no target specified
if [[ "$EXPLICIT_TARGET" -eq 0 ]]; then
  TARGET_CLAUDE=1
fi

# ---------- Helpers ----------

# Install/update one skill into one target dir. Args: src_skill_dir, dst_skills_dir
install_skill_into() {
  local skill_dir="$1"
  local dst_root="$2"
  local skill_name dst
  skill_name="$(basename "$skill_dir")"
  dst="$dst_root/$skill_name"

  if [[ -d "$dst" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dst"
      cp -r "$skill_dir" "$dst"
      grep -q "claude-docs-toolkit" "$dst/SKILL.md" 2>/dev/null \
        || printf '\n<!-- claude-docs-toolkit -->\n' >> "$dst/SKILL.md"
      echo -e "    ${GREEN}updated${NC} $skill_name"
      return 1  # signal: updated
    else
      echo -e "    ${YELLOW}exists${NC}  $skill_name (use --force to overwrite)"
      return 2  # signal: skipped
    fi
  else
    cp -r "$skill_dir" "$dst"
    grep -q "claude-docs-toolkit" "$dst/SKILL.md" 2>/dev/null \
      || printf '\n<!-- claude-docs-toolkit -->\n' >> "$dst/SKILL.md"
    echo -e "    ${GREEN}installed${NC} $skill_name"
    return 0  # signal: installed
  fi
}

# Install all toolkit skills into one host. Args: host_label, dst_root
install_skills_for_host() {
  local label="$1"
  local dst_root="$2"
  echo -e "${BLUE}→ ${label}${NC} ($dst_root)"
  mkdir -p "$dst_root"
  for skill_dir in "$SKILLS_SRC"/*/; do
    install_skill_into "$skill_dir" "$dst_root" || true
  done
}

# Uninstall all toolkit skills from one host. Args: host_label, dst_root
uninstall_skills_for_host() {
  local label="$1"
  local dst_root="$2"
  echo -e "${YELLOW}→ ${label}${NC} ($dst_root)"
  if [[ ! -d "$dst_root" ]]; then
    echo -e "    ${YELLOW}skipped${NC} (directory does not exist)"
    return 0
  fi
  for skill_dir in "$SKILLS_SRC"/*/; do
    local skill_name dst
    skill_name="$(basename "$skill_dir")"
    dst="$dst_root/$skill_name"
    if [[ -d "$dst" ]]; then
      if [[ -f "$dst/SKILL.md" ]] && grep -q "claude-docs-toolkit" "$dst/SKILL.md" 2>/dev/null; then
        rm -rf "$dst"
        echo -e "    ${GREEN}removed${NC} $skill_name"
      else
        echo -e "    ${YELLOW}skipped${NC} $skill_name (not from this toolkit)"
      fi
    fi
  done
}

# Install the coderv-router hook into Claude Code settings.json. Idempotent.
install_router_hook() {
  if [[ ! -f "$HOOKS_SRC/coderv-router.sh" ]]; then
    echo -e "    ${YELLOW}skipped${NC} hook (hooks/coderv-router.sh not in toolkit)"
    return 0
  fi

  local hook_dst="$CLAUDE_HOME/hooks/coderv-router.sh"
  mkdir -p "$CLAUDE_HOME/hooks"
  cp "$HOOKS_SRC/coderv-router.sh" "$hook_dst"
  chmod +x "$hook_dst"
  echo -e "    ${GREEN}installed${NC} hook → $hook_dst"

  # Wire into settings.json (create or merge — never clobber other keys).
  local settings="$CLAUDE_HOME/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo '{}' > "$settings"
  fi

  python3 - "$settings" "$hook_dst" <<'PY'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print("    ERROR: settings.json is not valid JSON — leaving it alone.")
        sys.exit(0)
if not isinstance(data, dict):
    print("    ERROR: settings.json root is not an object — leaving it alone.")
    sys.exit(0)

hooks = data.setdefault("hooks", {})
ups = hooks.setdefault("UserPromptSubmit", [])

# Already wired?
for entry in ups:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            print("    already wired into settings.json (no change)")
            sys.exit(0)

ups.append({
    "hooks": [
        {"type": "command", "command": hook_path, "timeout": 10}
    ]
})
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("    wired into settings.json (UserPromptSubmit)")
PY
}

# Install the project-context SessionStart hook into Claude Code settings.json.
# Same idempotent merge idiom as install_router_hook.
install_context_hook() {
  if [[ ! -f "$HOOKS_SRC/project-context.sh" ]]; then
    echo -e "    ${YELLOW}skipped${NC} hook (hooks/project-context.sh not in toolkit)"
    return 0
  fi

  local hook_dst="$CLAUDE_HOME/hooks/project-context.sh"
  mkdir -p "$CLAUDE_HOME/hooks"
  cp "$HOOKS_SRC/project-context.sh" "$hook_dst"
  chmod +x "$hook_dst"
  echo -e "    ${GREEN}installed${NC} hook → $hook_dst"

  local settings="$CLAUDE_HOME/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo '{}' > "$settings"
  fi

  python3 - "$settings" "$hook_dst" <<'PY'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print("    ERROR: settings.json is not valid JSON — leaving it alone.")
        sys.exit(0)
if not isinstance(data, dict):
    print("    ERROR: settings.json root is not an object — leaving it alone.")
    sys.exit(0)

hooks = data.setdefault("hooks", {})
starts = hooks.setdefault("SessionStart", [])

for entry in starts:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            print("    already wired into settings.json (no change)")
            sys.exit(0)

starts.append({
    "hooks": [
        {"type": "command", "command": hook_path, "timeout": 15,
         "statusMessage": "Loading project map..."}
    ]
})
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("    wired into settings.json (SessionStart)")
PY
}

# Install one gate hook + wire it into settings.json under any event/matcher.
# Args: script_name, event, matcher ("" = none), timeout_seconds
# Same idempotent merge idiom as install_router_hook.
install_gate_hook() {
  local script="$1" event="$2" matcher="$3" timeout="$4" status_msg="${5:-}"
  if [[ ! -f "$HOOKS_SRC/$script" ]]; then
    echo -e "    ${YELLOW}skipped${NC} hook (hooks/$script not in toolkit)"
    return 0
  fi

  local hook_dst="$CLAUDE_HOME/hooks/$script"
  mkdir -p "$CLAUDE_HOME/hooks"
  cp "$HOOKS_SRC/$script" "$hook_dst"
  chmod +x "$hook_dst"
  echo -e "    ${GREEN}installed${NC} hook → $hook_dst"

  local settings="$CLAUDE_HOME/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo '{}' > "$settings"
  fi

  python3 - "$settings" "$hook_dst" "$event" "$matcher" "$timeout" "$status_msg" <<'PY'
import json, sys
settings_path, hook_path, event, matcher, timeout, status_msg = sys.argv[1:7]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print("    ERROR: settings.json is not valid JSON — leaving it alone.")
        sys.exit(0)
if not isinstance(data, dict):
    print("    ERROR: settings.json root is not an object — leaving it alone.")
    sys.exit(0)

hooks = data.setdefault("hooks", {})
entries = hooks.setdefault(event, [])

for entry in entries:
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            if status_msg and h.get("statusMessage") != status_msg:
                h["statusMessage"] = status_msg
                with open(settings_path, "w") as f:
                    json.dump(data, f, indent=2)
                    f.write("\n")
                print("    already wired — statusMessage refreshed")
            else:
                print("    already wired into settings.json (no change)")
            sys.exit(0)

hook_obj = {"type": "command", "command": hook_path, "timeout": int(timeout)}
if status_msg:
    hook_obj["statusMessage"] = status_msg
new_entry = {"hooks": [hook_obj]}
if matcher:
    new_entry["matcher"] = matcher
entries.append(new_entry)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"    wired into settings.json ({event})")
PY
}

# Uninstall one gate hook + remove its settings.json entry.
# Args: script_name, event
uninstall_gate_hook() {
  local script="$1" event="$2"
  local hook_dst="$CLAUDE_HOME/hooks/$script"
  if [[ -f "$hook_dst" ]]; then
    if grep -q "claude-docs-toolkit" "$hook_dst" 2>/dev/null; then
      rm -f "$hook_dst"
      echo -e "    ${GREEN}removed${NC} $script"
    else
      echo -e "    ${YELLOW}skipped${NC} $script (not from this toolkit)"
    fi
  fi

  local settings="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings" ]]; then
    python3 - "$settings" "$hook_dst" "$event" <<'PY'
import json, sys
settings_path, hook_path, event = sys.argv[1:4]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
hooks = data.get("hooks", {})
entries = hooks.get(event, [])
new_entries = []
removed = False
for entry in entries:
    keep = []
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            removed = True
            continue
        keep.append(h)
    if keep:
        entry = dict(entry, hooks=keep)
        new_entries.append(entry)
if removed:
    if new_entries:
        hooks[event] = new_entries
    else:
        hooks.pop(event, None)
    if not hooks:
        data.pop("hooks", None)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("    removed entry from settings.json")
PY
  fi
}

# Uninstall the project-context hook + remove settings.json entry.
uninstall_context_hook() {
  local hook_dst="$CLAUDE_HOME/hooks/project-context.sh"
  if [[ -f "$hook_dst" ]]; then
    if grep -q "claude-docs-toolkit" "$hook_dst" 2>/dev/null; then
      rm -f "$hook_dst"
      echo -e "    ${GREEN}removed${NC} hook script"
    else
      echo -e "    ${YELLOW}skipped${NC} hook script (not from this toolkit)"
    fi
  fi

  local settings="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings" ]]; then
    python3 - "$settings" "$hook_dst" <<'PY'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
hooks = data.get("hooks", {})
starts = hooks.get("SessionStart", [])
new_starts = []
removed = False
for entry in starts:
    keep = []
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            removed = True
            continue
        keep.append(h)
    if keep:
        entry = dict(entry, hooks=keep)
        new_starts.append(entry)
if removed:
    if new_starts:
        hooks["SessionStart"] = new_starts
    else:
        hooks.pop("SessionStart", None)
    if not hooks:
        data.pop("hooks", None)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("    removed entry from settings.json")
PY
  fi
}

# Uninstall the router hook + remove settings.json entry.
uninstall_router_hook() {
  local hook_dst="$CLAUDE_HOME/hooks/coderv-router.sh"
  if [[ -f "$hook_dst" ]]; then
    if grep -q "claude-docs-toolkit" "$hook_dst" 2>/dev/null; then
      rm -f "$hook_dst"
      echo -e "    ${GREEN}removed${NC} hook script"
    else
      echo -e "    ${YELLOW}skipped${NC} hook script (not from this toolkit)"
    fi
  fi

  local settings="$CLAUDE_HOME/settings.json"
  if [[ -f "$settings" ]]; then
    python3 - "$settings" "$hook_dst" <<'PY'
import json, sys
settings_path, hook_path = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
hooks = data.get("hooks", {})
ups = hooks.get("UserPromptSubmit", [])
new_ups = []
removed = False
for entry in ups:
    keep = []
    for h in entry.get("hooks", []):
        if h.get("command") == hook_path:
            removed = True
            continue
        keep.append(h)
    if keep:
        entry = dict(entry, hooks=keep)
        new_ups.append(entry)
if removed:
    if new_ups:
        hooks["UserPromptSubmit"] = new_ups
    else:
        hooks.pop("UserPromptSubmit", None)
    if not hooks:
        data.pop("hooks", None)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    print("    removed entry from settings.json")
PY
  fi
}

# ---------- Uninstall path ----------
if [[ "$UNINSTALL" -eq 1 ]]; then
  echo -e "${YELLOW}Uninstalling…${NC}"
  if [[ "$TARGET_CLAUDE" -eq 1 ]]; then
    uninstall_skills_for_host "Claude Code" "$CLAUDE_HOME/skills"
    uninstall_router_hook
    uninstall_context_hook
    uninstall_gate_hook "grounding-gate.sh"    "PreToolUse"
    uninstall_gate_hook "codex-review-gate.sh" "PreToolUse"
    uninstall_gate_hook "compact-rehydrate.sh" "SessionStart"
    uninstall_gate_hook "context-gate.sh"      "Stop"
  fi
  if [[ "$TARGET_CODEX" -eq 1 ]]; then
    uninstall_skills_for_host "Codex CLI" "$CODEX_HOME/skills"
  fi
  if [[ "$TARGET_GEMINI" -eq 1 ]]; then
    uninstall_skills_for_host "Gemini CLI" "$GEMINI_HOME/skills"
  fi
  echo -e "${GREEN}Done.${NC}"
  exit 0
fi

# ---------- Install path ----------
if [[ "$TARGET_CLAUDE" -eq 1 ]]; then
  install_skills_for_host "Claude Code" "$CLAUDE_HOME/skills"
  echo -e "${BLUE}→ coderv-router hook${NC} (Claude Code only)"
  install_router_hook
  echo -e "${BLUE}→ project-context hook${NC} (Claude Code only)"
  install_context_hook
  echo -e "${BLUE}→ anti-dumb-zone gates${NC} (Claude Code only)"
  install_gate_hook "grounding-gate.sh"    "PreToolUse"   "Edit|Write|MultiEdit|NotebookEdit" 10
  install_gate_hook "codex-review-gate.sh" "PreToolUse"   "Bash"                              240 "Codex adversarial review..."
  install_gate_hook "compact-rehydrate.sh" "SessionStart" "compact"                           10
  install_gate_hook "context-gate.sh"      "Stop"         ""                                  15
fi

if [[ "$TARGET_CODEX" -eq 1 ]]; then
  install_skills_for_host "Codex CLI" "$CODEX_HOME/skills"
fi

if [[ "$TARGET_GEMINI" -eq 1 ]]; then
  install_skills_for_host "Gemini CLI" "$GEMINI_HOME/skills"
fi

echo
echo -e "${GREEN}Done.${NC}"
echo
echo "Seven commands (you only need to remember the first):"
echo "  /coderv <request> — The front door: classifies your request and drives the pipeline"
echo "  /docify           — Once per project: generate CLAUDE.md + docs from your code"
echo "  /before <task>    — Before coding: Claude reads docs + plans, waits for OK"
echo "  /decision <title> — Log why you chose X over Y (30 seconds)"
echo "  /ship             — Before commit: reviewer + verification scorecard (approve at 100%)"
echo "  /session          — End-of-session handoff (state as pasted evidence)"
echo "  /lint             — Every ~5 sessions: audit docs for rot + contradictions"
echo
echo "Four always-on gates (Claude Code): grounding-gate (docs before code),"
echo "codex-review-gate (Codex adversarial review before commit),"
echo "compact-rehydrate (truth snapshot after compaction), context-gate (dumb-zone guard)."
echo "Kill switch: CODERV_GATES_OFF=1"
echo
echo "Docs: https://coderv.dev"
