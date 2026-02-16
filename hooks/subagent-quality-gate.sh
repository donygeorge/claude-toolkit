#!/bin/bash
# SubagentStop hook: Validate agent output quality before accepting results
# Checks that agents produced meaningful evidence appropriate to their role.
# In deep/thorough mode: critical failures block (exit 2). In smoke mode: warnings only.

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Parse agent type and output from JSON input
if command -v jq >/dev/null 2>&1; then
  AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_name // empty' 2>/dev/null)
  AGENT_OUTPUT=$(echo "$INPUT" | jq -r '.output // empty' 2>/dev/null)
  AGENT_MODE=$(echo "$INPUT" | jq -r '.mode // "standard"' 2>/dev/null)
else
  AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  AGENT_OUTPUT=$(echo "$INPUT" | grep -o '"output"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  AGENT_MODE="standard"
fi

# Nothing to validate if no agent type
[ -z "$AGENT_TYPE" ] && exit 0
[ -z "$AGENT_OUTPUT" ] && exit 0

# Determine if we should block or warn
IS_STRICT=false
case "$AGENT_MODE" in
  deep|thorough) IS_STRICT=true ;;
esac

WARNINGS=""
FAILURES=""

# --- Helper: add a warning ---
warn() {
  WARNINGS="${WARNINGS}WARNING ($AGENT_TYPE): $1\n"
}

# --- Helper: add a failure ---
fail() {
  FAILURES="${FAILURES}FAILURE ($AGENT_TYPE): $1\n"
}

# =============================================================================
# Agent-specific validation
# TODO: read from config — agent names and validation rules should be configurable
# =============================================================================
case "$AGENT_TYPE" in
  reviewer)
    # Must have file:line evidence for high/critical findings
    if echo "$AGENT_OUTPUT" | grep -qiE '(high|critical|severity)'; then
      if ! echo "$AGENT_OUTPUT" | grep -qE '[a-zA-Z_/]+\.(py|swift|sh|js|ts):[0-9]+'; then
        fail "Reviewer reported high/critical findings but no file:line evidence found."
      fi
    fi
    # Must reference actual project files
    if ! echo "$AGENT_OUTPUT" | grep -qE '(src/|app/|lib/|tests/|\.claude/|scripts/)'; then
      warn "Reviewer output does not reference any project file paths."
    fi
    ;;

  qa)
    # Must show evidence of test execution
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(pytest|make test|test.*pass|test.*fail|PASSED|FAILED|errors?)'; then
      fail "QA agent did not show evidence of test execution."
    fi
    ;;

  security)
    # Must have run at least one security tool
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(gitleaks|semgrep|pip-audit|osv-scanner|bandit|safety|trivy)'; then
      fail "Security agent did not reference any security scanning tool."
    fi
    ;;

  architect)
    # Must reference actual code files
    if ! echo "$AGENT_OUTPUT" | grep -qE '(src/|app/|lib/|tests/|\.py|\.swift|\.ts|\.js)'; then
      fail "Architect output does not reference actual project code files."
    fi
    # Should mention architectural concepts
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(pattern|coupling|dependency|layer|separation|modular|architecture)'; then
      warn "Architect output lacks architectural analysis vocabulary."
    fi
    ;;

  docs)
    # Must reference documentation files or identify gaps
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(\.md|documentation|docstring|README|CLAUDE\.md|docs/)'; then
      warn "Docs agent did not reference any documentation files or identify gaps."
    fi
    ;;

  ux)
    # Must mention accessibility or UI concerns
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(accessibility|VoiceOver|WCAG|dark.?mode|contrast|font.?size|a11y)'; then
      warn "UX agent did not mention accessibility or UI standards."
    fi
    ;;

  pm)
    # Must mention user-facing concerns
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(user|workflow|feature|experience|requirement|story|persona)'; then
      warn "PM agent did not mention user-facing concerns."
    fi
    ;;

  plan)
    # Must produce milestones
    if ! echo "$AGENT_OUTPUT" | grep -qiE '(milestone|M[0-9]|phase|deliverable|exit.?criteria)'; then
      fail "Plan agent output missing milestones or deliverables."
    fi
    ;;

  commit-check)
    # Must produce JSON output
    if ! echo "$AGENT_OUTPUT" | grep -qE '^\s*\{'; then
      fail "Commit-check agent did not produce JSON output."
    fi
    ;;

  general-purpose)
    # No specific validation for general-purpose agents
    ;;

  *)
    # Unknown agent type — warn but don't block
    warn "Unknown agent type: $AGENT_TYPE — no validation rules defined."
    ;;
esac

# =============================================================================
# Log to hook-log.jsonl
# =============================================================================
LOG_FILE="$PROJECT_DIR/.claude/hook-log.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HAS_WARNINGS="false"
HAS_FAILURES="false"
[ -n "$WARNINGS" ] && HAS_WARNINGS="true"
[ -n "$FAILURES" ] && HAS_FAILURES="true"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ts "$TIMESTAMP" --arg agent "$AGENT_TYPE" --arg mode "$AGENT_MODE" \
    --arg warnings "$HAS_WARNINGS" --arg failures "$HAS_FAILURES" \
    '{timestamp:$ts,hook:"subagent-quality-gate",agent:$agent,mode:$mode,has_warnings:($warnings=="true"),has_failures:($failures=="true")}' \
    >> "$LOG_FILE" 2>/dev/null
fi

# =============================================================================
# Output results
# =============================================================================
if [ -n "$FAILURES" ] && [ "$IS_STRICT" = "true" ]; then
  # In deep/thorough mode, critical failures block
  printf '%b' "$FAILURES" >&2
  if [ -n "$WARNINGS" ]; then
    printf '%b' "$WARNINGS" >&2
  fi
  exit 2
fi

# Warnings and non-strict failures: emit as advisory context
ALL_ISSUES="${FAILURES}${WARNINGS}"
if [ -n "$ALL_ISSUES" ]; then
  # Emit as advisory (does not block)
  SAFE_ISSUES=$(printf '%b' "$ALL_ISSUES" | sed 's/"/\\"/g' | tr '\n' ' ')
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg issues "$SAFE_ISSUES" \
      '{hookSpecificOutput:{hookEventName:"SubagentStop",additionalContext:$issues}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":"%s"}}\n' "$SAFE_ISSUES"
  fi
fi

exit 0
