#!/usr/bin/env bash
# CoderLap Docs Toolkit — release gate.
# The "VERSION + CHANGELOG + tag + release + website move together" rule,
# enforced by a machine instead of memory. Refuses to release unless every
# piece is in place; then tags, pushes, syncs the website, and prints the
# one command left for a human (gh release create).
#
# Usage:
#   ./release.sh              # verify + tag + push + site sync
#   ./release.sh --check      # verify only, change nothing (CI-friendly)
#
# Website sync: set CODERV_SITE_DIR to the coderv.dev repo (default
# /home/appuser/apps/coderv-docs). Skipped with a warning if absent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SITE_DIR="${CODERV_SITE_DIR:-/home/appuser/apps/coderv-docs}"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
fail() { echo -e "${RED}BLOCKED${NC} $1"; exit 1; }
ok()   { echo -e "${GREEN}ok${NC}     $1"; }
warn() { echo -e "${YELLOW}warn${NC}   $1"; }

VERSION=$(tr -d '[:space:]' < VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION file is not semver: '$VERSION'"
ok "VERSION = $VERSION"

# 1. CHANGELOG's newest entry must be this exact version.
TOP_ENTRY=$(grep -m1 '^## \[' CHANGELOG.md | sed -E 's/^## \[([^]]+)\].*/\1/')
[[ "$TOP_ENTRY" == "$VERSION" ]] || fail "CHANGELOG top entry is [$TOP_ENTRY], VERSION is $VERSION — they must move together"
ok "CHANGELOG top entry matches"

# 2. CHANGELOG entry must carry a real ISO date (absolute-dates rule).
grep -m1 "^## \[$VERSION\]" CHANGELOG.md | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
  || fail "CHANGELOG [$VERSION] entry has no ISO date"
ok "CHANGELOG entry dated"

# 3. Working tree must be clean — the bump is a commit, not a loose file.
[[ -z "$(git status --porcelain)" ]] || fail "working tree not clean — commit the release changes first"
ok "working tree clean"

# 4. Tag must not already exist.
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  fail "tag v$VERSION already exists — bump VERSION or delete the tag deliberately"
fi
ok "tag v$VERSION is free"

# 5. Every skill must have TRIGGER and SKIP blocks (release-blocking rule).
for f in skills/*/SKILL.md; do
  grep -q 'TRIGGER' "$f" || fail "$f has no TRIGGER block"
  grep -q 'SKIP'    "$f" || fail "$f has no SKIP block"
done
ok "all $(ls -d skills/*/ | wc -l) skills carry TRIGGER + SKIP"

# 6. Website check (report even in --check).
SITE_TS="$SITE_DIR/astro-site/src/config/site.ts"
if [[ -f "$SITE_TS" ]]; then
  SITE_V=$(grep -oE "version: '[^']+'" "$SITE_TS" | cut -d"'" -f2)
  if [[ "$SITE_V" == "$VERSION" ]]; then
    ok "website site.ts already at $VERSION"
  else
    [[ "$CHECK_ONLY" -eq 1 ]] && warn "website site.ts at $SITE_V (will be synced on release)"
  fi
else
  warn "website repo not found at $SITE_DIR — site sync will be skipped (set CODERV_SITE_DIR)"
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  echo -e "${GREEN}All release gates pass.${NC} Run ./release.sh to tag v$VERSION."
  exit 0
fi

# ---- Act ----
git tag -a "v$VERSION" -m "v$VERSION"
ok "tagged v$VERSION"
git push origin HEAD --tags
ok "pushed branch + tag"

# Website sync: bump site.ts, rebuild as the repo's owner, commit.
if [[ -f "$SITE_TS" && "${SITE_V:-}" != "$VERSION" ]]; then
  SITE_OWNER=$(stat -c '%U' "$SITE_TS" 2>/dev/null || stat -f '%Su' "$SITE_TS")
  sed -i.bak -E "s/version: '[^']+'/version: '$VERSION'/" "$SITE_TS" && rm -f "$SITE_TS.bak"
  if sudo -u "$SITE_OWNER" bash -c "cd '$SITE_DIR/astro-site' && export PATH=\$(ls -d /home/$SITE_OWNER/.nvm/versions/node/*/bin 2>/dev/null | tail -1):\$PATH && npm run build" >/dev/null 2>&1; then
    ok "website rebuilt at $VERSION"
  else
    warn "website build FAILED — site.ts updated but dist is stale; rebuild manually"
  fi
  git -C "$SITE_DIR" add -A
  git -C "$SITE_DIR" commit -m "v$VERSION: site sync" >/dev/null && ok "website repo committed" \
    || warn "website repo commit skipped"
fi

echo
echo -e "${GREEN}Released v$VERSION.${NC} One human step left:"
echo "  gh release create v$VERSION --title \"v$VERSION\" --notes-file <(awk '/^## \\[$VERSION\\]/{f=1;next} /^## \\[/{f=0} f' CHANGELOG.md)"
