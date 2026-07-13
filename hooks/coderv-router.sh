#!/usr/bin/env bash
# coderv-router — UserPromptSubmit hook for Claude Code
#
# Scans every user prompt for INTENT patterns (not just literal phrases) that
# match one of the 6 toolkit skills (before, decision, ship, session, docify,
# lint) and injects a one-line reminder into Claude's context. The model picks
# it up and offers the skill instead of charging ahead.
#
# Why a hook (not just the skill description): skill descriptions are
# guidelines for the model and can be missed mid-task. Hooks run in the
# harness — they can't be forgotten.
#
# Matching philosophy:
#   - Each skill has a HIGH-CONFIDENCE pattern (clear intent → suggest firmly).
#   - Each skill has a LOW-CONFIDENCE pattern (ambiguous → suggest, but ask
#     before acting).
#   - NEGATIVE patterns suppress matches when the surface phrase looks similar
#     but the intent is different (e.g. "update docs" ≠ /docify).
#
# Output: plain text on stdout becomes additional context.
# Exit silently when no trigger matches.
#
# <!-- claude-docs-toolkit -->

set -euo pipefail

PROMPT=$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("prompt", ""))
except Exception:
    pass
' 2>/dev/null || true)

if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# Lowercase + collapse whitespace for matching.
LOWER=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')

declare -a HIGH=()
declare -a LOW=()

# ============================================================
# /decision — INTENT: user is weighing a technical choice
# ============================================================

# HIGH: explicit comparisons or trade-off language.
if [[ "$LOWER" =~ (should\ we|can\ we\ (use|make|switch|move|migrate|do|build)|is\ it\ worth|do\ we\ (use|need|switch|ditch)|why\ did\ we|why\ are\ we|x\ or\ y| vs\.?\ |trade-?off|architectural\ decision|\badr\b|pick\ between|choose\ between|deciding\ between) ]]; then
  HIGH+=("decision")

# LOW: question form that *might* be a tech choice ("what about X?", "how about Y?").
elif [[ "$LOWER" =~ (^|\ )(what\ about|how\ about|what\ if\ we|could\ we|any\ reason\ (not\ )?to)\  ]]; then
  LOW+=("decision")
fi

# ============================================================
# /before — INTENT: user is asking for non-trivial code work
# ============================================================

# NEGATIVE: explicit small-task signals — never fire /before.
BEFORE_NEGATIVE=0
if [[ "$LOWER" =~ (quick\ fix|small\ change|tiny|just\ a|typo|one[-\ ]liner|small\ edit) ]]; then
  BEFORE_NEGATIVE=1
fi

if [[ "$BEFORE_NEGATIVE" -eq 0 ]]; then
  # HIGH: imperative verbs that imply real work.
  if [[ "$LOWER" =~ (^|\ )(add|build|implement|refactor|rewrite|rename|integrate|migrate|port|extract|set\ up|wire\ up|create\ a|introduce|scaffold|bootstrap|design)\  ]] \
     || [[ "$LOWER" =~ (take\ your\ time|think\ about\ this|be\ careful|do\ this\ properly|do\ it\ right) ]]; then
    HIGH+=("before")

  # LOW: softer asks ("can you make X", "help me with Y", "i want to add").
  elif [[ "$LOWER" =~ (can\ you\ (make|add|build|change|update)|help\ me\ (build|add|implement)|i\ (want|need)\ to\ (add|build|implement|change)|let\'?s\ build|let\'?s\ add) ]]; then
    LOW+=("before")
  fi
fi

# ============================================================
# /ship — INTENT: user wants to commit / wrap a change
# ============================================================

# NEGATIVE: pure status questions.
SHIP_NEGATIVE=0
if [[ "$LOWER" =~ (what\ changed|show\ me\ the\ diff|git\ status|git\ log|git\ diff) ]]; then
  SHIP_NEGATIVE=1
fi

if [[ "$SHIP_NEGATIVE" -eq 0 ]]; then
  # HIGH: direct commit/push intent.
  if [[ "$LOWER" =~ (^|\ )(commit|push)([[:space:]]|$|[[:punct:]]) ]] \
     || [[ "$LOWER" =~ (commit\ this|push\ this|push\ it|push\ up|git\ commit|create\ (a\ )?commit|make\ (a\ )?commit|commit\ and\ push|draft\ (a\ )?commit\ message|write\ (a\ )?commit\ message|ready\ to\ (ship|merge|commit|push)|let\'?s\ commit|let\'?s\ ship) ]]; then
    HIGH+=("ship")

  # LOW: completion signals that often precede a commit.
  elif [[ "$LOWER" =~ (all\ done|i\'?m\ done|we\'?re\ done|wrap\ (this\ )?up|finalize|finish\ (this|it|up)|let\'?s\ finish) ]]; then
    LOW+=("ship")
  fi
fi

# ============================================================
# /session — INTENT: end of work, or resume from prior work
# ============================================================

# HIGH end-of-session
if [[ "$LOWER" =~ (done\ for\ (today|the\ day|now)|wrapping\ up|see\ you\ (tomorrow|next\ week|monday|later)|stopping\ here|pausing\ here|leaving\ it\ here|continue\ later|tomorrow-?me|taking\ a\ break|lunch\ break|end\ of\ day|\beod\b|signing\ off|log\ off) ]]; then
  HIGH+=("session-end")

# LOW end-of-session
elif [[ "$LOWER" =~ (let\'?s\ pause|gotta\ go|brb\b|back\ later|need\ to\ stop) ]]; then
  LOW+=("session-end")
fi

# HIGH start-of-session / resume
if [[ "$LOWER" =~ (where\ did\ i\ leave\ off|where\ were\ we|what\ was\ i\ doing|pick\ up\ where|continue\ from\ (yesterday|last\ time)|remind\ me\ what\ we\ were|what\ was\ last|read\ the\ last\ session|last\ session) ]]; then
  HIGH+=("session-start")

# LOW start-of-session — short status / "what's next" questions.
# These often mean "read the handoff", but could also be a normal question.
elif [[ "$LOWER" =~ (^|\ )(what\'?s\ next|what\ do\ we\ have\ next|whats\ next|what\ now|status\??\ ?$|where\ are\ we|catch\ me\ up)([[:space:]]|$|[[:punct:]]) ]]; then
  LOW+=("session-start")
fi

# ============================================================
# /docify — INTENT: generate fresh docs from the codebase
# ============================================================

# NEGATIVE: editing existing docs is NOT /docify.
DOCIFY_NEGATIVE=0
if [[ "$LOWER" =~ (update\ (the\ )?docs|fix\ (the\ )?docs|edit\ (the\ )?docs|refresh\ the|add\ to\ (the\ )?docs|fix\ a\ typo|add\ a\ line|tweak\ the\ docs|small\ doc) ]]; then
  DOCIFY_NEGATIVE=1
fi

if [[ "$DOCIFY_NEGATIVE" -eq 0 ]]; then
  # HIGH: explicit "generate / create / write fresh docs".
  if [[ "$LOWER" =~ (write\ (the\ )?docs|write\ documentation|create\ (the\ )?docs|generate\ (the\ )?docs|make\ (the\ )?docs|make\ a\ doc|need\ docs|no\ docs|document\ this\ project|document\ the\ (project|codebase|repo)|explain\ the\ (codebase|project|repo)|bootstrap\ docs|fresh\ docs|docs\ are\ missing|docs\ outdated|our\ docs\ are\ outdated|set\ up\ docs) ]]; then
    HIGH+=("docify")

  # LOW: bare mentions of docs without verb context.
  elif [[ "$LOWER" =~ (^|\ )(docs|documentation|readme)\??\ ?$ ]]; then
    LOW+=("docify")
  fi
fi

# ============================================================
# /lint — INTENT: audit existing docs for rot (NOT generate: /docify)
# ============================================================

# HIGH: explicit audit/health-check language about docs.
if [[ "$LOWER" =~ (lint\ (the\ )?docs|audit\ (the\ )?docs|docs?\ (are\ )?(lying|rott(en|ing)|stale)|doc\ rot|check\ for\ contradictions|contradictions?\ in\ (the\ )?docs|gap\ in\ (the\ )?(docs|documentation)|docs\ health|verify\ (the\ )?docs|do\ the\ docs\ match|docs\ match\ the\ code|clean\ up\ (the\ )?docs) ]]; then
  HIGH+=("lint")

# LOW: freshness questions that might mean "run a lint".
elif [[ "$LOWER" =~ (docs\ up\ to\ date|are\ the\ docs\ (current|correct|right|accurate)|trust\ the\ docs) ]]; then
  LOW+=("lint")
fi

# ============================================================
# Render output
# ============================================================

if [[ ${#HIGH[@]} -eq 0 && ${#LOW[@]} -eq 0 ]]; then
  exit 0
fi

describe() {
  case "$1" in
    decision)      echo "/decision — user is weighing a technical choice with a trade-off. Offer to log it as an ADR (30 seconds, prevents re-debating later)." ;;
    before)        echo "/before — non-trivial change requested. Read relevant docs, grep prior art, state a plan, wait for approval before coding." ;;
    ship)          echo "/ship — user signaled commit intent. Run the pre-commit checklist (diff review, doc updates, citation validation, commit message draft) before committing." ;;
    session-end)   echo "/session — user is wrapping up. Offer to write a handoff note so the next session picks up cleanly." ;;
    session-start) echo "/session last — user is resuming. Read the most recent handoff before answering." ;;
    docify)        echo "/docify — user wants fresh project docs generated from the codebase. Confirm scope, then run." ;;
    lint)          echo "/lint — user suspects doc rot (contradictions, stale claims, dead references). Run the docs health check and report findings with file:line." ;;
  esac
}

echo "[coderv-router] Toolkit skill match detected."

if [[ ${#HIGH[@]} -gt 0 ]]; then
  echo
  echo "HIGH confidence — offer this skill firmly before continuing:"
  for m in "${HIGH[@]}"; do echo "  • $(describe "$m")"; done
fi

if [[ ${#LOW[@]} -gt 0 ]]; then
  echo
  echo "LOW confidence — phrasing is ambiguous. Briefly check intent before running:"
  for m in "${LOW[@]}"; do echo "  • $(describe "$m")"; done
fi

echo
echo "Rule: offer the skill explicitly (\"Want me to run /<name>?\") rather than silently doing the work without it. Skip the offer only if the user has already declined this skill earlier in the same session."

exit 0
