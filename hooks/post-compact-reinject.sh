#!/bin/bash
# SessionStart(compact) hook: Re-inject critical context AFTER compaction
# Reads state saved by pre-compact.sh

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PROJECT_NAME="${TOOLKIT_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
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

# TODO: read from config — critical rules should be injected from per-project config

exit 0
