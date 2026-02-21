#!/usr/bin/env bash
# cmd-status.sh — Show toolkit status
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

cmd_status() {
  echo "Claude Toolkit Status"
  echo "====================="
  echo ""

  # Toolkit version
  local version="unknown"
  if [[ -f "${TOOLKIT_DIR}/VERSION" ]]; then
    version=$(tr -d '[:space:]' < "${TOOLKIT_DIR}/VERSION")
  fi
  echo "  Toolkit version: ${version}"

  # Project directory
  echo "  Project: ${PROJECT_DIR}"
  echo "  Toolkit: ${TOOLKIT_DIR}"

  # Check toolkit.toml
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ -f "$toml_file" ]]; then
    local project_name
    project_name=$(_read_toml_value "$toml_file" "project.name" 2>/dev/null || echo "unknown")
    echo "  Project name: ${project_name}"
  else
    echo "  Project name: (no toolkit.toml)"
  fi

  # Available stacks (auto-discovered from templates/stacks/)
  echo ""
  echo "  Available stacks:"
  local stacks_dir="${TOOLKIT_DIR}/templates/stacks"
  local has_stacks=false
  if [[ -d "$stacks_dir" ]]; then
    for stack_file in "${stacks_dir}"/*.json; do
      [[ -f "$stack_file" ]] || continue
      has_stacks=true
      local stack_name
      stack_name=$(basename "$stack_file" .json)
      local stack_desc=""
      if command -v jq &>/dev/null; then
        stack_desc=$(jq -r '._meta.description // ""' "$stack_file" 2>/dev/null || true)
      fi
      if [[ -n "$stack_desc" ]]; then
        echo "    ${stack_name}: ${stack_desc}"
      else
        echo "    ${stack_name}"
      fi
    done
  fi
  if [[ "$has_stacks" != true ]]; then
    echo "    (none found)"
  fi

  # Agents info
  echo ""
  echo "  Agents:"
  local agent_install_list=""
  if [[ -f "$toml_file" ]]; then
    agent_install_list=$(_read_toml_array "$toml_file" "agents.install" 2>/dev/null || true)
  fi
  # Default to reviewer and commit-check if no config
  if [[ -z "$agent_install_list" ]]; then
    agent_install_list=$'reviewer\ncommit-check'
  fi

  local agent_install_all=false
  local agent_install_none=false
  if printf '%s\n' "$agent_install_list" | grep -Fxq "all"; then
    agent_install_all=true
  elif printf '%s\n' "$agent_install_list" | grep -Fxq "none"; then
    agent_install_none=true
  fi

  echo "    Installed:"
  local installed_count=0
  local available_agents=""
  for agent_src in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_src" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_src")
    local agent_base="${agent_name%.md}"

    local is_installed=false
    if [[ "$agent_install_all" == true ]]; then
      is_installed=true
    elif [[ "$agent_install_none" == true ]]; then
      is_installed=false
    elif printf '%s\n' "$agent_install_list" | grep -Fxq "$agent_base"; then
      is_installed=true
    fi

    if [[ "$is_installed" == true ]]; then
      local agent_file="${CLAUDE_DIR}/agents/${agent_name}"
      local size_info=""
      if [[ -f "$agent_file" || -L "$agent_file" ]] && [[ -e "$agent_file" ]]; then
        local file_size
        file_size=$(wc -c < "$agent_file" 2>/dev/null || echo 0)
        local file_kb
        file_kb=$(awk "BEGIN { printf \"%.1f\", $file_size / 1024 }")
        size_info=" (${file_kb}KB)"
      fi
      echo "      ${agent_base}${size_info}"
      installed_count=$((installed_count + 1))
    else
      if [[ -n "$available_agents" ]]; then
        available_agents="${available_agents} ${agent_base}"
      else
        available_agents="$agent_base"
      fi
    fi
  done
  if [[ $installed_count -eq 0 ]]; then
    echo "      (none)"
  fi

  if [[ -n "$available_agents" ]]; then
    echo "    Available (not installed):"
    for avail in $available_agents; do
      echo "      ${avail}"
    done
  fi

  # Check config staleness
  local cache_file="${CLAUDE_DIR}/toolkit-cache.env"
  if [[ -f "$toml_file" ]] && [[ -f "$cache_file" ]]; then
    if [[ "$toml_file" -nt "$cache_file" ]]; then
      echo ""
      _warn "Config is stale: toolkit.toml is newer than toolkit-cache.env"
      echo "    Run: $0 generate-settings"
    else
      echo "  Config cache: up to date"
    fi
  elif [[ -f "$toml_file" ]] && [[ ! -f "$cache_file" ]]; then
    echo ""
    _warn "Config cache missing. Run: $0 generate-settings"
  fi

  # Manifest info
  echo ""
  if [[ -f "$MANIFEST_PATH" ]] && command -v jq &>/dev/null; then
    local manifest_version
    manifest_version=$(jq -r '.toolkit_version // "unknown"' "$MANIFEST_PATH")
    echo "  Manifest version: ${manifest_version}"

    local last_merge
    last_merge=$(jq -r '.last_subtree_merge // "none"' "$MANIFEST_PATH")
    if [[ -n "$last_merge" ]] && [[ "$last_merge" != "none" ]] && [[ "$last_merge" != "" ]]; then
      echo "  Last subtree merge: ${last_merge:0:12}"
    fi

    # Customized files
    echo ""
    echo "  Customized files:"
    local has_customized=false

    local agents
    agents=$(jq -r '.agents // {} | to_entries[] | select(.value.status == "customized") | "    agents/\(.key) (since \(.value.customized_at // "unknown"))"' "$MANIFEST_PATH" 2>/dev/null || true)
    if [[ -n "$agents" ]]; then
      echo "$agents"
      has_customized=true
    fi

    local skills
    skills=$(jq -r '.skills // {} | to_entries[] | select(.value.status == "customized") | "    skills/\(.key) (since \(.value.customized_at // "unknown"))"' "$MANIFEST_PATH" 2>/dev/null || true)
    if [[ -n "$skills" ]]; then
      echo "$skills"
      has_customized=true
    fi

    local rules
    rules=$(jq -r '.rules // {} | to_entries[] | select(.value.status == "customized") | "    rules/\(.key) (since \(.value.customized_at // "unknown"))"' "$MANIFEST_PATH" 2>/dev/null || true)
    if [[ -n "$rules" ]]; then
      echo "$rules"
      has_customized=true
    fi

    if [[ "$has_customized" != true ]]; then
      echo "    (none)"
    fi

    # Modified managed files (differ from toolkit source)
    echo ""
    echo "  Modified managed files:"
    local has_modified=false

    # Check agents
    for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
      [[ -f "$agent_file" ]] || continue
      local agent_name
      agent_name=$(basename "$agent_file")
      local project_file="${CLAUDE_DIR}/agents/${agent_name}"
      if [[ -f "$project_file" ]] && [[ ! -L "$project_file" ]]; then
        if ! diff -q "$agent_file" "$project_file" &>/dev/null; then
          local status
          status=$(jq -r --arg n "$agent_name" '.agents[$n].status // "managed"' "$MANIFEST_PATH" 2>/dev/null || echo "managed")
          if [[ "$status" != "customized" ]]; then
            echo "    agents/${agent_name} (modified)"
            has_modified=true
          fi
        fi
      fi
    done

    # Check skills
    for skill_dir in "${TOOLKIT_DIR}"/skills/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      local status
      status=$(jq -r --arg n "$skill_name" '.skills[$n].status // "managed"' "$MANIFEST_PATH" 2>/dev/null || echo "managed")
      if [[ "$status" == "customized" ]]; then
        continue
      fi
      for toolkit_file in "$skill_dir"*; do
        [[ -f "$toolkit_file" ]] || continue
        local fname
        fname=$(basename "$toolkit_file")
        local project_file="${CLAUDE_DIR}/skills/${skill_name}/${fname}"
        if [[ -f "$project_file" ]] && ! diff -q "$toolkit_file" "$project_file" &>/dev/null; then
          echo "    skills/${skill_name}/${fname} (modified)"
          has_modified=true
        fi
      done
    done

    if [[ "$has_modified" != true ]]; then
      echo "    (none)"
    fi
  else
    echo "  Manifest: not found (run 'init' first)"
  fi
}
