#!/bin/bash
# SessionEnd hook: Clean up temporary files on session end

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Clean compact state file
COMPACT_STATE="$PROJECT_DIR/.claude/compact-state.txt"
[ -f "$COMPACT_STATE" ] && rm -f "$COMPACT_STATE"

# Auto-truncate agent memory files > 250 lines
MEMORY_DIR="$PROJECT_DIR/.claude/agent-memory"
if [ -d "$MEMORY_DIR" ]; then
  for MEM_FILE in "$MEMORY_DIR"/*/MEMORY.md; do
    [ -f "$MEM_FILE" ] || continue
    LINE_COUNT=$(wc -l < "$MEM_FILE" | tr -d ' ')
    if [ "$LINE_COUNT" -gt 250 ]; then
      { head -5 "$MEM_FILE"; echo ""; echo "<!-- Auto-truncated from $LINE_COUNT lines -->"; echo ""; tail -195 "$MEM_FILE"; } > "$MEM_FILE.tmp"
      mv "$MEM_FILE.tmp" "$MEM_FILE"
    fi
  done
fi

# Prune hook logs > 500 lines
HOOK_LOG="$PROJECT_DIR/.claude/hook-log.jsonl"
if [ -f "$HOOK_LOG" ]; then
  LINE_COUNT=$(wc -l < "$HOOK_LOG" | tr -d ' ')
  if [ "$LINE_COUNT" -gt 500 ]; then
    tail -500 "$HOOK_LOG" > "$HOOK_LOG.tmp"
    mv "$HOOK_LOG.tmp" "$HOOK_LOG"
  fi
fi

# TODO: read from config — additional cleanup paths can be added per-project
# e.g., artifacts directories with age-based cleanup

exit 0
