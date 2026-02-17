#!/bin/bash
# Stop hook: Advisory check for uncommitted changes
# Non-blocking (always exit 0)
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
  ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
  if [ "$ACTIVE" = "true" ]; then exit 0; fi
else
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHANGES" -gt 0 ]; then
  STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNSTAGED=$((CHANGES - STAGED))
  echo "Pre-stop check:"
  echo "- ${CHANGES} uncommitted file(s) (${STAGED} staged, ${UNSTAGED} unstaged)"
  echo "Consider committing before finishing."
fi

exit 0
