#!/usr/bin/env bash
# PreToolUse hook: Block Write/Edit to sensitive project files
# Prevents accidental modification of secrets, credentials, and critical configs.
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"
# shellcheck source=../lib/hook-utils.sh
source "$(dirname "$0")/../lib/hook-utils.sh"

hook_read_input

# Only guard Write/Edit operations — skip other PreToolUse events
case "$HOOK_TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

# No file path — nothing to guard
[ -z "$HOOK_FILE_PATH" ] && exit 0

# Skip if guards are disabled
if [ "${TOOLKIT_GUARD_ENABLED:-true}" = "false" ]; then exit 0; fi

# =============================================================================
# 0. Toolkit generated files — must be managed via toolkit.sh, not direct AI writes
# =============================================================================
# Note: toolkit.toml is intentionally NOT blocked — it's the user config file
# that AI should be able to write/edit (e.g., during /toolkit-setup).
# Only generated files that should be regenerated from source are blocked.
# Match both absolute paths (*/.claude/...) and relative paths (.claude/...)
case "$HOOK_FILE_PATH" in
  */.claude/settings.json | */.claude/toolkit-cache.env | \
  .claude/settings.json | .claude/toolkit-cache.env)
    hook_deny "Direct modification of generated toolkit file blocked — use 'toolkit.sh generate-settings'"
    ;;
esac

# Normalize: strip trailing slashes, resolve to basename for extension checks
BASENAME=$(basename "$HOOK_FILE_PATH")

# =============================================================================
# 1. Environment / secret files
# =============================================================================
if echo "$BASENAME" | grep -qE '^\.(env|env\..*)$'; then
  hook_deny "Blocked write to .env file — secrets must be edited manually"
fi

# =============================================================================
# 2. Credentials and key files
# =============================================================================
if echo "$BASENAME" | grep -qiE '(credentials|secrets?|keys?)\.(json|ya?ml|toml|ini|cfg)$'; then
  hook_deny "Blocked write to credentials/secrets file — edit manually"
fi

if echo "$BASENAME" | grep -qiE '\.(pem|p12|pfx|key|crt|cert)$'; then
  hook_deny "Blocked write to certificate/key file — edit manually"
fi

# =============================================================================
# 3. SSH and GPG files
# =============================================================================
if echo "$HOOK_FILE_PATH" | grep -qE '(^|/)\.ssh/'; then
  hook_deny "Blocked write to .ssh directory — SSH keys must be managed manually"
fi

if echo "$HOOK_FILE_PATH" | grep -qE '(^|/)\.gnupg/'; then
  hook_deny "Blocked write to .gnupg directory — GPG keys must be managed manually"
fi

# =============================================================================
# 4. Token / API key files
# =============================================================================
if echo "$BASENAME" | grep -qiE '(token|api_?key|auth)'; then
  if echo "$BASENAME" | grep -qiE '\.(json|ya?ml|toml|txt|ini|cfg)$'; then
    hook_deny "Blocked write to token/API key file — edit manually"
  fi
fi

# =============================================================================
# 5. Git internal files
# =============================================================================
if echo "$HOOK_FILE_PATH" | grep -qE '(^|/)\.git/'; then
  hook_deny "Blocked write to .git internals — use git commands instead"
fi

# =============================================================================
# 6. Database files
# =============================================================================
# Database file protection (configurable via toolkit.toml, with safe default)
DB_PATTERN="${TOOLKIT_HOOKS_GUARD_DATABASE_PATTERN:-(^|/)data/.*\.(db|sqlite|sqlite3)$}"
if echo "$HOOK_FILE_PATH" | grep -qE -- "$DB_PATTERN"; then
  hook_deny "Blocked direct write to database file — use migrations or SQL commands"
fi

# All checks passed — allow the write
exit 0
