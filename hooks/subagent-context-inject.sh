#!/bin/bash
# SubagentStart hook: Inject project context into subagents
# Provides branch state, modified files, and active plan/solve state.

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

# Parse agent type
if command -v jq >/dev/null 2>&1; then
  AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_name // empty' 2>/dev/null)
else
  AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
fi

PROJECT_NAME="${TOOLKIT_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
VERSION_FILE="${TOOLKIT_VERSION_FILE:-VERSION}"

# =============================================================================
# 1. Gather project state
# =============================================================================
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
MOD_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")

# Modified files list (max 20 for context efficiency)
MOD_FILES=$(git status --porcelain 2>/dev/null | head -20 | awk '{print $2}')

# =============================================================================
# 2. Detect active plan/solve/implement state
# =============================================================================
ACTIVE_STATE=""

# Check for active implement execution
LATEST_EXECUTE=$(ls -td artifacts/execute/*/M*/ 2>/dev/null | head -1)
if [ -n "$LATEST_EXECUTE" ]; then
  PLAN_NAME=$(echo "$LATEST_EXECUTE" | sed 's|artifacts/execute/\([^/]*\)/.*|\1|')
  MILESTONE=$(echo "$LATEST_EXECUTE" | sed 's|.*/\(M[0-9]*\)/.*|\1|')
  ACTIVE_STATE="Active implement: $PLAN_NAME $MILESTONE"
fi

# Check for active solve (GitHub issue)
if [ -f "artifacts/solve/active.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    ISSUE=$(jq -r '.issue_number // empty' artifacts/solve/active.json 2>/dev/null)
    [ -n "$ISSUE" ] && ACTIVE_STATE="${ACTIVE_STATE:+$ACTIVE_STATE | }Active solve: issue #$ISSUE"
  fi
fi

# Check for active refine
LATEST_REFINE=$(ls -td artifacts/refine/*/ 2>/dev/null | head -1)
if [ -n "$LATEST_REFINE" ]; then
  REFINE_SCOPE=$(basename "$LATEST_REFINE")
  ACTIVE_STATE="${ACTIVE_STATE:+$ACTIVE_STATE | }Active refine: $REFINE_SCOPE"
fi

# =============================================================================
# 3. Build context injection
# =============================================================================
CONTEXT="=== ${PROJECT_NAME} Project Context (Subagent: ${AGENT_TYPE:-unknown}) ===
Version: $VERSION | Branch: $BRANCH | Modified files: $MOD_COUNT"

if [ -n "$ACTIVE_STATE" ]; then
  CONTEXT="$CONTEXT
$ACTIVE_STATE"
fi

if [ -n "$MOD_FILES" ]; then
  CONTEXT="$CONTEXT
Changed: $(echo "$MOD_FILES" | tr '\n' ', ' | sed 's/,$//')"
fi

# TODO: read from config — critical rules should be injected from per-project config
# Projects can define their own critical rules in toolkit.toml

# =============================================================================
# 4. Output as structured JSON
# =============================================================================
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}'
else
  SAFE_CTX=$(printf '%s' "$CONTEXT" | sed 's/"/\\"/g' | tr '\n' ' ')
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' "$SAFE_CTX"
fi

exit 0
