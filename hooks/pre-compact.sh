#!/usr/bin/env bash
# PreCompact hook: Output working state context that survives compaction
# Hook output is injected into conversation after compact completes
# Also saves state to compact-state.txt for post-compact-reinject.sh
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

PROJECT_NAME="$TOOLKIT_PROJECT_NAME"

# Get source directories and extensions from config
# Use mktemp for safe temp files with cleanup trap
TMPFILE_RECENT=$(mktemp "${TMPDIR:-/tmp}/toolkit_recent.XXXXXX") || exit 0
TMPFILE_STATE=$(mktemp "${TMPDIR:-/tmp}/toolkit_state.XXXXXX") || { rm -f "$TMPFILE_RECENT"; exit 0; }
TMPFILE_RULES=$(mktemp "${TMPDIR:-/tmp}/toolkit_rules.XXXXXX") || { rm -f "$TMPFILE_RECENT" "$TMPFILE_STATE"; exit 0; }
trap 'rm -f "$TMPFILE_RECENT" "$TMPFILE_STATE" "$TMPFILE_RULES"' EXIT

RECENT_FILES=""
while read -r DIR; do
  [ -z "$DIR" ] && continue
  if [ -d "$DIR" ]; then
    # Build find arguments array from configured extensions
    FIND_ARGS=()
    FIRST=true
    while read -r EXTGLOB; do
      [ -z "$EXTGLOB" ] && continue
      if [ "$FIRST" = true ]; then
        FIND_ARGS+=(-name "$EXTGLOB")
        FIRST=false
      else
        FIND_ARGS+=(-o -name "$EXTGLOB")
      fi
    done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_COMPACT_SOURCE_EXTENSIONS")
    if [ ${#FIND_ARGS[@]} -gt 0 ]; then
      find "$DIR" -type f \( "${FIND_ARGS[@]}" \) -mmin -30 2>/dev/null | head -5
    fi
  fi
done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_COMPACT_SOURCE_DIRS") > "$TMPFILE_RECENT" 2>/dev/null
RECENT_FILES=$(cat "$TMPFILE_RECENT" 2>/dev/null)

# Get uncommitted changes
GIT_STATUS=$(git status --porcelain 2>/dev/null | head -10)

# Check for active orchestration state (implement/solve/refine)
ACTIVE_STATE=""

while read -r STATE_DIR; do
  [ -z "$STATE_DIR" ] && continue
  if [ -d "$STATE_DIR/execute" ]; then
    LATEST_PLAN=$(ls -t "$STATE_DIR"/execute/*/plan_state.json 2>/dev/null | head -1)
    if [ -n "$LATEST_PLAN" ] && command -v jq >/dev/null 2>&1; then
      PLAN_NAME=$(jq -r '.plan_name // empty' "$LATEST_PLAN" 2>/dev/null)
      PLAN_MS=$(jq -r '.current_milestone // empty' "$LATEST_PLAN" 2>/dev/null)
      if [ -n "$PLAN_NAME" ]; then
        echo "Active plan: $LATEST_PLAN (plan: $PLAN_NAME, milestone: $PLAN_MS)"
      fi
    fi
  fi
  if [ -d "$STATE_DIR/refine" ]; then
    LATEST_REFINE=$(ls -t "$STATE_DIR"/refine/*/*/state.json 2>/dev/null | head -1)
    if [ -n "$LATEST_REFINE" ] && command -v jq >/dev/null 2>&1; then
      REFINE_SCOPE=$(jq -r '.scope // empty' "$LATEST_REFINE" 2>/dev/null)
      REFINE_ITER=$(jq -r '.current_iteration // empty' "$LATEST_REFINE" 2>/dev/null)
      if [ -n "$REFINE_SCOPE" ]; then
        echo "Active refine: $LATEST_REFINE (scope: $REFINE_SCOPE, iteration: $REFINE_ITER)"
      fi
    fi
  fi
done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_COMPACT_STATE_DIRS") > "$TMPFILE_STATE" 2>/dev/null
ACTIVE_STATE=$(cat "$TMPFILE_STATE" 2>/dev/null)

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null)

# Build critical rules from config
CRITICAL_RULES=""
while read -r RULE; do
  [ -z "$RULE" ] && continue
  echo "- $RULE"
done < <(toolkit_iterate_array "$TOOLKIT_HOOKS_SUBAGENT_CONTEXT_CRITICAL_RULES") > "$TMPFILE_RULES" 2>/dev/null
CRITICAL_RULES=$(cat "$TMPFILE_RULES" 2>/dev/null)

# Generate output function (used for both stdout and state file)
generate_output() {
cat << EOF
## Working Context (Pre-Compact Snapshot)

**Project:** ${PROJECT_NAME}
**Branch:** ${BRANCH:-"(unknown)"}

**Recently modified files:**
${RECENT_FILES:-"(none in last 30 min)"}

**Uncommitted changes:**
\`\`\`
${GIT_STATUS:-"(clean)"}
\`\`\`
EOF

# Include active orchestration state
if [ -n "$ACTIVE_STATE" ]; then
  echo ""
  echo "**Active orchestration state:**"
  echo "$ACTIVE_STATE"
fi

# Include critical rules if configured
if [ -n "$CRITICAL_RULES" ]; then
  echo ""
  echo "**Critical rules:**"
  echo "$CRITICAL_RULES"
fi

cat << 'RULES'

**Post-compact actions:**
1. Check todo list for current task state
2. If orchestration state exists above, read the state file to restore context
3. Continue from last checkpoint
RULES
}

# Output to stdout (injected into conversation)
generate_output

# Save state for post-compact-reinject.sh (atomic write)
STATE_FILE="$PROJECT_DIR/.claude/compact-state.txt"
STATE_TMP="${STATE_FILE}.tmp.$$"
generate_output > "$STATE_TMP" 2>/dev/null
mv "$STATE_TMP" "$STATE_FILE" 2>/dev/null || true
