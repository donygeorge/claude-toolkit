#!/bin/bash
# PreCompact hook: Output working state context that survives compaction
# Hook output is injected into conversation after compact completes
# Also saves state to compact-state.txt for post-compact-reinject.sh

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$PROJECT_DIR" || exit 0

PROJECT_NAME="${TOOLKIT_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# TODO: read from config — source directories for recent file scanning
# Default scans src/ and app/ for recently modified files
SOURCE_DIRS="src app lib"

# Get recently modified project files (last 30 min)
RECENT_FILES=""
for DIR in $SOURCE_DIRS; do
  if [ -d "$DIR" ]; then
    DIR_FILES=$(find "$DIR" -type f \( -name "*.py" -o -name "*.swift" -o -name "*.ts" -o -name "*.js" \) -mmin -30 2>/dev/null | head -5)
    if [ -n "$DIR_FILES" ]; then
      RECENT_FILES="${RECENT_FILES}${DIR_FILES}
"
    fi
  fi
done

# Get uncommitted changes
GIT_STATUS=$(git status --porcelain 2>/dev/null | head -10)

# Check for active orchestration state (implement/solve/refine)
ACTIVE_STATE=""

if [ -d "artifacts/execute" ]; then
  LATEST_PLAN=$(ls -t artifacts/execute/*/plan_state.json 2>/dev/null | head -1)
  if [ -n "$LATEST_PLAN" ] && command -v jq >/dev/null 2>&1; then
    PLAN_NAME=$(jq -r '.plan_name // empty' "$LATEST_PLAN" 2>/dev/null)
    PLAN_MS=$(jq -r '.current_milestone // empty' "$LATEST_PLAN" 2>/dev/null)
    if [ -n "$PLAN_NAME" ]; then
      ACTIVE_STATE="Active plan: $LATEST_PLAN (plan: $PLAN_NAME, milestone: $PLAN_MS)"
    fi
  fi
fi

if [ -d "artifacts/refine" ]; then
  LATEST_REFINE=$(ls -t artifacts/refine/*/*/state.json 2>/dev/null | head -1)
  if [ -n "$LATEST_REFINE" ] && command -v jq >/dev/null 2>&1; then
    REFINE_SCOPE=$(jq -r '.scope // empty' "$LATEST_REFINE" 2>/dev/null)
    REFINE_ITER=$(jq -r '.current_iteration // empty' "$LATEST_REFINE" 2>/dev/null)
    if [ -n "$REFINE_SCOPE" ]; then
      ACTIVE_STATE="${ACTIVE_STATE:+$ACTIVE_STATE | }Active refine: $LATEST_REFINE (scope: $REFINE_SCOPE, iteration: $REFINE_ITER)"
    fi
  fi
fi

# Get current branch
BRANCH=$(git branch --show-current 2>/dev/null)

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
  echo "- $ACTIVE_STATE"
fi

# TODO: read from config — critical rules should be injected from config
cat << 'RULES'

**Post-compact actions:**
1. Check todo list for current task state
2. If orchestration state exists above, read the state file to restore context
3. Continue from last checkpoint
RULES
}

# Output to stdout (injected into conversation)
generate_output

# Save state for post-compact-reinject.sh
STATE_FILE="$PROJECT_DIR/.claude/compact-state.txt"
generate_output > "$STATE_FILE" 2>/dev/null
