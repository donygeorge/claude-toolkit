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
    version=$(cat "${TOOLKIT_DIR}/VERSION" | tr -d '[:space:]')
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
