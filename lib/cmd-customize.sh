#!/usr/bin/env bash
# cmd-customize.sh — Convert managed file to customized
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

cmd_customize() {
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    _error "Usage: $0 customize <path>"
    echo "  Path is relative to .claude/ (e.g., agents/reviewer.md or skills/implement/SKILL.md)"
    return 1
  fi

  _require_jq || return 1

  local full_path="${CLAUDE_DIR}/${path}"

  if [[ ! -e "$full_path" ]]; then
    _error "File not found: ${full_path}"
    return 1
  fi

  # If it's a symlink, convert to a local copy
  if [[ -L "$full_path" ]]; then
    local link_target
    link_target=$(readlink "$full_path")
    # Resolve the symlink to get the actual file
    local resolved
    resolved=$(cd "$(dirname "$full_path")" && cd "$(dirname "$link_target")" && pwd)/$(basename "$link_target")
    if [[ -f "$resolved" ]]; then
      rm "$full_path"
      cp "$resolved" "$full_path"
      _ok "Converted symlink to local copy: ${path}"
    else
      _error "Symlink target not found: ${resolved}"
      return 1
    fi
  fi

  # Mark as customized in manifest
  if [[ -f "$MANIFEST_PATH" ]]; then
    export TOOLKIT_ROOT="$TOOLKIT_DIR"
    manifest_customize "$path" "$CLAUDE_DIR"
  else
    _warn "No manifest file found. Run 'init' first."
  fi
}
