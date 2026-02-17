#!/usr/bin/env bash
# SessionStart(compact) hook: Re-inject critical context AFTER compaction
# Reads state saved by pre-compact.sh
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_NAME="$TOOLKIT_PROJECT_NAME"
STATE_FILE="$PROJECT_DIR/.claude/compact-state.txt"

if [ -f "$STATE_FILE" ]; then
  echo "=== Context re-injected after compaction ==="
  cat "$STATE_FILE"
else
  # Fallback: generate fresh context
  cd "$PROJECT_DIR" || exit 0
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "=== Context re-injected after compaction ==="
  echo "GIT STATE ($PROJECT_NAME): branch=${BRANCH}, modified_files=${MODIFIED}"
fi

# Inject critical rules from config (always, even with state file)
# Use process substitution to avoid subshell (HAS_RULES must persist)
HAS_RULES=false
while read -r RULE; do
  [ -z "$RULE" ] && continue
  if [ "$HAS_RULES" = false ]; then
    echo ""
    echo "--- Critical Rules ---"
    HAS_RULES=true
  fi
  echo "- $RULE"
done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_SUBAGENT_CONTEXT_CRITICAL_RULES")

exit 0
