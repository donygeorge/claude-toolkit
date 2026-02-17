#!/bin/bash
# PreToolUse hook: Block Write/Edit to sensitive project files
# Prevents accidental modification of secrets, credentials, and critical configs.
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

INPUT=$(cat)

# Parse file path from JSON input
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# No file path — nothing to guard
[ -z "$FILE_PATH" ] && exit 0

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
  _audit_log "DENY" "$REASON"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$REASON" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    # Escape quotes and backslashes for JSON safety when jq is unavailable
    local SAFE_REASON
    SAFE_REASON=$(printf '%s' "$REASON" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$SAFE_REASON"
  fi
  exit 0
}

# =============================================================================
# 0. Toolkit config files — must be managed via toolkit.sh, not direct AI writes
# =============================================================================
# Match both absolute paths (*/.claude/...) and relative paths (.claude/...)
case "$FILE_PATH" in
  */.claude/settings.json | */.claude/toolkit.toml | */.claude/toolkit-cache.env | \
  .claude/settings.json | .claude/toolkit.toml | .claude/toolkit-cache.env)
    deny "Direct modification of toolkit config blocked — use 'toolkit.sh generate-settings'"
    ;;
esac

# Normalize: strip trailing slashes, resolve to basename for extension checks
BASENAME=$(basename "$FILE_PATH")

# =============================================================================
# 1. Environment / secret files
# =============================================================================
if echo "$BASENAME" | grep -qE '^\.(env|env\..*)$'; then
  deny "Blocked write to .env file — secrets must be edited manually"
fi

# =============================================================================
# 2. Credentials and key files
# =============================================================================
if echo "$BASENAME" | grep -qiE '(credentials|secrets?|keys?)\.(json|ya?ml|toml|ini|cfg)$'; then
  deny "Blocked write to credentials/secrets file — edit manually"
fi

if echo "$BASENAME" | grep -qiE '\.(pem|p12|pfx|key|crt|cert)$'; then
  deny "Blocked write to certificate/key file — edit manually"
fi

# =============================================================================
# 3. SSH and GPG files
# =============================================================================
if echo "$FILE_PATH" | grep -qE '(^|/)\.ssh/'; then
  deny "Blocked write to .ssh directory — SSH keys must be managed manually"
fi

if echo "$FILE_PATH" | grep -qE '(^|/)\.gnupg/'; then
  deny "Blocked write to .gnupg directory — GPG keys must be managed manually"
fi

# =============================================================================
# 4. Token / API key files
# =============================================================================
if echo "$BASENAME" | grep -qiE '(token|api_?key|auth)'; then
  if echo "$BASENAME" | grep -qiE '\.(json|ya?ml|toml|txt|ini|cfg)$'; then
    deny "Blocked write to token/API key file — edit manually"
  fi
fi

# =============================================================================
# 5. Git internal files
# =============================================================================
if echo "$FILE_PATH" | grep -qE '(^|/)\.git/'; then
  deny "Blocked write to .git internals — use git commands instead"
fi

# =============================================================================
# 6. Database files
# =============================================================================
# Database file protection (configurable via toolkit.toml, with safe default)
DB_PATTERN="${TOOLKIT_HOOKS_GUARD_DATABASE_PATTERN:-(^|/)data/.*\.(db|sqlite|sqlite3)$}"
if echo "$FILE_PATH" | grep -qE -- "$DB_PATTERN"; then
  deny "Blocked direct write to database file — use migrations or SQL commands"
fi

# All checks passed — allow the write
exit 0
