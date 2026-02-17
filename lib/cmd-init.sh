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
  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
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
  for agent_file in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local agent_name
    agent_name=$(basename "$agent_file")
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
