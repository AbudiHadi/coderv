#!/usr/bin/env bash
# Claude Docs Toolkit installer
# Copies skills to one or more host CLI skill directories, installs the
# Claude-Code hooks/gates, and completes the two-brain workflow: it detects
# whether the Codex CLI is installed + authed, installs the reviewer rules
# Codex reads (~/.codex/AGENTS.md, never clobbering an existing file), and
# reports honestly which mode the machine ended up in (two-brain ON, Codex
# found-but-not-authed, or single-brain with a one-line enable path).
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
  --claude     Install to ~/.claude/skills/  (also installs hooks + gates, and
               completes the two-brain setup: reviewer rules to ~/.codex/AGENTS.md
               + an honest report of whether Codex is installed/authed)
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

# Detect the Codex CLI's state, so setup can complete the two-brain workflow
# or tell the user exactly how to enable it. Echoes one of:
#   absent | installed | authed
codex_state() {
  command -v codex >/dev/null 2>&1 || { echo "absent"; return; }
  if codex login status >/dev/null 2>&1; then echo "authed"; else echo "installed"; fi
}

# Install the portable reviewer rules to ~/.codex/AGENTS.md so Codex knows its
# role in the two-brain workflow. NEVER overwrites a user's existing file:
# if the file exists we append our rules inside a marked block (idempotent —
# skipped when the marker is already present); if absent we create it from the
# template. The marker lets --uninstall remove exactly our block and nothing
# else. Args: none. Uses AGENTS_TEMPLATE + CODEX_HOME.
AGENTS_TEMPLATE="$SCRIPT_DIR/templates/codex-AGENTS.md"
AGENTS_START="<!-- claude-docs-toolkit:agents START -->"
AGENTS_END="<!-- claude-docs-toolkit:agents END -->"
# Written as the FIRST line only when the installer CREATED the whole file (no
# pre-existing file). It is what lets --uninstall tell "a file we made" from "a
# pre-existing (possibly empty) file we appended a block to" — the two are
# otherwise byte-identical. Absent on the append path.
AGENTS_OWNED="<!-- claude-docs-toolkit:agents OWNS-FILE -->"

# Emit the reviewer rules wrapped in our START/END marked block, to stdout.
# ALWAYS marker-wrapped — for both create and append — so ownership is proven
# by the marker, never by a byte-compare heuristic. Args: none.
emit_codex_block() {
  printf '%s\n' "$AGENTS_START"
  printf '%s\n' "<!-- Managed by claude-docs-toolkit. Edit above/below, not inside; --uninstall removes this block. -->"
  cat "$AGENTS_TEMPLATE"
  printf '%s\n' "$AGENTS_END"
}

# Set to 1 by install_codex_rules when the reviewer rules are in place, so the
# closing status line never claims rules exist when the template was missing.
CODEX_RULES_INSTALLED=0

install_codex_rules() {
  if [[ ! -f "$AGENTS_TEMPLATE" ]]; then
    echo -e "    ${YELLOW}skipped${NC} reviewer rules (templates/codex-AGENTS.md not in toolkit)"
    return 0
  fi
  CODEX_RULES_INSTALLED=1
  local dst="$CODEX_HOME/AGENTS.md"
  mkdir -p "$CODEX_HOME"

  if [[ ! -f "$dst" ]]; then
    # We are creating the whole file: stamp the OWNS-FILE sentinel first so
    # uninstall knows it may remove the file entirely (a pre-existing empty
    # file we merely appended to must NOT be deleted — hence the sentinel).
    { printf '%s\n' "$AGENTS_OWNED"; emit_codex_block; } > "$dst"
    echo -e "    ${GREEN}installed${NC} reviewer rules → $dst"
    return 0
  fi

  # File exists — never clobber it. Append our rules as a marked block, once.
  # Exact-line match so user prose mentioning the marker text isn't misread.
  if grep -qxF "$AGENTS_START" "$dst" 2>/dev/null; then
    echo -e "    ${YELLOW}exists${NC}  reviewer rules already present in $dst (marked block)"
    return 0
  fi
  # Ensure the file ends in a newline so the START marker lands on its own line.
  # Uninstall removes the START..END lines (block) but preserves every other
  # line — including anything the user adds later, above or below the block —
  # so the removal is line-exact, not byte-exact. (A rare CRLF file is
  # normalised to LF and a missing final newline is added; see ADR-011 — that
  # trade-off is accepted in favour of never destroying user edits.)
  [[ -s "$dst" && -n "$(tail -c1 "$dst")" ]] && printf '\n' >> "$dst"
  emit_codex_block >> "$dst"
  echo -e "    ${GREEN}appended${NC} reviewer rules (marked block) → $dst"
}

# Remove ONLY our marked block from ~/.codex/AGENTS.md, leaving the user's own
# content intact. If we originally created the whole file (it is exactly our
# template with no user edits) remove it entirely. Args: none.
uninstall_codex_rules() {
  local dst="$CODEX_HOME/AGENTS.md" rc
  [[ -f "$dst" ]] || return 0

  # Exact-line match (grep -x), never substring: user prose that merely mentions
  # the marker text must not be read as our block.
  if grep -qxF "$AGENTS_START" "$dst" 2>/dev/null || grep -qxF "$AGENTS_END" "$dst" 2>/dev/null; then
    # Strip our block ONLY if the markers are well-formed: exactly one START
    # line, exactly one END line, START before END. Any other shape (missing
    # partner, wrong order, duplicated markers) is hand-edited/corrupted —
    # removing it blindly could eat the user's own content, so Python exits
    # nonzero and we leave the file untouched with a warning. All marker checks
    # live in one place (Python) so bash and Python can't disagree.
    if python3 - "$dst" "$AGENTS_START" "$AGENTS_END" "$AGENTS_OWNED" <<'PY'
import sys, os
path, start, end, owned = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = open(path).read().splitlines(keepends=True)
# Exact-line match: a marker is a line equal to the marker text (ignoring only
# its trailing newline), NOT a line that merely contains it.
starts = [i for i, ln in enumerate(lines) if ln.rstrip("\n") == start]
ends   = [i for i, ln in enumerate(lines) if ln.rstrip("\n") == end]
# Well-formed = exactly one START line, one END line, START before END. Any
# other shape (missing partner, wrong order, duplicated markers) is hand-
# edited/corrupted — removing it blindly could eat user content, so exit
# nonzero and the caller leaves the file untouched.
if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
    sys.exit(3)
s0, e0 = starts[0], ends[0]
# The OWNS-FILE sentinel (written only on fresh create) sits on the line just
# above START; remove it together with the block when present.
has_sentinel = s0 >= 1 and lines[s0 - 1].rstrip("\n") == owned
lo = s0 - 1 if has_sentinel else s0
# Line-based removal: drop the block (and sentinel) lines, KEEP every other
# line verbatim — including anything the user added later, above OR below the
# block. This preserves post-install edits (the byte-length-truncate approach
# did not); the trade-off is CRLF→LF / added-final-newline on exotic files,
# accepted per ADR-011.
out = lines[:lo] + lines[e0 + 1:]
# Remove the whole file ONLY when we created it (sentinel) AND nothing else
# remains. A pre-existing file (no sentinel) or one the user wrote into is
# always kept.
if has_sentinel and not out:
    os.remove(path); sys.exit(10)   # 10 = file removed (was ours, now empty)
open(path, "w").writelines(out)
sys.exit(0)
PY
    then
      echo -e "    ${GREEN}removed${NC} reviewer-rules block from $dst"
    else
      rc=$?   # capture BEFORE any command (incl. `local`) resets $?
      if [[ "$rc" -eq 10 ]]; then
        echo -e "    ${GREEN}removed${NC} reviewer rules $dst (was toolkit-created)"
      else
        echo -e "    ${YELLOW}skipped${NC} $dst — reviewer-rules markers are malformed/hand-edited"
        echo -e "             (remove the block manually to avoid data loss)"
      fi
    fi
    return 0
  fi

  # No toolkit marker at all → a file the user fully owns. Never touch it.
  echo -e "    ${YELLOW}skipped${NC} $dst (no toolkit marker — leaving your file untouched)"
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
    uninstall_codex_rules
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

  # Complete the second brain: install the reviewer rules Codex reads. This
  # runs regardless of whether Codex is installed yet — the rules sit ready
  # for when it is, and the honest status line below says which mode you got.
  echo -e "${BLUE}→ Codex reviewer rules${NC} (the second brain)"
  install_codex_rules
fi

if [[ "$TARGET_CODEX" -eq 1 ]]; then
  install_skills_for_host "Codex CLI" "$CODEX_HOME/skills"
fi

if [[ "$TARGET_GEMINI" -eq 1 ]]; then
  install_skills_for_host "Gemini CLI" "$GEMINI_HOME/skills"
fi

echo
echo -e "${GREEN}Done.${NC}"

# Two-brain status — honest about which mode this machine got. Only meaningful
# when the Claude target installed the gate + reviewer rules.
if [[ "$TARGET_CLAUDE" -eq 1 ]]; then
  echo
  case "$(codex_state)" in
    authed)
      echo -e "${GREEN}Two-brain workflow: ON.${NC} Codex is installed and authed — the"
      echo "codex-review-gate will review every commit adversarially."
      ;;
    installed)
      echo -e "${YELLOW}Two-brain workflow: Codex found but not signed in.${NC}"
      echo "Run  codex login  to turn on adversarial review. Until then commits"
      echo "pass through single-brain (the gate fails open with a warning)."
      ;;
    absent)
      echo -e "${YELLOW}Two-brain workflow: second brain OFF.${NC} Codex CLI isn't installed,"
      echo "so commits run single-brain now (the gate fails open harmlessly)."
      echo "To enable adversarial review:"
      echo -e "    ${BLUE}npm i -g @openai/codex && codex login${NC}"
      ;;
  esac
  # Reviewer-rules status applies to EVERY Codex state — the reviewer needs its
  # rules whether or not Codex is authed. Never claim they are installed when
  # the template was missing (CODEX_RULES_INSTALLED stays 0 in that case).
  if [[ "$CODEX_RULES_INSTALLED" -eq 1 ]]; then
    echo "Reviewer rules: in place at ~/.codex/AGENTS.md."
  else
    echo -e "${RED}Reviewer rules: NOT installed${NC} — templates/codex-AGENTS.md was"
    echo "missing from the toolkit; re-run from a complete checkout, or Codex will"
    echo "review without the two-brain rules."
  fi
fi
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
