#!/usr/bin/env bash
# Shared hook utilities — sourced by hooks that need common helpers.
# Unlike _config.sh (which every hook sources), this is opt-in.
#
# Provides:
#   hook_read_input   — reads stdin, extracts tool_name/command/file_path via jq
#   hook_deny         — structured deny response with audit logging
#   hook_approve      — structured approve response
#   hook_approve_and_persist — approve and persist permission
#   _audit_log        — audit log helper
#   _atomic_write     — atomic file write (stdin -> target)
#   hook_warn, hook_error, hook_info — standardized logging to stderr
#
# Usage:
#   source "$(dirname "$0")/../lib/hook-utils.sh"

# --- JSON input parsing ---
# Reads stdin into HOOK_INPUT and extracts common fields.
# Sets: HOOK_INPUT, HOOK_TOOL, HOOK_COMMAND, HOOK_FILE_PATH
hook_read_input() {
  HOOK_INPUT=$(cat)
  if command -v jq >/dev/null 2>&1; then
    # shellcheck disable=SC2034  # Variables used by sourcing hooks
    HOOK_TOOL=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    # shellcheck disable=SC2034
    HOOK_COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    # shellcheck disable=SC2034
    HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  else
    # Fallback regex parsing for when jq is unavailable
    # shellcheck disable=SC2034  # Variables used by sourcing hooks
    HOOK_TOOL=$(echo "$HOOK_INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    # shellcheck disable=SC2034
    HOOK_COMMAND=$(echo "$HOOK_INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    # shellcheck disable=SC2034
    HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  fi
}

# --- Structured deny response ---
# Outputs JSON deny decision to stdout, logs to audit log, then exits 0.
# Args: $1 = reason, $2 = additional context (optional)
hook_deny() {
  local reason="$1"
  local context="${2:-}"
  _audit_log "DENY" "$reason"
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$context" ]; then
      jq -n --arg r "$reason" --arg c "$context" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r,additionalContext:$c}}'
    else
      jq -n --arg r "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    fi
  else
    # Escape quotes and backslashes for JSON safety when jq is unavailable
    local safe_reason
    safe_reason=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$safe_reason"
  fi
  exit 0
}

# --- Structured approve response ---
# Outputs JSON approve decision to stdout, then exits 0.
hook_approve() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
  exit 0
}

# --- Approve and persist permission ---
# Outputs JSON approve + persist decision, then exits 0.
# Args: $1 = tool name to persist
hook_approve_and_persist() {
  local tool_name="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg tool "$tool_name" \
      '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedPermissions:[{type:"toolAlwaysAllow",tool:$tool}]}}}'
  else
    # Escape quotes for JSON safety when jq is unavailable
    local safe_tool
    safe_tool=$(printf '%s' "$tool_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"toolAlwaysAllow","tool":"%s"}]}}}\n' "$safe_tool"
  fi
  exit 0
}

# --- Audit logging ---
# Appends a structured line to .claude/guard-audit.log (if .claude/ exists).
# Args: $1 = decision (DENY/ALLOW), $2 = reason
_audit_log() {
  local decision="$1"
  local reason="$2"
  local log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude"
  if [ -d "$log_dir" ]; then
    printf '%s %s %s: %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$decision" \
      "$(basename "$0")" \
      "$reason" >> "${log_dir}/guard-audit.log" 2>/dev/null || true
  fi
}

# --- Atomic file write ---
# Reads content from stdin, writes to $1 atomically via temp file + mv.
# Args: $1 = target file path
_atomic_write() {
  local target="$1"
  local content
  content=$(cat)
  local tmp="${target}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}

# --- Logging helpers ---
# All output goes to stderr. Stdout is reserved for JSON responses to Claude Code.
hook_warn()  { echo "[toolkit:$(basename "$0" .sh)] WARN: $*" >&2; }
hook_error() { echo "[toolkit:$(basename "$0" .sh)] ERROR: $*" >&2; }
hook_info()  { echo "[toolkit:$(basename "$0" .sh)] $*" >&2; }
