#!/bin/bash
# PostToolUseFailure hook: Classify errors and suggest recovery strategies
# Returns structured JSON hookSpecificOutput with additionalContext for the model.
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)

# Parse tool name and error from JSON input
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  ERROR=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null)
else
  TOOL=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  ERROR=$(echo "$INPUT" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
fi

# Nothing to classify if tool or error is empty
[ -z "$TOOL" ] && exit 0
[ -z "$ERROR" ] && exit 0

CLASSIFICATION=""

case "$ERROR" in
  # --- Network / Connection ---
  *"Connection refused"*|*"ECONNREFUSED"*|*"connection reset"*)
    CLASSIFICATION="TRANSIENT ERROR ($TOOL): Connection failure — server may not be running. Recovery: Check if server is started, retry after brief wait."
    ;;
  *"timeout"*|*"ETIMEDOUT"*|*"timed out"*)
    CLASSIFICATION="TRANSIENT ERROR ($TOOL): Operation timed out. Recovery: Retry with longer timeout."
    ;;

  # --- File system ---
  *"ENOENT"*|*"No such file"*|*"not found"*|*"FileNotFoundError"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): File or resource not found. Recovery: Verify the path exists."
    ;;
  *"Permission denied"*|*"EACCES"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Permission denied. Recovery: Check file permissions."
    ;;

  # --- Python syntax / imports ---
  *"syntax error"*|*"SyntaxError"*|*"IndentationError"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Code syntax error. Recovery: Fix the syntax issue."
    ;;
  *"ModuleNotFoundError"*|*"ImportError"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Missing Python module. Recovery: Install dependencies or check virtual environment activation."
    ;;

  # --- Port / process ---
  *"port"*"in use"*|*"EADDRINUSE"*)
    CLASSIFICATION="TRANSIENT ERROR ($TOOL): Port already in use. Recovery: Kill the process using that port."
    ;;

  # --- Database ---
  *"database is locked"*|*"SQLITE_BUSY"*)
    CLASSIFICATION="TRANSIENT ERROR ($TOOL): Database locked. Recovery: Close other database connections, retry."
    ;;

  # --- Linting ---
  *"ruff"*|*"Ruff"*"error"*|*"eslint"*|*"ESLint"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Linting error. Recovery: Fix the lint issues or run the formatter."
    ;;

  # --- Type checking ---
  *"mypy"*"error"*|*"Incompatible type"*|*"has no attribute"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Type checking error. Recovery: Fix type annotations."
    ;;

  # --- Xcode / iOS build ---
  *"xcodebuild"*"error"*|*"Build Failed"*|*"Undefined symbol"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Xcode build error. Recovery: Check build errors for details."
    ;;

  # --- iOS Simulator ---
  *"simctl"*"error"*|*"Unable to boot"*|*"Simulator"*"not"*"found"*)
    CLASSIFICATION="TRANSIENT ERROR ($TOOL): iOS simulator error. Recovery: Try shutting down all simulators then retry."
    ;;

  # --- Playwright ---
  *"browserType.launch"*|*"Browser"*"not"*"installed"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): Playwright browser not installed. Recovery: Run 'npx playwright install chromium'."
    ;;

  # --- npm ---
  *"npm ERR"*|*"npm error"*)
    CLASSIFICATION="PERMANENT ERROR ($TOOL): npm error. Recovery: Check package.json and retry."
    ;;

  # --- Catch-all ---
  *)
    CLASSIFICATION="UNCLASSIFIED ERROR ($TOOL): $ERROR"
    ;;
esac

# Output structured JSON for the model
if command -v jq >/dev/null 2>&1; then
  jq -n --arg classification "$CLASSIFICATION" \
    '{hookSpecificOutput:{hookEventName:"PostToolUseFailure",additionalContext:$classification}}'
else
  # Escape special characters for JSON (backslashes, quotes, tabs, newlines, carriage returns)
  SAFE_CLASS=$(printf '%s' "$CLASSIFICATION" | tr '\n\r' '  ' | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"%s"}}\n' "$SAFE_CLASS"
fi

exit 0
