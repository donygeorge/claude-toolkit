#!/bin/bash
# PreToolUse hook: Block destructive commands for safe autonomous operation
# Uses JSON hookSpecificOutput with permissionDecision for structured deny/allow.
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)

# Parse tool name and command from JSON input
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
  TOOL=$(echo "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Only guard Bash tool
if [ "$TOOL" != "Bash" ]; then exit 0; fi

# Empty command: nothing to guard
[ -z "$COMMAND" ] && exit 0

# Skip if guards are disabled
if [ "${TOOLKIT_GUARD_ENABLED:-true}" = "false" ]; then exit 0; fi

# --- audit log helper ---
_audit_log() {
  local decision="$1"
  local reason="$2"
  local log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude"
  local log_file="${log_dir}/guard-audit.log"
  if [ -d "$log_dir" ]; then
    printf '%s %s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$decision" "$(basename "$0")" "$reason" >> "$log_file" 2>/dev/null || true
  fi
}

# --- deny helper ---
deny() {
  local REASON="$1"
  local CONTEXT="${2:-}"
  _audit_log "DENY" "$REASON"
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$CONTEXT" ]; then
      jq -n --arg reason "$REASON" --arg ctx "$CONTEXT" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason,additionalContext:$ctx}}'
    else
      jq -n --arg reason "$REASON" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    fi
  else
    # Escape quotes and backslashes for JSON safety when jq is unavailable
    local SAFE_REASON
    SAFE_REASON=$(printf '%s' "$REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$SAFE_REASON"
  fi
  exit 0
}

# =============================================================================
# 1. Destructive git commands
# =============================================================================
if echo "$COMMAND" | grep -qE '\bgit\s+push\b'; then
  deny "git push blocked — push manually after review" \
       "Use 'git push' outside Claude Code or ask the user to confirm."
fi

if echo "$COMMAND" | grep -qE '\bgit\s+reset\s+--hard\b'; then
  deny "git reset --hard blocked — destructive, loses uncommitted work"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+clean\s+-[a-zA-Z]*f'; then
  deny "git clean -f blocked — permanently deletes untracked files"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+checkout\s+(--\s+)?\.\s*$'; then
  deny "git checkout . blocked — discards all unstaged changes"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+restore\s+(--\s+)?\.\s*$'; then
  deny "git restore . blocked — discards all unstaged changes"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+branch\s+-D\b'; then
  deny "git branch -D blocked — force-deletes branch without merge check"
fi

if echo "$COMMAND" | grep -qE '\bgit\s+stash\s+drop\b'; then
  deny "git stash drop blocked — permanently removes stashed changes"
fi

# =============================================================================
# 2. rm -rf on critical project paths and dangerous wildcards
# =============================================================================
# Block rm -rf . or rm -rf * (extremely destructive regardless of path)
if echo "$COMMAND" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*\s+-[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*\s+-[a-zA-Z]*r|-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\b.*\s+(\.\s*$|\*)'; then
  deny "rm -rf on current directory or wildcard blocked — extremely destructive"
fi

# Critical paths for rm -rf protection (configurable via toolkit.toml, with safe defaults)
CRITICAL_PATHS="${TOOLKIT_HOOKS_GUARD_CRITICAL_PATHS:-(src|app|lib|\.claude|\.git|tests|data|scripts|config)(/|$|\s)}"
if echo "$COMMAND" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|-[a-zA-Z]*r[a-zA-Z]*\s+-[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*\s+-[a-zA-Z]*r|--recursive)\b'; then
  if echo "$COMMAND" | grep -qE -- "$CRITICAL_PATHS"; then
    deny "rm -rf on critical path blocked — would destroy essential project files" \
         "Critical paths: src/, app/, lib/, .claude/, .git/, tests/, data/, scripts/, config/"
  fi
fi

# =============================================================================
# 3. Destructive SQL commands
# =============================================================================
if echo "$COMMAND" | grep -qiE '\b(DROP\s+TABLE|TRUNCATE)\b'; then
  deny "Destructive SQL (DROP TABLE / TRUNCATE) blocked"
fi

# =============================================================================
# 4. Shared destructive patterns — checked in direct commands AND substitutions
# =============================================================================
# These patterns are dangerous in any context (direct, subshell, backtick, $())
DESTRUCTIVE_PATTERNS='\b(eval)\s|;\s*eval\s|\|\s*bash\b|\|\s*sh\b|\|\s*zsh\b'

# 4a. Direct command check
if echo "$COMMAND" | grep -qE "$DESTRUCTIVE_PATTERNS"; then
  deny "Destructive pattern blocked (eval / pipe-to-shell)" \
       "Commands containing eval or piping to bash/sh/zsh are not allowed."
fi

# 4b. Commands inside subshells $() or backticks
# Use grep -oP for nested $() if available, fall back to simple regex
# Also check the full command for destructive patterns within any $(...) context
SUBSHELL_CONTENT=$(echo "$COMMAND" | grep -oE '\$\([^)]*\)' 2>/dev/null || true)
# For nested substitutions like $(echo $(rm -rf /)), also strip $() wrappers and re-check
INNER_CONTENT=$(echo "$COMMAND" | sed 's/\$(\([^)]*\))/\1/g' 2>/dev/null || true)
# Intentionally matching literal backticks in command
# shellcheck disable=SC2016
BACKTICK_CONTENT=$(echo "$COMMAND" | grep -oE '`[^`]+`' 2>/dev/null || true)
SUBSTITUTION_CONTENT="${SUBSHELL_CONTENT}${BACKTICK_CONTENT}${INNER_CONTENT}"

if [ -n "$SUBSTITUTION_CONTENT" ]; then
  if echo "$SUBSTITUTION_CONTENT" | grep -qE "$DESTRUCTIVE_PATTERNS"; then
    deny "Destructive pattern in command substitution blocked" \
         "eval or pipe-to-shell detected inside \$() or backticks."
  fi
  # Also check for destructive git inside substitutions
  if echo "$SUBSTITUTION_CONTENT" | grep -qE '\bgit\s+(push|reset\s+--hard|clean\s+-[a-zA-Z]*f)\b'; then
    deny "Destructive git command in substitution blocked"
  fi
fi

# =============================================================================
# 5. Interpreter invocations with destructive patterns
# =============================================================================
if echo "$COMMAND" | grep -qE '\b(python[23]?)\s+-c\b'; then
  if echo "$COMMAND" | grep -qiE '(shutil\.rmtree|os\.remove|os\.unlink|subprocess.*rm)'; then
    deny "Destructive operation in python -c blocked"
  fi
fi

if echo "$COMMAND" | grep -qE '\bnode\s+-e\b'; then
  if echo "$COMMAND" | grep -qiE '(rmSync|unlinkSync|fs\.rm)'; then
    deny "Destructive operation in node -e blocked"
  fi
fi

# =============================================================================
# 6. source / dot commands from external paths
# =============================================================================
if echo "$COMMAND" | grep -qE '^\s*(source|\.)\s+(/|https?://)'; then
  deny "Sourcing external file blocked — only source local project files" \
       "source/dot with absolute or URL paths is not allowed."
fi

# =============================================================================
# 7. exec with destructive patterns
# =============================================================================
if echo "$COMMAND" | grep -qE '\bexec\s'; then
  if echo "$COMMAND" | grep -qE '\bexec\s+.*(rm|git\s+push|git\s+reset)'; then
    deny "exec with destructive command blocked"
  fi
fi

# =============================================================================
# 8. Block network access in review subagents (configurable agent names)
# =============================================================================
# Block network in review subagents (names configurable via toolkit.toml)
REVIEW_AGENTS="${TOOLKIT_HOOKS_GUARD_REVIEW_AGENTS:-reviewer|qa|security|ux|pm|docs|architect|commit-check}"
CLAUDE_SUBAGENT_TYPE="${CLAUDE_SUBAGENT_TYPE:-}"
if [ -n "$CLAUDE_SUBAGENT_TYPE" ]; then
  # shellcheck disable=SC2254
  case "$CLAUDE_SUBAGENT_TYPE" in
    $REVIEW_AGENTS)
      if echo "$COMMAND" | grep -qE '\b(curl|wget)\b'; then
        deny "Network access blocked in review subagent ($CLAUDE_SUBAGENT_TYPE)" \
             "Review agents must not make network requests. Use cached/local data only."
      fi
      ;;
  esac
fi

# All checks passed — allow the command
exit 0
