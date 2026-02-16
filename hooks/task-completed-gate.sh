#!/bin/bash
# TaskCompleted hook: Quality gate — blocks task completion if lint/tests fail
# Exit 0 = allow task completion
# Exit 2 = block with stderr feedback (agent must fix before completing)

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

# Consume stdin (required by hook protocol, not used here)
cat > /dev/null

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

# Collect changed Python files (staged + unstaged + untracked)
CHANGED_PY=$(
  { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep '\.py$' | sort -u
)

# Collect changed shell scripts in .claude/hooks/
CHANGED_SH=$(
  { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | grep -E '\.claude/hooks/.*\.sh$' | sort -u
)

# =============================================================================
# 1. Validate shell script syntax for changed hook scripts
# =============================================================================
if [ -n "$CHANGED_SH" ]; then
  for SH_FILE in $CHANGED_SH; do
    if [ -f "$SH_FILE" ]; then
      if ! SH_SYNTAX=$(bash -n "$SH_FILE" 2>&1); then
        echo "Task cannot be completed: syntax error in $SH_FILE" >&2
        echo "$SH_SYNTAX" >&2
        exit 2
      fi
    fi
  done
fi

# =============================================================================
# 2. Python lint with ruff (soft-fail if ruff not available)
# =============================================================================
if [ -n "$CHANGED_PY" ]; then
  # Find ruff — prefer .venv version
  RUFF=".venv/bin/ruff"
  [ ! -x "$RUFF" ] && RUFF="ruff"

  if command -v "$RUFF" >/dev/null 2>&1; then
    # Filter to only files that actually exist
    EXISTING_PY=""
    for F in $CHANGED_PY; do
      [ -f "$F" ] && EXISTING_PY="$EXISTING_PY $F"
    done

    if [ -n "$EXISTING_PY" ]; then
      if ! LINT_OUTPUT=$(echo "$EXISTING_PY" | xargs "$RUFF" check --quiet 2>&1); then
        echo "Task cannot be completed: lint errors found. Fix lint issues and retry." >&2
        echo "$LINT_OUTPUT" >&2
        exit 2
      fi
    fi
  fi

  # ===========================================================================
  # 3. Run tests if a test command is available (90s timeout)
  # ===========================================================================
  # TODO: read from config — test command should be configurable
  if [ -f "Makefile" ] && grep -q 'test-changed' Makefile 2>/dev/null; then
    if ! TEST_OUTPUT=$(timeout 90 make test-changed 2>&1); then
      echo "Task cannot be completed: tests failing." >&2
      echo "$TEST_OUTPUT" | tail -20 >&2
      exit 2
    fi
  fi
fi

# All checks passed
exit 0
