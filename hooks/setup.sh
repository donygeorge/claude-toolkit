#!/bin/bash
# Setup hook: Validate development environment on first session start
# NOTE: No set -e — hooks should degrade gracefully

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

WARNINGS=""

# TODO: read from config — required tools and versions should be configurable
# Currently checks for a common Python + jq setup

# Check Python 3.11+
PYTHON_VERSION=$(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')
if [ -n "$PYTHON_VERSION" ]; then
  MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
  MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
  if [ "$MAJOR" -lt 3 ] || { [ "$MAJOR" -eq 3 ] && [ "$MINOR" -lt 11 ]; }; then
    WARNINGS="${WARNINGS}- Python 3.11+ required, found ${PYTHON_VERSION}\n"
  fi
fi

# Check .venv
if [ ! -d ".venv" ]; then
  WARNINGS="${WARNINGS}- Virtual environment not found. Run: python3 -m venv .venv && pip install -r requirements.txt\n"
elif [ ! -f ".venv/bin/python" ]; then
  WARNINGS="${WARNINGS}- Virtual environment broken. Recreate with: python3 -m venv .venv\n"
fi

# Check required tools: ruff, jq
for TOOL in ruff jq; do
  if ! command -v "$TOOL" >/dev/null 2>&1 && [ ! -x ".venv/bin/$TOOL" ]; then
    WARNINGS="${WARNINGS}- Missing tool: ${TOOL}\n"
  fi
done

# TODO: read from config — additional tool checks should be configurable
# Projects can add iOS tools (axe, xcodebuild), security tools (gitleaks, semgrep), etc.

if [ -n "$WARNINGS" ]; then
  echo "=== Setup Check ==="
  printf '%b' "$WARNINGS"
  echo "Fix these before development."
else
  echo "=== Setup Check: All OK ==="
fi

exit 0
