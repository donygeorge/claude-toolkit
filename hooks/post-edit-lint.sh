#!/bin/bash
# PostToolUse hook: Auto-format and lint Python files after edits

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

# Guard: Skip if jq not available
command -v jq >/dev/null 2>&1 || exit 0

# Read tool input from stdin
INPUT=$(cat)

# Extract tool name and file path using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only run for Write/Edit on Python files
if [[ "$TOOL_NAME" =~ ^(Write|Edit)$ ]] && [[ "$FILE_PATH" == *.py ]]; then
  # Navigate to project root
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
  cd "$PROJECT_DIR" || exit 0

  # Check if file exists
  if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
  fi

  # Use .venv ruff if available, otherwise fall back to global
  RUFF=".venv/bin/ruff"
  [ ! -x "$RUFF" ] && RUFF="ruff"

  # Format with ruff (suppress output unless there's an error)
  "$RUFF" format "$FILE_PATH" 2>/dev/null

  # Lint with clear error reporting
  LINT_OUTPUT=$("$RUFF" check "$FILE_PATH" 2>&1)
  LINT_EXIT=$?

  if [ $LINT_EXIT -ne 0 ]; then
    echo ""
    echo "=== LINT ERRORS in $FILE_PATH ==="
    echo "$LINT_OUTPUT"
    echo "=== Fix: ruff check --fix $FILE_PATH ==="
    echo ""
  fi
fi

exit 0
