#!/bin/bash
# Setup hook: Validate development environment on first session start
# NOTE: No set -e — hooks should degrade gracefully

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

WARNINGS=""

# ---------------------------------------------------------------------------
# 1. Check Python version (configurable minimum)
# ---------------------------------------------------------------------------
REQUIRED_MAJOR=$(echo "$TOOLKIT_HOOKS_SETUP_PYTHON_MIN_VERSION" | cut -d. -f1)
REQUIRED_MINOR=$(echo "$TOOLKIT_HOOKS_SETUP_PYTHON_MIN_VERSION" | cut -d. -f2)

PYTHON_VERSION=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')
if [ -n "$PYTHON_VERSION" ]; then
  MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
  MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
  if [ "$MAJOR" -lt "$REQUIRED_MAJOR" ] || { [ "$MAJOR" -eq "$REQUIRED_MAJOR" ] && [ "$MINOR" -lt "$REQUIRED_MINOR" ]; }; then
    WARNINGS="${WARNINGS}- Python ${TOOLKIT_HOOKS_SETUP_PYTHON_MIN_VERSION}+ required, found ${PYTHON_VERSION}\n"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Check .venv
# ---------------------------------------------------------------------------
if [ ! -d ".venv" ]; then
  WARNINGS="${WARNINGS}- Virtual environment not found. Run: python3 -m venv .venv && pip install -r requirements.txt\n"
elif [ ! -f ".venv/bin/python" ]; then
  WARNINGS="${WARNINGS}- Virtual environment broken. Recreate with: python3 -m venv .venv\n"
fi

# ---------------------------------------------------------------------------
# 3. Check required tools (from config)
# ---------------------------------------------------------------------------
toolkit_iterate_array "$TOOLKIT_HOOKS_SETUP_REQUIRED_TOOLS" | while read -r TOOL; do
  [ -z "$TOOL" ] && continue
  if ! command -v "$TOOL" >/dev/null 2>&1 && [ ! -x ".venv/bin/$TOOL" ]; then
    # Can't modify WARNINGS from subshell, so echo directly
    echo "WARNING: Missing required tool: ${TOOL}" >&2
  fi
done

# ---------------------------------------------------------------------------
# 4. Check optional tools (from config, informational only)
# ---------------------------------------------------------------------------
toolkit_iterate_array "$TOOLKIT_HOOKS_SETUP_OPTIONAL_TOOLS" | while read -r TOOL; do
  [ -z "$TOOL" ] && continue
  if ! command -v "$TOOL" >/dev/null 2>&1 && [ ! -x ".venv/bin/$TOOL" ]; then
    echo "INFO: Optional tool not found: ${TOOL}" >&2
  fi
done

# ---------------------------------------------------------------------------
# 5. Check security tools (from config)
# ---------------------------------------------------------------------------
toolkit_iterate_array "$TOOLKIT_HOOKS_SETUP_SECURITY_TOOLS" | while read -r TOOL; do
  [ -z "$TOOL" ] && continue
  if ! command -v "$TOOL" >/dev/null 2>&1; then
    echo "INFO: Security tool not found: ${TOOL}" >&2
  fi
done

if [ -n "$WARNINGS" ]; then
  echo "=== Setup Check ==="
  printf '%b' "$WARNINGS"
  echo "Fix these before development."
else
  echo "=== Setup Check: All OK ==="
fi

exit 0
