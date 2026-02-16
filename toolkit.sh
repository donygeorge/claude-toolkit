#!/usr/bin/env bash
# toolkit.sh — Main CLI for claude-toolkit
#
# Usage:
#   .claude/toolkit/toolkit.sh <subcommand> [options]
#
# Subcommands:
#   init              Initialize toolkit in a project
#   update [version]  Update toolkit from remote
#   customize <path>  Convert managed file to customized
#   status            Show toolkit status
#   validate          Check toolkit health
#   generate-settings Regenerate settings.json and .mcp.json
#   help              Show this help message

set -euo pipefail

# ============================================================================
# Path resolution
# ============================================================================

# The toolkit directory is where this script lives
TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"

# The project directory is two levels up from .claude/toolkit/
# But use CLAUDE_PROJECT_DIR if available
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
  PROJECT_DIR="$(cd "$TOOLKIT_DIR/../.." && pwd)"
fi

CLAUDE_DIR="${PROJECT_DIR}/.claude"
MANIFEST_PATH="${CLAUDE_DIR}/toolkit-manifest.json"

# Source manifest functions
# shellcheck source=lib/manifest.sh
source "${TOOLKIT_DIR}/lib/manifest.sh"

# ============================================================================
# Helpers
# ============================================================================

_info() { echo "  [info] $*"; }
_warn() { echo "  [warn] $*" >&2; }
_error() { echo "  [error] $*" >&2; }
_ok() { echo "  [ok] $*"; }

_require_jq() {
  if ! command -v jq &>/dev/null; then
    _error "jq is required. Install with: brew install jq"
    return 1
  fi
}

_require_python3() {
  if ! command -v python3 &>/dev/null; then
    _error "python3 is required."
    return 1
  fi
}

_require_toml() {
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  if [[ ! -f "$toml_file" ]]; then
    _error "toolkit.toml not found at ${toml_file}"
    echo ""
    echo "  Create one with:"
    echo "    cp ${TOOLKIT_DIR}/templates/toolkit.toml.example ${toml_file}"
    echo ""
    echo "  Or run: $0 init --from-example"
    return 1
  fi
}

_read_toml_value() {
  # Simple TOML value reader using python3
  # Usage: _read_toml_value <file> <dotted.key>
  local file="$1"
  local key="$2"
  python3 -c "
import tomllib, sys
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
keys = sys.argv[2].split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(1)
if isinstance(val, list):
    for item in val:
        print(item)
else:
    print(val)
" "$file" "$key" 2>/dev/null
}

_read_toml_array() {
  # Read a TOML array as newline-separated values
  _read_toml_value "$1" "$2"
}

# ============================================================================
# init
# ============================================================================

cmd_init() {
  local force=false
  local from_example=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      --from-example) from_example=true; shift ;;
      *) _error "Unknown option: $1"; return 1 ;;
    esac
  done

  _require_jq || return 1
  _require_python3 || return 1

  echo "Initializing claude-toolkit in ${PROJECT_DIR}..."
  echo ""

  # Ensure .claude directory exists
  mkdir -p "$CLAUDE_DIR"

  # Handle toolkit.toml
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
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

  # --- Symlink agents ---
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

  # --- Copy skills ---
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

  # --- Symlink generic rules ---
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

  # --- Copy rule templates based on stacks ---
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
        # python.md.template -> python stack
        # swift.md.template -> ios stack
        # typescript.md.template -> typescript stack
        # testing-pytest.md.template -> python stack
        # testing-jest.md.template -> typescript stack
        # api-routes-fastapi.md.template -> python stack
        # database-sqlite.md.template -> python stack (generic)
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
          sed "s/{{PROJECT_NAME}}/${project_name}/g" "$template_file" > "$target"
          _ok "Created rules/${rule_name} from template (stack: ${stack})"
        fi
      done
    done <<< "$stacks"
  fi

  # --- Create agent-memory directory ---
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

  # --- Create git remote ---
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

  # --- Generate config cache ---
  echo ""
  echo "Generating configuration..."
  cmd_generate_settings_inner || {
    _error "Settings generation failed. Fix toolkit.toml before continuing."
    return 1
  }

  # --- Create manifest ---
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
          jq --arg name "$agent_name" \
            '.agents[$name].status = "copy-managed"' \
            "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp"
          mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"
        fi
      fi
    fi
  done

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
# update
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
    jq --arg hash "$merge_hash" '.last_subtree_merge = $hash' "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp"
    mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"
  fi

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
    jq --arg v "$new_version" '.toolkit_version = $v' "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp"
    mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"
  fi

  echo ""
  _ok "Toolkit updated to ${ref}"
}

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
# customize
# ============================================================================

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

# ============================================================================
# status
# ============================================================================

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

# ============================================================================
# validate
# ============================================================================

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

  # Check all symlinks resolve
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
  if [[ $broken_links -eq 0 ]]; then
    _ok "All symlinks resolve"
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

# ============================================================================
# generate-settings
# ============================================================================

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
  # shellcheck disable=SC2086
  python3 "${TOOLKIT_DIR}/generate-settings.py" \
    --base "${TOOLKIT_DIR}/templates/settings-base.json" \
    $stacks_args \
    $project_args \
    --output "${CLAUDE_DIR}/settings.json" \
    $mcp_args || {
    _error "Failed to generate settings.json"
    return 1
  }
  _ok "Generated settings.json"

  if [[ -n "$mcp_args" ]]; then
    _ok "Generated .mcp.json"
  fi
}

cmd_generate_settings() {
  echo "Regenerating settings..."
  echo ""
  cmd_generate_settings_inner
  echo ""
  _ok "Settings regenerated successfully"
}

# ============================================================================
# help
# ============================================================================

cmd_help() {
  echo "claude-toolkit CLI"
  echo ""
  echo "Usage: $0 <subcommand> [options]"
  echo ""
  echo "Subcommands:"
  echo "  init [--force] [--from-example]   Initialize toolkit in project"
  echo "  update [version] [--latest] [--force]  Update toolkit from remote"
  echo "  customize <path>                  Convert managed file to customized"
  echo "  status                            Show toolkit status"
  echo "  validate                          Check toolkit health"
  echo "  generate-settings                 Regenerate settings.json and .mcp.json"
  echo "  help                              Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 init                     # Initialize (requires toolkit.toml)"
  echo "  $0 init --from-example      # Initialize with example toolkit.toml"
  echo "  $0 update                   # Update to latest tagged release"
  echo "  $0 update v1.2.0            # Update to specific version"
  echo "  $0 update --latest          # Update to latest main"
  echo "  $0 customize agents/reviewer.md  # Customize an agent"
  echo "  $0 status                   # Show current status"
  echo "  $0 validate                 # Check for issues"
  echo "  $0 generate-settings        # Regenerate config files"
}

# ============================================================================
# Main dispatch
# ============================================================================

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    init)               cmd_init "$@" ;;
    update)             cmd_update "$@" ;;
    customize)          cmd_customize "$@" ;;
    status)             cmd_status ;;
    validate)           cmd_validate ;;
    generate-settings)  cmd_generate_settings ;;
    help|--help|-h)     cmd_help ;;
    *)
      _error "Unknown command: $cmd"
      echo ""
      cmd_help
      return 1
      ;;
  esac
}

main "$@"
