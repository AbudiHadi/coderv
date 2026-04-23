#!/usr/bin/env bash
# Claude Docs Toolkit installer
# Copies skills into ~/.claude/skills/ so they're available in every project

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
SKILLS_DST="${HOME}/.claude/skills"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Claude Docs Toolkit — installer${NC}"
echo

# Sanity check: source dir exists
if [[ ! -d "$SKILLS_SRC" ]]; then
  echo -e "${RED}Error:${NC} $SKILLS_SRC not found. Run install.sh from the toolkit repo root."
  exit 1
fi

# Ensure destination exists
mkdir -p "$SKILLS_DST"

# Parse flags
FORCE=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --force|-f)  FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --help|-h)
      cat <<EOF
Usage: ./install.sh [--force] [--uninstall]

  --force      Overwrite existing skills without asking
  --uninstall  Remove toolkit skills from ~/.claude/skills/
  --help       Show this message

Skills installed to: $SKILLS_DST
EOF
      exit 0
      ;;
  esac
done

# Uninstall path
if [[ "$UNINSTALL" -eq 1 ]]; then
  echo -e "${YELLOW}Uninstalling toolkit skills...${NC}"
  for skill_dir in "$SKILLS_SRC"/*/; do
    skill_name="$(basename "$skill_dir")"
    if [[ -d "$SKILLS_DST/$skill_name" ]]; then
      # Only remove if it matches our SKILL.md (avoid nuking unrelated skills of the same name)
      if [[ -f "$SKILLS_DST/$skill_name/SKILL.md" ]] && \
         grep -q "claude-docs-toolkit" "$SKILLS_DST/$skill_name/SKILL.md" 2>/dev/null; then
        rm -rf "$SKILLS_DST/$skill_name"
        echo -e "  ${GREEN}removed${NC} $skill_name"
      else
        echo -e "  ${YELLOW}skipped${NC} $skill_name (not from this toolkit)"
      fi
    fi
  done
  echo -e "${GREEN}Done.${NC}"
  exit 0
fi

# Install each skill
installed=0
updated=0
skipped=0

for skill_dir in "$SKILLS_SRC"/*/; do
  skill_name="$(basename "$skill_dir")"
  dst="$SKILLS_DST/$skill_name"

  if [[ -d "$dst" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      # Tag the file so uninstaller knows it's ours
      rm -rf "$dst"
      cp -r "$skill_dir" "$dst"
      # Add a marker comment to SKILL.md (hidden at end) for the uninstaller
      printf '\n<!-- claude-docs-toolkit -->\n' >> "$dst/SKILL.md"
      updated=$((updated + 1))
      echo -e "  ${GREEN}updated${NC} /$skill_name"
    else
      echo -e "  ${YELLOW}exists${NC}  /$skill_name (use --force to overwrite)"
      skipped=$((skipped + 1))
    fi
  else
    cp -r "$skill_dir" "$dst"
    printf '\n<!-- claude-docs-toolkit -->\n' >> "$dst/SKILL.md"
    installed=$((installed + 1))
    echo -e "  ${GREEN}installed${NC} /$skill_name"
  fi
done

echo
echo -e "${GREEN}Installed:${NC} $installed  ${BLUE}Updated:${NC} $updated  ${YELLOW}Skipped:${NC} $skipped"
echo
echo -e "${BLUE}Skills are now available in every project you open with Claude Code.${NC}"
echo
echo "Four commands, one loop:"
echo "  /before <task>   — Claude reads the docs + plans, waits for your OK"
echo "  /decision <title> — Write down why you chose X over Y (30 seconds)"
echo "  /ship            — Pre-commit checklist that catches forgotten doc updates"
echo "  /session         — End-of-session handoff, so Monday-you knows what Friday-you was doing"
echo
echo "Docs: https://coderv.dev"
