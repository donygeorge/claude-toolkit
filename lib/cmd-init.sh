#!/usr/bin/env bash
# cmd-init.sh — Initialize toolkit in a project
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

# ============================================================================
# Init helper functions
# ============================================================================

_init_toml() {
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  local force="$1"
  local from_example="$2"

  if [[ ! -f "$toml_file" ]]; then
    if [[ "$from_example" == true ]]; then
      cp "${TOOLKIT_DIR}/templates/toolkit.toml.example" "$toml_file"
      _ok "Created toolkit.toml from example"
    else
      _error "toolkit.toml not found at ${toml_file}"
      echo ""
      echo "  Create one with:"
      echo "    cp ${TOOLKIT_DIR}/templates/toolkit.toml.example ${toml_file}"
      echo ""
      echo "  Or run: $0 init --from-example"
      return 1
    fi
  else
    _ok "toolkit.toml already exists"
  fi
}

_init_agents() {
  local force="$1"

  echo ""
  echo "Setting up agents..."
  mkdir -p "${CLAUDE_DIR}/agents"

  # Read agent install list from toolkit.toml
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  local install_list=""
  if [[ -f "$toml_file" ]]; then
    install_list=$(_read_toml_array "$toml_file" "agents.install" 2>/dev/null || true)
  fi

  # Default to reviewer and commit-check if no config
  if [[ -z "$install_list" ]]; then
    install_list=$'reviewer\ncommit-check'
  fi

  # Handle magic values
  local install_all=false
  local install_none=false
  if printf '%s\n' "$install_list" | grep -Fxq "all"; then
    install_all=true
  elif printf '%s\n' "$install_list" | grep -Fxq "none"; then
    install_none=true
  fi

  if [[ "$install_none" == true ]]; then
    _info "agents.install = [\"none\"] — skipping all agents"
    return 0
  fi

  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
    local agent_base="${agent_name%.md}"

    # Filter: skip agents not in the install list (unless install_all)
    if [[ "$install_all" != true ]]; then
      if ! printf '%s\n' "$install_list" | grep -Fxq "$agent_base"; then
        _info "Skipping agents/${agent_name} (not in agents.install)"
        continue
      fi
    fi

    local target="${CLAUDE_DIR}/agents/${agent_name}"
    local relative_path="../toolkit/agents/${agent_name}"

    if [[ -e "$target" ]] && [[ "$force" != true ]]; then
      _info "Skipping agents/${agent_name} (already exists, use --force to overwrite)"
      continue
    fi

    # Remove existing file/symlink if forcing
    [[ -e "$target" || -L "$target" ]] && rm -f "$target"

    # Try symlink, fall back to copy
    if ln -sf "$relative_path" "$target" 2>/dev/null; then
      _ok "Symlinked agents/${agent_name}"
    else
      cp "$agent_file" "$target"
      _warn "Copied agents/${agent_name} (symlink failed, will be copy-managed)"
    fi
  done
}

_init_skills() {
  local force="$1"

  echo ""
  echo "Setting up skills..."
  mkdir -p "${CLAUDE_DIR}/skills"
  for skill_dir in "${TOOLKIT_DIR}"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    local target_dir="${CLAUDE_DIR}/skills/${skill_name}"

    if [[ -d "$target_dir" ]] && [[ "$force" != true ]]; then
      _info "Skipping skills/${skill_name} (already exists, use --force to overwrite)"
      continue
    fi

    mkdir -p "$target_dir"
    local copied=0
    for skill_file in "$skill_dir"*; do
      [[ -f "$skill_file" ]] || continue
      local fname
      fname=$(basename "$skill_file")
      cp "$skill_file" "${target_dir}/${fname}"
      copied=$((copied + 1))
    done
    _ok "Copied skills/${skill_name} (${copied} files)"
  done
}

_init_rules() {
  local force="$1"

  echo ""
  echo "Setting up rules..."
  mkdir -p "${CLAUDE_DIR}/rules"
  for rule_file in "${TOOLKIT_DIR}"/rules/*.md; do
    [[ -f "$rule_file" ]] || continue
    local rule_name
    rule_name=$(basename "$rule_file")
    local target="${CLAUDE_DIR}/rules/${rule_name}"
    local relative_path="../toolkit/rules/${rule_name}"

    if [[ -e "$target" ]] && [[ "$force" != true ]]; then
      _info "Skipping rules/${rule_name} (already exists, use --force to overwrite)"
      continue
    fi

    [[ -e "$target" || -L "$target" ]] && rm -f "$target"

    if ln -sf "$relative_path" "$target" 2>/dev/null; then
      _ok "Symlinked rules/${rule_name}"
    else
      cp "$rule_file" "$target"
      _warn "Copied rules/${rule_name} (symlink failed)"
    fi
  done
}

_init_rule_templates() {
  local force="$1"
  local toml_file="${CLAUDE_DIR}/toolkit.toml"

  local stacks=""
  stacks=$(_read_toml_array "$toml_file" "project.stacks" 2>/dev/null || true)

  if [[ -n "$stacks" ]]; then
    echo ""
    echo "Applying rule templates for stacks..."
    while IFS= read -r stack; do
      [[ -z "$stack" ]] && continue
      # Find matching rule templates for this stack
      for template_file in "${TOOLKIT_DIR}"/templates/rules/*.md.template; do
        [[ -f "$template_file" ]] || continue
        local template_name
        template_name=$(basename "$template_file")
        local rule_name="${template_name%.template}"

        # Match templates to stacks by naming convention
        local should_copy=false

        case "$stack" in
          python)
            case "$template_name" in
              python.md.template|testing-pytest.md.template|api-routes-fastapi.md.template|database-sqlite.md.template)
                should_copy=true ;;
            esac
            ;;
          ios)
            case "$template_name" in
              swift.md.template) should_copy=true ;;
            esac
            ;;
          typescript)
            case "$template_name" in
              typescript.md.template|testing-jest.md.template)
                should_copy=true ;;
            esac
            ;;
        esac

        if [[ "$should_copy" == true ]]; then
          local target="${CLAUDE_DIR}/rules/${rule_name}"
          if [[ -e "$target" ]] && [[ "$force" != true ]]; then
            _info "Skipping rules/${rule_name} (already exists)"
            continue
          fi
          # Copy template, stripping .template suffix
          # Substitute {{PROJECT_NAME}} with project name from toolkit.toml
          local project_name
          project_name=$(_read_toml_value "$toml_file" "project.name" 2>/dev/null || echo "my-project")
          awk -v name="$project_name" '{gsub(/\{\{PROJECT_NAME\}\}/, name); print}' "$template_file" > "$target"
          _ok "Created rules/${rule_name} from template (stack: ${stack})"
        fi
      done
    done <<< "$stacks"
  fi
}

_init_agent_memory() {
  echo ""
  echo "Setting up agent memory..."
  mkdir -p "${CLAUDE_DIR}/agent-memory"
  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file" .md)
    local memory_file="${CLAUDE_DIR}/agent-memory/${agent_name}/MEMORY.md"
    if [[ ! -f "$memory_file" ]]; then
      mkdir -p "${CLAUDE_DIR}/agent-memory/${agent_name}"
      echo "# ${agent_name} Agent Memory" > "$memory_file"
      echo "" >> "$memory_file"
      echo "## Key Learnings" >> "$memory_file"
      echo "" >> "$memory_file"
      _ok "Created agent-memory/${agent_name}/MEMORY.md"
    else
      _info "Skipping agent-memory/${agent_name}/MEMORY.md (already exists)"
    fi
  done
}

_init_git_remote() {
  local force="$1"
  local toml_file="${CLAUDE_DIR}/toolkit.toml"

  echo ""
  echo "Setting up git remote..."
  local remote_url
  remote_url=$(_read_toml_value "$toml_file" "toolkit.remote_url" 2>/dev/null || true)
  if [[ -n "$remote_url" ]]; then
    if git -C "$PROJECT_DIR" remote get-url claude-toolkit &>/dev/null; then
      local existing_url
      existing_url=$(git -C "$PROJECT_DIR" remote get-url claude-toolkit)
      if [[ "$existing_url" != "$remote_url" ]]; then
        if [[ "$force" == true ]]; then
          git -C "$PROJECT_DIR" remote set-url claude-toolkit "$remote_url"
          _ok "Updated git remote 'claude-toolkit' to ${remote_url}"
        else
          _warn "Git remote 'claude-toolkit' exists with different URL: ${existing_url}"
          _info "Use --force to update"
        fi
      else
        _ok "Git remote 'claude-toolkit' already configured"
      fi
    else
      git -C "$PROJECT_DIR" remote add claude-toolkit "$remote_url" 2>/dev/null || true
      _ok "Added git remote 'claude-toolkit' -> ${remote_url}"
    fi
  else
    _info "No remote_url in toolkit.toml, skipping git remote"
  fi
}

_init_strip_overlapping_hooks() {
  # Strip hook entries from settings-project.json that would duplicate
  # toolkit base hooks (same event type + same matcher).
  # Unique project hooks (no toolkit equivalent) are preserved.
  local project_file="$1"
  local base_file="${TOOLKIT_DIR}/templates/settings-base.json"

  [[ -f "$project_file" ]] || return 0
  [[ -f "$base_file" ]] || return 0

  # Check if project has any hooks at all
  local project_hooks
  project_hooks=$(jq -r '.hooks // {} | keys[]' "$project_file" 2>/dev/null || true)
  [[ -z "$project_hooks" ]] && return 0

  # Build a list of event+matcher pairs from the toolkit base
  local base_matchers
  base_matchers=$(jq -r '
    .hooks // {} | to_entries[] |
    .key as $event |
    (.value // [])[] |
    "\($event):\(.matcher // "__no_matcher__")"
  ' "$base_file" 2>/dev/null || true)
  [[ -z "$base_matchers" ]] && return 0

  # For each event in the project hooks, filter out entries whose matcher
  # overlaps with a toolkit base entry
  local stripped_count=0
  local stripped
  stripped=$(jq --argjson base_matchers "$(echo "$base_matchers" | jq -R -s 'split("\n") | map(select(length > 0))')" '
    .hooks as $hooks |
    if $hooks == null then . else
    reduce ($hooks | to_entries[]) as $event (.;
      $event.key as $ename |
      if ($event.value | type) == "array" then
        # Filter entries: keep only those whose event:matcher is NOT in base
        ($event.value | map(
          select(
            ("\($ename):\(.matcher // "__no_matcher__")" | IN($base_matchers[])) | not
          )
        )) as $kept |
        if ($kept | length) == ($event.value | length) then .
        elif ($kept | length) == 0 then .hooks |= del(.[$ename])
        else .hooks[$ename] = $kept
        end
      else .
      end
    )
    end
  ' "$project_file" 2>/dev/null) || true

  if [[ -n "$stripped" ]]; then
    # Count how many entries were removed
    local orig_count new_count
    orig_count=$(jq '[.hooks // {} | .[] | if type == "array" then length else 0 end] | add // 0' "$project_file" 2>/dev/null || echo 0)
    _atomic_write "$project_file" "$stripped"
    new_count=$(jq '[.hooks // {} | .[] | if type == "array" then length else 0 end] | add // 0' "$project_file" 2>/dev/null || echo 0)
    stripped_count=$((orig_count - new_count))
    if [[ $stripped_count -gt 0 ]]; then
      _warn "Stripped ${stripped_count} hook entries that overlap with toolkit base hooks"
      _info "  These would have caused duplicate invocations after merge"
      _info "  Original settings preserved in settings.json.pre-toolkit"
    fi
  fi
}

_init_preserve_existing_settings() {
  local settings_file="${CLAUDE_DIR}/settings.json"
  local project_file="${CLAUDE_DIR}/settings-project.json"
  local mcp_file="${PROJECT_DIR}/.mcp.json"

  # Skip if settings-project.json already exists (user already configured)
  if [[ -f "$project_file" ]]; then
    _info "settings-project.json already exists, skipping settings preservation"
    return 0
  fi

  # Skip if no existing settings.json to preserve
  if [[ ! -f "$settings_file" ]]; then
    return 0
  fi

  # Validate settings.json is valid JSON before preservation
  if ! jq empty "$settings_file" 2>/dev/null; then
    _warn "Existing settings.json is not valid JSON — skipping preservation"
    _info "  Fix the file manually or remove it before running init"
    return 0
  fi

  echo ""
  echo "Preserving existing settings..."

  # Back up and convert settings.json to settings-project.json
  cp "$settings_file" "${settings_file}.pre-toolkit"
  _ok "Backed up settings.json -> settings.json.pre-toolkit"

  cp "$settings_file" "$project_file"
  _ok "Created settings-project.json from existing settings.json"

  # Strip hook entries that overlap with toolkit base hooks.
  # The toolkit base provides hooks for specific event+matcher combinations.
  # If the project had its own hooks for the same events, both would fire
  # after the merge — causing duplicate invocations.
  _init_strip_overlapping_hooks "$project_file"

  # If .mcp.json also exists, extract mcpServers into settings-project.json
  if [[ -f "$mcp_file" ]]; then
    # Validate .mcp.json before extraction
    if ! jq empty "$mcp_file" 2>/dev/null; then
      _warn "Existing .mcp.json is not valid JSON — skipping MCP merge"
      _info "  Review the file manually after setup"
      cp "$mcp_file" "${mcp_file}.pre-toolkit"
      _ok "Backed up .mcp.json -> .mcp.json.pre-toolkit (invalid JSON)"
      return 0
    fi

    cp "$mcp_file" "${mcp_file}.pre-toolkit"
    _ok "Backed up .mcp.json -> .mcp.json.pre-toolkit"

    # Extract mcpServers and merge into settings-project.json
    local mcp_servers
    mcp_servers=$(jq '.mcpServers // {}' "$mcp_file" 2>/dev/null || echo '{}')

    if [[ "$mcp_servers" != "{}" ]]; then
      local merged
      merged=$(jq --argjson servers "$mcp_servers" \
        '. + {mcpServers: ((.mcpServers // {}) * $servers)}' \
        "$project_file" 2>/dev/null) || true
      if [[ -n "$merged" ]]; then
        _atomic_write "$project_file" "$merged"
        _ok "Merged mcpServers from .mcp.json into settings-project.json"
      else
        _warn "Could not merge mcpServers (settings-project.json may have invalid JSON)"
        _info "  You may need to manually add mcpServers from .mcp.json.pre-toolkit"
      fi
    fi
  fi
}

_init_config() {
  echo ""
  echo "Generating configuration..."
  cmd_generate_settings_inner || {
    _error "Settings generation failed. Fix toolkit.toml before continuing."
    return 1
  }
}

_init_manifest() {
  echo ""
  echo "Creating manifest..."
  # Set TOOLKIT_ROOT for manifest functions
  export TOOLKIT_ROOT="$TOOLKIT_DIR"
  manifest_init "$CLAUDE_DIR"

  # Update manifest for copy-managed agents (if any symlinks failed)
  for agent_file in "${CLAUDE_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
    if [[ -f "$agent_file" ]] && [[ ! -L "$agent_file" ]]; then
      # It's a copy, not a symlink — check if the toolkit source exists
      if [[ -f "${TOOLKIT_DIR}/agents/${agent_name}" ]]; then
        local toolkit_hash
        toolkit_hash=$(_file_hash "${TOOLKIT_DIR}/agents/${agent_name}")
        local project_hash
        project_hash=$(_file_hash "$agent_file")
        if [[ "$toolkit_hash" == "$project_hash" ]]; then
          # Content matches — mark as copy-managed
          local updated_manifest
          updated_manifest=$(jq --arg name "$agent_name" \
            '.agents[$name].status = "copy-managed"' \
            "$MANIFEST_PATH")
          _atomic_write "$MANIFEST_PATH" "$updated_manifest"
        fi
      fi
    fi
  done
}

# ============================================================================
# cmd_init — main entry point
# ============================================================================

cmd_init() {
  local force=false
  local from_example=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      --from-example) from_example=true; shift ;;
      --dry-run) DRY_RUN=true; export DRY_RUN; shift ;;
      *) _error "Unknown option: $1"; return 1 ;;
    esac
  done

  _require_jq || return 1
  _require_python3 || return 1

  if _is_dry_run; then
    echo "Dry-run: showing what 'init' would do in ${PROJECT_DIR}..."
    echo ""
    _dry_run_msg "Would create directory: ${CLAUDE_DIR}"
    _init_toml_dry_run "$from_example"
    _init_agents_dry_run "$force"
    _init_skills_dry_run "$force"
    _init_rules_dry_run "$force"
    _init_rule_templates_dry_run "$force"
    _init_agent_memory_dry_run
    _init_git_remote_dry_run
    _init_preserve_existing_settings_dry_run
    _dry_run_msg "Would generate toolkit-cache.env"
    _dry_run_msg "Would generate settings.json"
    _dry_run_msg "Would create toolkit-manifest.json"
    echo ""
    echo "No files were modified (dry-run mode)."
    return 0
  fi

  echo "Initializing claude-toolkit in ${PROJECT_DIR}..."
  echo ""

  # Ensure .claude directory exists
  mkdir -p "$CLAUDE_DIR"

  _init_toml "$force" "$from_example" || return 1
  _init_agents "$force"
  _init_skills "$force"
  _init_rules "$force"
  _init_rule_templates "$force"
  _init_agent_memory
  _init_git_remote "$force"
  _init_preserve_existing_settings
  _init_config || return 1
  _init_manifest

  echo ""
  echo "Toolkit initialized successfully!"
  echo "  Project: ${PROJECT_DIR}"
  echo "  Toolkit: ${TOOLKIT_DIR}"
  echo ""
  echo "Next steps:"
  echo "  1. Edit .claude/toolkit.toml to match your project"
  echo "  2. Run: $0 generate-settings"
  echo "  3. Commit the .claude/ directory"
}

# ============================================================================
# Dry-run helpers for init
# ============================================================================

_init_toml_dry_run() {
  local from_example="$1"
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ ! -f "$toml_file" ]]; then
    if [[ "$from_example" == true ]]; then
      _dry_run_msg "Would create toolkit.toml from example template"
    else
      _dry_run_msg "Would require toolkit.toml (not found)"
    fi
  else
    _dry_run_msg "toolkit.toml already exists (no change)"
  fi
}

_init_agents_dry_run() {
  local force="$1"

  # Read agent install list from toolkit.toml
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  local install_list=""
  if [[ -f "$toml_file" ]]; then
    install_list=$(_read_toml_array "$toml_file" "agents.install" 2>/dev/null || true)
  fi

  # Default to reviewer and commit-check if no config
  if [[ -z "$install_list" ]]; then
    install_list=$'reviewer\ncommit-check'
  fi

  # Handle magic values
  local install_all=false
  local install_none=false
  if printf '%s\n' "$install_list" | grep -Fxq "all"; then
    install_all=true
  elif printf '%s\n' "$install_list" | grep -Fxq "none"; then
    install_none=true
  fi

  if [[ "$install_none" == true ]]; then
    _dry_run_msg "Would skip all agents (agents.install = [\"none\"])"
    return 0
  fi

  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
    local agent_base="${agent_name%.md}"

    # Filter: skip agents not in the install list (unless install_all)
    if [[ "$install_all" != true ]]; then
      if ! printf '%s\n' "$install_list" | grep -Fxq "$agent_base"; then
        _dry_run_msg "Would skip agents/${agent_name} (not in agents.install)"
        continue
      fi
    fi

    local target="${CLAUDE_DIR}/agents/${agent_name}"
    if [[ -e "$target" ]] && [[ "$force" != true ]]; then
      _dry_run_msg "Would skip agents/${agent_name} (already exists)"
    else
      _dry_run_msg "Would symlink agents/${agent_name}"
    fi
  done
}

_init_skills_dry_run() {
  local force="$1"
  for skill_dir in "${TOOLKIT_DIR}"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    local target_dir="${CLAUDE_DIR}/skills/${skill_name}"
    if [[ -d "$target_dir" ]] && [[ "$force" != true ]]; then
      _dry_run_msg "Would skip skills/${skill_name} (already exists)"
    else
      local count=0
      for f in "$skill_dir"*; do
        [[ -f "$f" ]] && count=$((count + 1))
      done
      _dry_run_msg "Would copy skills/${skill_name} (${count} files)"
    fi
  done
}

_init_rules_dry_run() {
  local force="$1"
  for rule_file in "${TOOLKIT_DIR}"/rules/*.md; do
    [[ -f "$rule_file" ]] || continue
    local rule_name
    rule_name=$(basename "$rule_file")
    local target="${CLAUDE_DIR}/rules/${rule_name}"
    if [[ -e "$target" ]] && [[ "$force" != true ]]; then
      _dry_run_msg "Would skip rules/${rule_name} (already exists)"
    else
      _dry_run_msg "Would symlink rules/${rule_name}"
    fi
  done
}

_init_rule_templates_dry_run() {
  local force="$1"
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ ! -f "$toml_file" ]]; then
    return 0
  fi
  local stacks=""
  stacks=$(_read_toml_array "$toml_file" "project.stacks" 2>/dev/null || true)
  if [[ -n "$stacks" ]]; then
    _dry_run_msg "Would apply rule templates for stacks: $(echo "$stacks" | tr '\n' ', ')"
  fi
}

_init_agent_memory_dry_run() {
  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file" .md)
    local memory_file="${CLAUDE_DIR}/agent-memory/${agent_name}/MEMORY.md"
    if [[ ! -f "$memory_file" ]]; then
      _dry_run_msg "Would create agent-memory/${agent_name}/MEMORY.md"
    fi
  done
}

_init_git_remote_dry_run() {
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ -f "$toml_file" ]]; then
    local remote_url
    remote_url=$(_read_toml_value "$toml_file" "toolkit.remote_url" 2>/dev/null || true)
    if [[ -n "$remote_url" ]]; then
      _dry_run_msg "Would set up git remote 'claude-toolkit' -> ${remote_url}"
    fi
  fi
}

_init_preserve_existing_settings_dry_run() {
  local settings_file="${CLAUDE_DIR}/settings.json"
  local project_file="${CLAUDE_DIR}/settings-project.json"
  local mcp_file="${PROJECT_DIR}/.mcp.json"

  if [[ -f "$project_file" ]]; then
    _dry_run_msg "settings-project.json already exists (no preservation needed)"
    return 0
  fi

  if [[ -f "$settings_file" ]]; then
    _dry_run_msg "Would back up settings.json -> settings.json.pre-toolkit"
    _dry_run_msg "Would create settings-project.json from existing settings.json"
    if [[ -f "$mcp_file" ]]; then
      _dry_run_msg "Would back up .mcp.json -> .mcp.json.pre-toolkit"
      _dry_run_msg "Would merge mcpServers from .mcp.json into settings-project.json"
    fi
  fi
}
