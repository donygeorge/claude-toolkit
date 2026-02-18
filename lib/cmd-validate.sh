#!/usr/bin/env bash
# cmd-validate.sh — Check toolkit health
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

cmd_validate() {
  local errors=0
  local warnings=0

  echo "Validating claude-toolkit..."
  echo ""

  # Check subtree exists
  if [[ -d "$TOOLKIT_DIR" ]]; then
    _ok "Toolkit directory exists at .claude/toolkit/"
  else
    _error "Toolkit directory not found at .claude/toolkit/"
    errors=$((errors + 1))
  fi

  # Check toolkit.toml
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ -f "$toml_file" ]]; then
    if python3 "${TOOLKIT_DIR}/generate-config-cache.py" --validate-only --toml "$toml_file" &>/dev/null; then
      _ok "toolkit.toml is valid"
    else
      _error "toolkit.toml has validation errors"
      python3 "${TOOLKIT_DIR}/generate-config-cache.py" --validate-only --toml "$toml_file" 2>&1 || true
      errors=$((errors + 1))
    fi
  else
    _error "toolkit.toml not found"
    errors=$((errors + 1))
  fi

  # Check manifest
  if [[ -f "$MANIFEST_PATH" ]]; then
    if jq empty "$MANIFEST_PATH" 2>/dev/null; then
      _ok "Manifest is valid JSON"
    else
      _error "Manifest is not valid JSON"
      errors=$((errors + 1))
    fi
  else
    _warn "Manifest not found (run 'init')"
    warnings=$((warnings + 1))
  fi

  # Check settings.json
  local settings_file="${CLAUDE_DIR}/settings.json"
  if [[ -f "$settings_file" ]]; then
    if jq empty "$settings_file" 2>/dev/null; then
      _ok "settings.json is valid JSON"
    else
      _error "settings.json is not valid JSON"
      errors=$((errors + 1))
    fi
  else
    _warn "settings.json not found (run 'generate-settings')"
    warnings=$((warnings + 1))
  fi

  # Check all symlinks resolve (agents, rules, skills)
  echo ""
  echo "Checking symlinks..."
  local broken_links=0
  for link in "${CLAUDE_DIR}"/agents/*.md "${CLAUDE_DIR}"/rules/*.md; do
    [[ -L "$link" ]] || continue
    if [[ ! -e "$link" ]]; then
      _error "Broken symlink: ${link#${PROJECT_DIR}/}"
      broken_links=$((broken_links + 1))
      errors=$((errors + 1))
    fi
  done
  # Check skill symlinks/copies
  if [[ -d "${CLAUDE_DIR}/skills" ]]; then
    for link in "${CLAUDE_DIR}"/skills/*/; do
      [[ -L "${link%/}" ]] || continue
      if [[ ! -e "$link" ]]; then
        _error "Broken skill symlink: ${link#${PROJECT_DIR}/}"
        broken_links=$((broken_links + 1))
        errors=$((errors + 1))
      fi
    done
  fi
  if [[ $broken_links -eq 0 ]]; then
    _ok "All symlinks resolve"
  fi

  # Check all toolkit skills are registered in .claude/skills/
  if [[ -d "${CLAUDE_DIR}/skills" ]] && [[ -d "${TOOLKIT_DIR}/skills" ]]; then
    echo ""
    echo "Checking skill registration..."
    local missing_skills=0
    for skill_dir in "${TOOLKIT_DIR}"/skills/*/; do
      [[ -d "$skill_dir" ]] || continue
      local sname
      sname=$(basename "$skill_dir")
      if [[ ! -e "${CLAUDE_DIR}/skills/${sname}" ]] && [[ ! -L "${CLAUDE_DIR}/skills/${sname}" ]]; then
        _error "Skill '${sname}' exists in toolkit but not registered in .claude/skills/"
        missing_skills=$((missing_skills + 1))
        errors=$((errors + 1))
      fi
    done
    if [[ $missing_skills -eq 0 ]]; then
      _ok "All toolkit skills registered in .claude/skills/"
    fi
  fi

  # Check hooks referenced in settings.json exist and are executable
  if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
    echo ""
    echo "Checking hooks..."
    local hook_commands
    hook_commands=$(jq -r '.hooks // {} | .. | objects | .command? // empty' "$settings_file" 2>/dev/null | sort -u || true)
    local hook_errors=0
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      # Resolve $CLAUDE_PROJECT_DIR
      local resolved_cmd="${cmd//\$CLAUDE_PROJECT_DIR/$PROJECT_DIR}"
      # Extract the script path (first token)
      local script_path
      script_path=$(echo "$resolved_cmd" | awk '{print $1}')
      # Handle python3 prefix
      if [[ "$script_path" == "python3" ]]; then
        script_path=$(echo "$resolved_cmd" | awk '{print $2}')
        script_path="${script_path//\$CLAUDE_PROJECT_DIR/$PROJECT_DIR}"
      fi
      if [[ -f "$script_path" ]]; then
        if [[ -x "$script_path" ]] || [[ "$script_path" == *.py ]]; then
          : # ok
        else
          _warn "Hook not executable: ${script_path#${PROJECT_DIR}/}"
          warnings=$((warnings + 1))
        fi
      else
        _error "Hook script not found: ${script_path#${PROJECT_DIR}/}"
        hook_errors=$((hook_errors + 1))
        errors=$((errors + 1))
      fi
    done <<< "$hook_commands"
    if [[ $hook_errors -eq 0 ]]; then
      _ok "All hook scripts found"
    fi
  fi

  # Check config staleness
  local cache_file="${CLAUDE_DIR}/toolkit-cache.env"
  if [[ -f "$toml_file" ]] && [[ -f "$cache_file" ]]; then
    if [[ "$toml_file" -nt "$cache_file" ]]; then
      _warn "Config is stale: toolkit.toml is newer than toolkit-cache.env"
      warnings=$((warnings + 1))
    fi
  fi

  # Summary
  echo ""
  if [[ $errors -eq 0 ]] && [[ $warnings -eq 0 ]]; then
    echo "Validation passed: no errors, no warnings."
  elif [[ $errors -eq 0 ]]; then
    echo "Validation passed with ${warnings} warning(s)."
  else
    echo "Validation failed: ${errors} error(s), ${warnings} warning(s)."
    return 1
  fi
}
