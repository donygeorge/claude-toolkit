#!/usr/bin/env bash
# PermissionRequest hook: Auto-approve known-safe operations
#
# Two approval modes:
#   hook_approve_and_persist() — Tool always allowed (persisted for session)
#   hook_approve()             — One-time approval (asked again next time)
#
# NEVER auto-approve: npx, curl, git commit/add/push
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"
# shellcheck source=../lib/hook-utils.sh
source "$(dirname "$0")/../lib/hook-utils.sh"

# Guard: auto-approve requires jq for reliable JSON parsing.
# Without jq, fall through to manual approval (original behavior preserved).
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input

[ -z "$HOOK_TOOL" ] && exit 0

# --- Always-Approve + Persist (Read-Only / Safe Tools) ---

case "$HOOK_TOOL" in
  Read|Glob|Grep|LS|NotebookRead)
    hook_approve_and_persist "$HOOK_TOOL"
    ;;
  Task|Skill)
    hook_approve_and_persist "$HOOK_TOOL"
    ;;
  WebSearch|WebFetch)
    hook_approve_and_persist "$HOOK_TOOL"
    ;;
esac

# --- MCP Tools: Auto-approve by configurable prefix ---
while read -r MCP_PREFIX; do
  [ -z "$MCP_PREFIX" ] && continue
  case "$HOOK_TOOL" in
    "${MCP_PREFIX}"*)
      hook_approve_and_persist "$HOOK_TOOL"
      ;;
  esac
done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_AUTO_APPROVE_MCP_TOOL_PREFIXES")

# --- Write/Edit: One-Time Approve Within Project Scope ---

if [ "$HOOK_TOOL" = "Write" ] || [ "$HOOK_TOOL" = "Edit" ]; then
  if [ -n "$HOOK_FILE_PATH" ]; then
    # Check against configurable write paths from toolkit.toml
    # Use process substitution to avoid subshell (hook_approve calls exit)
    while read -r PATTERN; do
      [ -z "$PATTERN" ] && continue
      # Use bash pattern matching (case) for glob-style patterns
      # shellcheck disable=SC2254
      case "$HOOK_FILE_PATH" in
        $PATTERN)
          hook_approve
          ;;
      esac
    done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_AUTO_APPROVE_WRITE_PATHS")

    # Hardcoded defaults (always present as safety net)
    case "$HOOK_FILE_PATH" in
      */src/*|*/app/*|*/lib/*|*/tests/*|*/test/*|*/docs/*|*/artifacts/*|*/scripts/*|\
      */.claude/*|*/CLAUDE.md|*/PROJECT_CONTEXT.md|*/Makefile|\
      */VERSION|*/requirements*.txt|*/package*.json|*/pyproject.toml|\
      */docker-compose*.yml|*/README.md|*/pytest.ini|\
      */Dockerfile|*/setup.sh|*/tsconfig*.json)
        hook_approve
        ;;
    esac
  fi
  # Outside project scope — do not auto-approve
  exit 0
fi

# --- Bash Commands ---

if [ "$HOOK_TOOL" = "Bash" ] && [ -n "$HOOK_COMMAND" ]; then

  # Extract first word of command using parameter expansion
  CMD_FIRST="${HOOK_COMMAND#"${HOOK_COMMAND%%[! ]*}"}"  # strip leading spaces
  CMD_FIRST="${CMD_FIRST%% *}"                           # take first word

  # --- Always-Approve + Persist: make and venv commands ---
  case "$CMD_FIRST" in
    make)
      hook_approve_and_persist "Bash(make:*)"
      ;;
  esac

  # .venv/bin/* commands
  case "$HOOK_COMMAND" in
    .venv/bin/*)
      hook_approve_and_persist "Bash(.venv/bin/*:*)"
      ;;
  esac

  # --- Always-Approve + Persist: Read-only git ---
  case "$HOOK_COMMAND" in
    "git diff"*|"git log"*|"git status"*|"git show"*|\
    "git branch"*|"git fetch"*|"git stash list"*)
      hook_approve_and_persist "Bash(git ${HOOK_COMMAND#git })"
      ;;
  esac

  # --- Check configurable bash commands ---
  # Use process substitution to avoid subshell (hook_approve calls exit)
  while read -r APPROVED_CMD; do
    [ -z "$APPROVED_CMD" ] && continue
    if [ "$CMD_FIRST" = "$APPROVED_CMD" ]; then
      hook_approve
    fi
  done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_AUTO_APPROVE_BASH_COMMANDS")

  # --- One-Time Approve: Safe filesystem reads ---
  case "$CMD_FIRST" in
    ls|cat|head|tail|wc|file|stat|du|df|find|tree|rg|grep|diff|\
    echo|pwd|which|type|env|printenv|uname|whoami|id|hostname|\
    basename|dirname|realpath|readlink|sort|uniq|cut|tr|tee|\
    mkdir|touch|chmod|ln)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: Build tools ---
  case "$CMD_FIRST" in
    xcrun|xcodebuild|swift|codesign|swiftlint)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: Lint/test/analysis tools ---
  case "$CMD_FIRST" in
    pytest|ruff|mypy|coverage|flake8|semgrep|gitleaks|pip-audit|\
    osv-scanner|jscpd|sqlite3|shellcheck|eslint|prettier|tsc)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: gh CLI (read operations) ---
  case "$HOOK_COMMAND" in
    "gh pr"*|"gh issue"*|"gh api"*)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: Process management ---
  case "$CMD_FIRST" in
    lsof|pgrep|pkill|kill|killall|sleep|timeout|date|open)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: Common utilities ---
  case "$CMD_FIRST" in
    bash|sh|sed|awk|cp|mv|rm)
      hook_approve
      ;;
  esac

  # --- One-Time Approve: jq (used by other hooks) ---
  case "$CMD_FIRST" in
    jq)
      hook_approve
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
  case "$HOOK_COMMAND" in
    "git commit"*|"git add"*|"git push"*)
      exit 0
      ;;
  esac
fi

# Default: do not auto-approve (let user decide)
exit 0
