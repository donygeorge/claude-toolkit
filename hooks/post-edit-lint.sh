#!/bin/bash
# PostToolUse hook: Auto-format and lint files after edits
# Supports configurable linters per file extension via toolkit.toml

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

# Guard: Skip if jq not available
command -v jq >/dev/null 2>&1 || exit 0

# Read tool input from stdin
INPUT=$(cat)

# Extract tool name and file path using jq
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only run for Write/Edit operations
[[ "$TOOL_NAME" =~ ^(Write|Edit)$ ]] || exit 0
[ -z "$FILE_PATH" ] && exit 0
# Reject suspicious paths (traversal, absolute paths outside project)
case "$FILE_PATH" in
  *..*) exit 0 ;;
esac
[ -f "$FILE_PATH" ] || exit 0

# Navigate to project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

# Extract file extension (without dot)
EXT="${FILE_PATH##*.}"

# Build config variable names for this extension
EXT_UPPER=$(echo "$EXT" | tr '[:lower:]' '[:upper:]')
VAR_CMD="TOOLKIT_HOOKS_POST_EDIT_LINT_LINTERS_${EXT_UPPER}_CMD"
VAR_FMT="TOOLKIT_HOOKS_POST_EDIT_LINT_LINTERS_${EXT_UPPER}_FMT"
VAR_FALLBACK="TOOLKIT_HOOKS_POST_EDIT_LINT_LINTERS_${EXT_UPPER}_FALLBACK"

LINT_CMD="${!VAR_CMD:-}"
FMT_CMD="${!VAR_FMT:-}"
FALLBACK="${!VAR_FALLBACK:-}"

# No linter configured for this extension — skip silently
[ -z "$LINT_CMD" ] && [ -z "$FMT_CMD" ] && exit 0

# Resolve the linter command: if the configured path doesn't exist, try fallback
resolve_cmd() {
  local CMD="$1"
  local FB="$2"
  local CMD_FIRST
  CMD_FIRST=$(echo "$CMD" | awk '{print $1}')
  if [ -x "$CMD_FIRST" ] || command -v "$CMD_FIRST" >/dev/null 2>&1; then
    echo "$CMD"
  elif [ -n "$FB" ] && command -v "$FB" >/dev/null 2>&1; then
    # Replace the first word with the fallback
    echo "$FB ${CMD#"$CMD_FIRST"}"
  else
    echo ""
  fi
}

# Format first (if configured)
if [ -n "$FMT_CMD" ]; then
  RESOLVED_FMT=$(resolve_cmd "$FMT_CMD" "$FALLBACK")
  if [ -n "$RESOLVED_FMT" ]; then
    # Word splitting is intentional: config values like ".venv/bin/ruff format" need splitting
    # shellcheck disable=SC2086
    $RESOLVED_FMT "$FILE_PATH" 2>/dev/null
  fi
fi

# Then lint
if [ -n "$LINT_CMD" ]; then
  RESOLVED_LINT=$(resolve_cmd "$LINT_CMD" "$FALLBACK")
  if [ -n "$RESOLVED_LINT" ]; then
    # Word splitting is intentional: config values like ".venv/bin/ruff check" need splitting
    # shellcheck disable=SC2086
    LINT_OUTPUT=$($RESOLVED_LINT "$FILE_PATH" 2>&1)
    LINT_EXIT=$?

    if [ $LINT_EXIT -ne 0 ]; then
      echo ""
      echo "=== LINT ERRORS in $FILE_PATH ==="
      echo "$LINT_OUTPUT"
      echo "=== Fix: ${RESOLVED_LINT} --fix $FILE_PATH ==="
      echo ""
    fi
  fi
fi

exit 0
