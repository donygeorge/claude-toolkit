#!/usr/bin/env bash
# TaskCompleted hook: Quality gate — blocks task completion if lint/tests fail
# Exit 0 = allow task completion
# Exit 2 = block with stderr feedback (agent must fix before completing)
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"
# shellcheck source=../lib/hook-utils.sh
source "$(dirname "$0")/../lib/hook-utils.sh"

# Consume stdin (required by hook protocol, not used here)
cat > /dev/null

# --- Gate bypass support ---
# Set TOOLKIT_SKIP_GATES=all to bypass all gates, or TOOLKIT_SKIP_GATES=lint,tests
# to skip specific gates. Useful for debugging false positives.
if [ -n "${TOOLKIT_SKIP_GATES:-}" ]; then
  if [ "$TOOLKIT_SKIP_GATES" = "all" ]; then
    hook_info "All gates bypassed via TOOLKIT_SKIP_GATES=all"
    exit 0
  fi
  hook_debug "Selective gate bypass active: TOOLKIT_SKIP_GATES=$TOOLKIT_SKIP_GATES"
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

# Collect changed files (staged + unstaged + untracked)
CHANGED_FILES=$(
  { git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
)

# Collect changed shell scripts in .claude/hooks/
CHANGED_SH=$(echo "$CHANGED_FILES" | grep -E '\.claude/hooks/.*\.sh$')

# =============================================================================
# 1. Validate shell script syntax for changed hook scripts
# =============================================================================
if [ -n "$CHANGED_SH" ]; then
  for SH_FILE in $CHANGED_SH; do
    if [ -f "$SH_FILE" ]; then
      if ! SH_SYNTAX=$(bash -n "$SH_FILE" 2>&1); then
        echo "[toolkit:task-completed-gate] ERROR: syntax error in $SH_FILE" >&2
        echo "$SH_SYNTAX" >&2
        exit 2
      fi
    fi
  done
fi

# =============================================================================
# 2. Run configurable quality gates
# =============================================================================
# Gate configuration comes from toolkit.toml [hooks.task-completed.gates]
# Each gate has: glob (file pattern), cmd (command to run), timeout (seconds)

# Helper: check if any changed files match a glob pattern
files_match_glob() {
  local PATTERN="$1"
  echo "$CHANGED_FILES" | while read -r F; do
    [ -z "$F" ] && continue
    # Use bash pattern matching
    # shellcheck disable=SC2254
    case "$F" in
      $PATTERN) echo "$F"; return 0 ;;
    esac
  done
}

# --- Lint gate ---
# Check if lint gate is bypassed
if echo ",${TOOLKIT_SKIP_GATES:-}," | grep -q ",lint,"; then
  hook_info "Lint gate bypassed via TOOLKIT_SKIP_GATES"
elif [ -n "$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_LINT_CMD" ]; then
  LINT_GLOB="$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_LINT_GLOB"
  LINT_CMD="$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_LINT_CMD"

  MATCHING_FILES=""
  while read -r F; do
    [ -z "$F" ] && continue
    [ ! -f "$F" ] && continue
    # shellcheck disable=SC2254
    case "$F" in
      $LINT_GLOB) MATCHING_FILES="$MATCHING_FILES $F" ;;
    esac
  done <<< "$CHANGED_FILES"

  if [ -n "$MATCHING_FILES" ]; then
    # Resolve command: try configured path, fall back to command name
    LINT_FIRST=$(echo "$LINT_CMD" | awk '{print $1}')
    if [ ! -x "$LINT_FIRST" ] && ! command -v "$LINT_FIRST" >/dev/null 2>&1; then
      # Try just the basename as fallback
      LINT_BASE=$(basename "$LINT_FIRST")
      if command -v "$LINT_BASE" >/dev/null 2>&1; then
        LINT_CMD="$LINT_BASE ${LINT_CMD#"$LINT_FIRST"}"
      fi
    fi

    if command -v "$(echo "$LINT_CMD" | awk '{print $1}')" >/dev/null 2>&1 || [ -x "$(echo "$LINT_CMD" | awk '{print $1}')" ]; then
      # Parse config value into array for safe execution (prevents glob expansion
      # while still splitting "ruff check --quiet" into command + arguments).
      read -ra LINT_ARGS <<< "$LINT_CMD"
      if ! LINT_OUTPUT=$(echo "$MATCHING_FILES" | xargs "${LINT_ARGS[@]}" 2>&1); then
        echo "[toolkit:task-completed-gate] ERROR: lint errors found. Fix lint issues and retry." >&2
        echo "$LINT_OUTPUT" >&2
        exit 2
      fi
    fi
  fi
fi

# --- Tests gate ---
# Check if tests gate is bypassed
if echo ",${TOOLKIT_SKIP_GATES:-}," | grep -q ",tests,"; then
  hook_info "Tests gate bypassed via TOOLKIT_SKIP_GATES"
elif [ -n "$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_TESTS_CMD" ]; then
  TESTS_GLOB="$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_TESTS_GLOB"
  TESTS_CMD="$TOOLKIT_HOOKS_TASK_COMPLETED_GATES_TESTS_CMD"
  TESTS_TIMEOUT="${TOOLKIT_HOOKS_TASK_COMPLETED_GATES_TESTS_TIMEOUT:-90}"

  HAS_MATCHING=false
  while read -r F; do
    [ -z "$F" ] && continue
    # shellcheck disable=SC2254
    case "$F" in
      $TESTS_GLOB) HAS_MATCHING=true; break ;;
    esac
  done <<< "$CHANGED_FILES"

  if [ "$HAS_MATCHING" = "true" ]; then
    # Check if the test command is available
    TESTS_FIRST=$(echo "$TESTS_CMD" | awk '{print $1}')
    CAN_RUN=false

    if [ "$TESTS_FIRST" = "make" ]; then
      # For make commands, check if Makefile has the target
      MAKE_TARGET=$(echo "$TESTS_CMD" | awk '{print $2}')
      if [ -f "Makefile" ] && grep -q "$MAKE_TARGET" Makefile 2>/dev/null; then
        CAN_RUN=true
      fi
    elif command -v "$TESTS_FIRST" >/dev/null 2>&1 || [ -x "$TESTS_FIRST" ]; then
      CAN_RUN=true
    fi

    if [ "$CAN_RUN" = "true" ]; then
      # Parse config value into array for safe execution (prevents glob expansion).
      read -ra TESTS_ARGS <<< "$TESTS_CMD"
      if ! TEST_OUTPUT=$(timeout "$TESTS_TIMEOUT" "${TESTS_ARGS[@]}" 2>&1); then
        echo "[toolkit:task-completed-gate] ERROR: tests failing." >&2
        echo "$TEST_OUTPUT" | tail -20 >&2
        exit 2
      fi
    fi
  fi
fi

# All checks passed
exit 0
