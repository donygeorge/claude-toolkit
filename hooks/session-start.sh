#!/bin/bash
# SessionStart hook: Load project state once per session

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

PROJECT_NAME="${TOOLKIT_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
VERSION_FILE="${TOOLKIT_VERSION_FILE:-VERSION}"

echo "=== ${PROJECT_NAME} Session Context ==="
echo "Version: $(cat "$VERSION_FILE" 2>/dev/null || echo 'unknown')"
echo "Branch: $(git branch --show-current 2>/dev/null)"
echo "Modified files: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# Show any uncommitted changes summary
if git status --porcelain 2>/dev/null | grep -q .; then
  echo "Changed:"
  git status --porcelain | head -10
fi

# TODO: read from config — additional session-start context (e.g., commit-check alerts)
# can be added per-project

exit 0
