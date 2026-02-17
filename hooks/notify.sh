#!/usr/bin/env bash
# Platform-aware notification helper
# Usage: notify.sh "Title" "Message" [sound]
#
# Platforms:
#   macOS:  Uses osascript (AppleScript)
#   Linux:  Uses notify-send (if available)
#   CI/headless: No-op (when $CI is set or no display available)
#
# set -u: Catch undefined variable bugs. No set -e/-o pipefail — hooks must
# degrade gracefully (exit 0 on unexpected errors rather than propagating failure).
set -u

# shellcheck source=_config.sh
source "$(dirname "$0")/_config.sh"

TITLE="${1:-Notification}"
MESSAGE="${2:-}"
SOUND="${3:-${TOOLKIT_NOTIFICATIONS_PERMISSION_SOUND}}"
APP_NAME="$TOOLKIT_NOTIFICATIONS_APP_NAME"

# No message = nothing to notify
[ -z "$MESSAGE" ] && exit 0

# CI/headless detection: skip notifications silently
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${JENKINS_HOME:-}" ]; then
  exit 0
fi

# --- macOS ---
if [ "$(uname -s)" = "Darwin" ]; then
  if command -v osascript >/dev/null 2>&1; then
    if [ -n "$SOUND" ] && [ "$SOUND" != "none" ]; then
      osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" subtitle \"$APP_NAME\" sound name \"$SOUND\"" 2>/dev/null
    else
      osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" subtitle \"$APP_NAME\"" 2>/dev/null
    fi
    exit 0
  fi
fi

# --- Linux ---
if [ "$(uname -s)" = "Linux" ]; then
  # Skip if no display server available
  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exit 0
  fi
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$TITLE" "$MESSAGE" --app-name="$APP_NAME" 2>/dev/null
    exit 0
  fi
fi

# Unsupported platform or missing tools — silent no-op
exit 0
