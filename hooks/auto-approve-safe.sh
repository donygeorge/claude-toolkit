#!/bin/bash
# PermissionRequest hook: Auto-approve known-safe operations
#
# Two approval modes:
#   approve_and_persist() — Tool always allowed (persisted for session)
#   approve()            — One-time approval (asked again next time)
#
# NEVER auto-approve: npx, curl, git commit/add/push

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)

# Parse JSON input — bail gracefully if jq missing
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  exit 0
fi

[ -z "$TOOL" ] && exit 0

# --- Helper Functions ---

approve() {
  cat <<'APPROVE_EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
APPROVE_EOF
  exit 0
}

approve_and_persist() {
  local TOOL_NAME="$1"
  jq -n --arg tool "$TOOL_NAME" \
    '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedPermissions:[{type:"toolAlwaysAllow",tool:$tool}]}}}'
  exit 0
}

# --- Always-Approve + Persist (Read-Only / Safe Tools) ---

case "$TOOL" in
  Read|Glob|Grep|LS|NotebookRead)
    approve_and_persist "$TOOL"
    ;;
  Task|Skill)
    approve_and_persist "$TOOL"
    ;;
  WebSearch|WebFetch)
    approve_and_persist "$TOOL"
    ;;
  # MCP tools: codex, playwright, context7
  mcp__codex__codex|mcp__codex__codex-reply)
    approve_and_persist "$TOOL"
    ;;
  mcp__plugin_playwright_playwright__*)
    approve_and_persist "$TOOL"
    ;;
  mcp__plugin_context7_context7__*)
    approve_and_persist "$TOOL"
    ;;
esac

# --- Write/Edit: One-Time Approve Within Project Scope ---

if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
  if [ -n "$FILE_PATH" ]; then
    # Check against configurable write paths from toolkit.toml
    toolkit_iterate_array "$TOOLKIT_HOOKS_AUTO_APPROVE_WRITE_PATHS" | while read -r PATTERN; do
      [ -z "$PATTERN" ] && continue
      # Use bash pattern matching (case) for glob-style patterns
      # shellcheck disable=SC2254
      case "$FILE_PATH" in
        $PATTERN)
          approve
          ;;
      esac
    done

    # Hardcoded defaults (always present as safety net)
    case "$FILE_PATH" in
      */src/*|*/app/*|*/lib/*|*/tests/*|*/test/*|*/docs/*|*/artifacts/*|*/scripts/*|\
      */.claude/*|*/CLAUDE.md|*/PROJECT_CONTEXT.md|*/Makefile|\
      */VERSION|*/requirements*.txt|*/package*.json|*/pyproject.toml|\
      */docker-compose*.yml|*/README.md|*/pytest.ini|\
      */Dockerfile|*/setup.sh|*/tsconfig*.json)
        approve
        ;;
    esac
  fi
  # Outside project scope — do not auto-approve
  exit 0
fi

# --- Bash Commands ---

if [ "$TOOL" = "Bash" ] && [ -n "$COMMAND" ]; then

  # Extract first word of command (handles leading whitespace)
  CMD_FIRST=$(echo "$COMMAND" | awk '{print $1}')

  # --- Always-Approve + Persist: make and venv commands ---
  case "$CMD_FIRST" in
    make)
      approve_and_persist "Bash(make:*)"
      ;;
  esac

  # .venv/bin/* commands
  case "$COMMAND" in
    .venv/bin/*)
      approve_and_persist "Bash(.venv/bin/*:*)"
      ;;
  esac

  # --- Always-Approve + Persist: Read-only git ---
  case "$COMMAND" in
    "git diff"*|"git log"*|"git status"*|"git show"*|\
    "git branch"*|"git fetch"*|"git stash list"*)
      approve_and_persist "Bash(git ${COMMAND#git })"
      ;;
  esac

  # --- Check configurable bash commands ---
  toolkit_iterate_array "$TOOLKIT_HOOKS_AUTO_APPROVE_BASH_COMMANDS" | while read -r APPROVED_CMD; do
    [ -z "$APPROVED_CMD" ] && continue
    if [ "$CMD_FIRST" = "$APPROVED_CMD" ]; then
      approve
    fi
  done

  # --- One-Time Approve: Safe filesystem reads ---
  case "$CMD_FIRST" in
    ls|cat|head|tail|wc|file|stat|du|df|find|tree|rg|grep|diff|\
    echo|pwd|which|type|env|printenv|uname|whoami|id|hostname|\
    basename|dirname|realpath|readlink|sort|uniq|cut|tr|tee|\
    mkdir|touch|chmod|ln)
      approve
      ;;
  esac

  # --- One-Time Approve: Build tools ---
  case "$CMD_FIRST" in
    xcrun|xcodebuild|swift|codesign|swiftlint)
      approve
      ;;
  esac

  # --- One-Time Approve: Lint/test/analysis tools ---
  case "$CMD_FIRST" in
    pytest|ruff|mypy|coverage|flake8|semgrep|gitleaks|pip-audit|\
    osv-scanner|jscpd|sqlite3|shellcheck|eslint|prettier|tsc)
      approve
      ;;
  esac

  # --- One-Time Approve: gh CLI (read operations) ---
  case "$COMMAND" in
    "gh pr"*|"gh issue"*|"gh api"*)
      approve
      ;;
  esac

  # --- One-Time Approve: Process management ---
  case "$CMD_FIRST" in
    lsof|pgrep|pkill|kill|killall|sleep|timeout|date|open)
      approve
      ;;
  esac

  # --- One-Time Approve: Common utilities ---
  case "$CMD_FIRST" in
    bash|sh|sed|awk|cp|mv|rm)
      approve
      ;;
  esac

  # --- One-Time Approve: jq (used by other hooks) ---
  case "$CMD_FIRST" in
    jq)
      approve
      ;;
  esac

  # --- BLOCK: npx (security risk) ---
  case "$CMD_FIRST" in
    npx)
      exit 0
      ;;
  esac

  # --- BLOCK: curl (defense-in-depth, review needed) ---
  case "$CMD_FIRST" in
    curl)
      exit 0
      ;;
  esac

  # --- BLOCK: git commit/add/push (let normal flow handle) ---
  case "$COMMAND" in
    "git commit"*|"git add"*|"git push"*)
      exit 0
      ;;
  esac
fi

# Default: do not auto-approve (let user decide)
exit 0
