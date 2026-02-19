#!/usr/bin/env bash
# cmd-generate-settings.sh — Regenerate settings.json and .mcp.json
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# and helper functions (_info, _warn, _error, _ok, _require_python3,
# _require_toml, _read_toml_array, etc.)

cmd_generate_settings_inner() {
  # Internal helper — does the actual work, used by both init and generate-settings
  _require_python3 || return 1

  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  _require_toml || return 1

  # Generate config cache
  python3 "${TOOLKIT_DIR}/generate-config-cache.py" \
    --toml "$toml_file" \
    --output "${CLAUDE_DIR}/toolkit-cache.env" || {
    _error "Failed to generate config cache"
    return 1
  }
  _ok "Generated toolkit-cache.env"

  # Determine stacks for settings merge
  local stacks_args=""
  local stacks=""
  stacks=$(_read_toml_array "$toml_file" "project.stacks" 2>/dev/null || true)
  if [[ -n "$stacks" ]]; then
    local stack_files=""
    while IFS= read -r stack; do
      [[ -z "$stack" ]] && continue
      local stack_file="${TOOLKIT_DIR}/templates/stacks/${stack}.json"
      if [[ -f "$stack_file" ]]; then
        if [[ -n "$stack_files" ]]; then
          stack_files="${stack_files},${stack_file}"
        else
          stack_files="$stack_file"
        fi
      else
        _warn "Stack file not found: ${stack_file}"
      fi
    done <<< "$stacks"
    if [[ -n "$stack_files" ]]; then
      stacks_args="--stacks ${stack_files}"
    fi
  fi

  # Determine project overlay
  local project_args=""
  local project_file="${CLAUDE_DIR}/settings-project.json"
  if [[ -f "$project_file" ]]; then
    project_args="--project ${project_file}"
  fi

  # Determine MCP args
  local mcp_args=""
  local mcp_base="${TOOLKIT_DIR}/mcp/base.mcp.json"
  if [[ -f "$mcp_base" ]]; then
    mcp_args="--mcp-base ${mcp_base} --mcp-output ${PROJECT_DIR}/.mcp.json"
  fi

  # Build and run the generate-settings command
  # Set restrictive umask for generated settings files
  local old_umask
  old_umask=$(umask)
  umask 077
  # shellcheck disable=SC2086
  python3 "${TOOLKIT_DIR}/generate-settings.py" \
    --base "${TOOLKIT_DIR}/templates/settings-base.json" \
    $stacks_args \
    $project_args \
    --output "${CLAUDE_DIR}/settings.json" \
    $mcp_args || {
    umask "$old_umask"
    _error "Failed to generate settings.json"
    return 1
  }
  umask "$old_umask"
  _ok "Generated settings.json"

  if [[ -n "$mcp_args" ]]; then
    _ok "Generated .mcp.json"
  fi
}

cmd_generate_settings() {
  if _is_dry_run; then
    echo "Dry-run: showing what 'generate-settings' would do..."
    echo ""
    _init_preserve_existing_settings_dry_run
    _dry_run_msg "Would regenerate toolkit-cache.env"
    _dry_run_msg "Would regenerate settings.json"
    local mcp_base="${TOOLKIT_DIR}/mcp/base.mcp.json"
    if [[ -f "$mcp_base" ]]; then
      _dry_run_msg "Would regenerate .mcp.json"
    fi
    echo ""
    echo "No files were modified (dry-run mode)."
    return 0
  fi
  echo "Regenerating settings..."
  echo ""

  # Preserve existing settings for projects without settings-project.json
  _init_preserve_existing_settings

  cmd_generate_settings_inner
  echo ""
  _ok "Settings regenerated successfully"
}
