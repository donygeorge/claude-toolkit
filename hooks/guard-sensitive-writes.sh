#!/bin/bash
# PreToolUse hook: Block Write/Edit to sensitive project files
# Prevents accidental modification of secrets, credentials, and critical configs.

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

# --- deny helper ---
deny() {
  local REASON="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg reason "$REASON" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
  fi
  exit 0
}

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
DB_PATTERN="${TOOLKIT_HOOKS_GUARD_DATABASE_PATTERN:-'(^|/)data/.*\.(db|sqlite|sqlite3)$'}"
if echo "$FILE_PATH" | grep -qE "$DB_PATTERN"; then
  deny "Blocked direct write to database file — use migrations or SQL commands"
fi

# All checks passed — allow the write
exit 0
