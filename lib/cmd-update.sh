#!/usr/bin/env bash
# cmd-update.sh — Update toolkit from remote via git subtree
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

# ============================================================================
# _refresh_symlinks — Re-create broken agent/rule symlinks after update
# ============================================================================

_refresh_symlinks() {
  # Re-create agent symlinks if broken
  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
    local target="${CLAUDE_DIR}/agents/${agent_name}"
    local relative_path="../toolkit/agents/${agent_name}"

    # Skip customized agents
    if [[ -f "$MANIFEST_PATH" ]]; then
      local status
      status=$(jq -r --arg name "$agent_name" '.agents[$name].status // "managed"' "$MANIFEST_PATH" 2>/dev/null || echo "managed")
      if [[ "$status" == "customized" ]]; then
        _info "Skipping customized agent: ${agent_name}"
        continue
      fi
    fi

    # If it's a broken symlink or doesn't exist, re-create
    if [[ -L "$target" ]] && [[ ! -e "$target" ]]; then
      rm -f "$target"
      ln -sf "$relative_path" "$target"
      _ok "Fixed broken symlink: agents/${agent_name}"
    elif [[ ! -e "$target" ]]; then
      ln -sf "$relative_path" "$target" 2>/dev/null || cp "$agent_file" "$target"
      _ok "Created: agents/${agent_name}"
    fi
  done

  # Re-create rule symlinks if broken
  for rule_file in "${TOOLKIT_DIR}"/rules/*.md; do
    [[ -f "$rule_file" ]] || continue
    local rule_name
    rule_name=$(basename "$rule_file")
    local target="${CLAUDE_DIR}/rules/${rule_name}"
    local relative_path="../toolkit/rules/${rule_name}"

    # Skip customized rules
    if [[ -f "$MANIFEST_PATH" ]]; then
      local status
      status=$(jq -r --arg name "$rule_name" '.rules[$name].status // "managed"' "$MANIFEST_PATH" 2>/dev/null || echo "managed")
      if [[ "$status" == "customized" ]]; then
        _info "Skipping customized rule: ${rule_name}"
        continue
      fi
    fi

    if [[ -L "$target" ]] && [[ ! -e "$target" ]]; then
      rm -f "$target"
      ln -sf "$relative_path" "$target"
      _ok "Fixed broken symlink: rules/${rule_name}"
    elif [[ ! -e "$target" ]]; then
      ln -sf "$relative_path" "$target" 2>/dev/null || cp "$rule_file" "$target"
      _ok "Created: rules/${rule_name}"
    fi
  done
}

# ============================================================================
# cmd_update — main entry point
# ============================================================================

cmd_update() {
  local version=""
  local latest=false
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --latest) latest=true; shift ;;
      --force) force=true; shift ;;
      v*) version="$1"; shift ;;
      *) _error "Unknown option: $1"; return 1 ;;
    esac
  done

  _require_jq || return 1

  # Check for uncommitted changes in the subtree
  if [[ "$force" != true ]]; then
    local toolkit_changes
    toolkit_changes=$(git -C "$PROJECT_DIR" diff --name-only -- .claude/toolkit/ 2>/dev/null || true)
    if [[ -n "$toolkit_changes" ]]; then
      _error "Uncommitted changes in .claude/toolkit/. Commit first or use --force."
      echo "$toolkit_changes" | head -5
      return 1
    fi
  fi

  # Check remote exists
  if ! git -C "$PROJECT_DIR" remote get-url claude-toolkit &>/dev/null; then
    _error "Git remote 'claude-toolkit' not found."
    echo "  Add it with: git remote add claude-toolkit <url>"
    return 1
  fi

  echo "Fetching from claude-toolkit remote..."
  git -C "$PROJECT_DIR" fetch claude-toolkit --tags 2>/dev/null || {
    _error "Failed to fetch from claude-toolkit remote."
    return 1
  }

  local ref=""
  if [[ -n "$version" ]]; then
    # Specific version
    ref="$version"
    echo "Updating to version: ${version}"
  elif [[ "$latest" == true ]]; then
    # Latest main
    ref="claude-toolkit/main"
    echo "Updating to latest main..."
  else
    # Latest semver tag
    ref=$(git -C "$PROJECT_DIR" tag -l 'v*' --sort=-version:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
    if [[ -z "$ref" ]]; then
      _warn "No semver tags found. Pulling from main instead."
      ref="claude-toolkit/main"
    else
      echo "Updating to latest release: ${ref}"
    fi
  fi

  # Perform subtree pull
  echo ""
  git -C "$PROJECT_DIR" subtree pull --squash --prefix=.claude/toolkit claude-toolkit "$ref" -m "Update claude-toolkit to ${ref}" || {
    _error "Subtree pull failed. You may need to resolve conflicts."
    return 1
  }

  # Record merge commit in manifest
  local merge_hash
  merge_hash=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")

  if [[ -f "$MANIFEST_PATH" ]]; then
    local updated_manifest
    updated_manifest=$(jq --arg hash "$merge_hash" '.last_subtree_merge = $hash' "$MANIFEST_PATH")
    _atomic_write "$MANIFEST_PATH" "$updated_manifest"
  fi

  # Verify pulled code integrity
  echo ""
  echo "Verifying toolkit integrity..."
  if command -v shellcheck &>/dev/null; then
    if shellcheck -x -S warning "${TOOLKIT_DIR}"/hooks/*.sh "${TOOLKIT_DIR}"/lib/*.sh "${TOOLKIT_DIR}"/toolkit.sh 2>/dev/null; then
      _ok "All scripts pass shellcheck"
    else
      _warn "Updated toolkit has shellcheck warnings. Review before using."
    fi
  else
    _info "shellcheck not installed — skipping integrity verification"
  fi

  # Show what changed
  echo ""
  echo "Changes in this update:"
  git -C "$PROJECT_DIR" diff --stat HEAD~1 -- .claude/toolkit/ 2>/dev/null || _info "Could not determine changes"

  # Refresh symlinks
  echo ""
  echo "Refreshing symlinks..."
  _refresh_symlinks

  # Update managed skills (skip customized)
  echo ""
  echo "Updating managed skills..."
  export TOOLKIT_ROOT="$TOOLKIT_DIR"
  for skill_dir in "${TOOLKIT_DIR}"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    manifest_update_skill "$skill_name" "$CLAUDE_DIR"
  done

  # Preserve existing settings for legacy installs (no settings-project.json)
  _init_preserve_existing_settings

  # Regenerate settings
  echo ""
  echo "Regenerating settings..."
  cmd_generate_settings_inner || {
    _error "Settings generation failed. Fix toolkit.toml before continuing."
    return 1
  }

  # Update manifest version
  if [[ -f "$MANIFEST_PATH" ]]; then
    local new_version
    new_version=$(cat "${TOOLKIT_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown")
    local updated_manifest
    updated_manifest=$(jq --arg v "$new_version" '.toolkit_version = $v' "$MANIFEST_PATH")
    _atomic_write "$MANIFEST_PATH" "$updated_manifest"
  fi

  echo ""
  _ok "Toolkit updated to ${ref}"
}
