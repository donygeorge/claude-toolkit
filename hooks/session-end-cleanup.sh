#!/usr/bin/env bash
# SessionEnd hook: Clean up temporary files on session end
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

_atomic_write() {
  # Write content (from stdin) to $1 atomically via temp file + mv
  local target="$1"
  local tmp="${target}.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$target"
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Clean compact state file
COMPACT_STATE="$PROJECT_DIR/.claude/compact-state.txt"
[ -f "$COMPACT_STATE" ] && rm -f "$COMPACT_STATE"

# Auto-truncate agent memory files (configurable max lines)
MAX_MEMORY_LINES="$TOOLKIT_HOOKS_SESSION_END_AGENT_MEMORY_MAX_LINES"
MEMORY_DIR="$PROJECT_DIR/.claude/agent-memory"
if [ -d "$MEMORY_DIR" ]; then
  for MEM_FILE in "$MEMORY_DIR"/*/MEMORY.md; do
    [ -f "$MEM_FILE" ] || continue
    LINE_COUNT=$(wc -l < "$MEM_FILE" | tr -d ' ')
    if [ "$LINE_COUNT" -gt "$MAX_MEMORY_LINES" ]; then
      TAIL_LINES=$((MAX_MEMORY_LINES - 55))
      # Guard against negative/zero TAIL_LINES when MAX_MEMORY_LINES is small
      [ "$TAIL_LINES" -lt 10 ] && TAIL_LINES=10
      { head -5 "$MEM_FILE"; echo ""; echo "<!-- Auto-truncated from $LINE_COUNT lines -->"; echo ""; tail -"$TAIL_LINES" "$MEM_FILE"; } | _atomic_write "$MEM_FILE"
    fi
  done
fi

# Prune hook logs (configurable max lines)
MAX_LOG_LINES="$TOOLKIT_HOOKS_SESSION_END_HOOK_LOG_MAX_LINES"
HOOK_LOG="$PROJECT_DIR/.claude/hook-log.jsonl"
if [ -f "$HOOK_LOG" ]; then
  LINE_COUNT=$(wc -l < "$HOOK_LOG" | tr -d ' ')
  if [ "$LINE_COUNT" -gt "$MAX_LOG_LINES" ]; then
    tail -"$MAX_LOG_LINES" "$HOOK_LOG" | _atomic_write "$HOOK_LOG"
  fi
fi

exit 0
