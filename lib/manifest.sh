#!/usr/bin/env bash
# Manifest system for claude-toolkit
# Tracks managed agents, skills, rules, and their customization status.
#
# Usage: Source this file from toolkit.sh or use directly:
#   source lib/manifest.sh
#   manifest_init
#   manifest_check_drift

set -euo pipefail

# Resolve toolkit root (relative to this file)
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST_FILE="toolkit-manifest.json"

# ============================================================================
# Helpers
# ============================================================================

_require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required for manifest operations. Install with: brew install jq" >&2
    return 1
  fi
}

_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_toolkit_version() {
  local version_file="${TOOLKIT_ROOT}/VERSION"
  if [[ -f "$version_file" ]]; then
    cat "$version_file" | tr -d '[:space:]'
  else
    echo "unknown"
  fi
}

_file_hash() {
  # Returns md5 hash of a file for change detection
  local file="$1"
  if [[ -f "$file" ]]; then
    if command -v md5sum &>/dev/null; then
      md5sum "$file" | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
      md5 -q "$file"
    else
      echo "no-hash-tool"
    fi
  else
    echo "file-missing"
  fi
}

# ============================================================================
# manifest_init
# ============================================================================

manifest_init() {
  # Creates initial toolkit-manifest.json listing all managed agents, skills, rules.
  # Run from the project root (where .claude/ lives) or pass project dir as $1.
  local project_dir="${1:-.}"
  local manifest_path="${project_dir}/${MANIFEST_FILE}"

  _require_jq || return 1

  local version
  version=$(_toolkit_version)
  local timestamp
  timestamp=$(_timestamp)

  # Discover agents
  local agents_json="{}"
  if [[ -d "${TOOLKIT_ROOT}/agents" ]]; then
    for agent_file in "${TOOLKIT_ROOT}"/agents/*.md; do
      [[ -f "$agent_file" ]] || continue
      local agent_name
      agent_name=$(basename "$agent_file")
      local hash
      hash=$(_file_hash "$agent_file")
      agents_json=$(echo "$agents_json" | jq --arg name "$agent_name" --arg hash "$hash" \
        '. + {($name): {"status": "managed", "toolkit_hash": $hash}}')
    done
  fi

  # Discover skills
  local skills_json="{}"
  if [[ -d "${TOOLKIT_ROOT}/skills" ]]; then
    for skill_dir in "${TOOLKIT_ROOT}"/skills/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name=$(basename "$skill_dir")
      local files_arr="[]"
      for f in "$skill_dir"*; do
        [[ -f "$f" ]] || continue
        local fname
        fname=$(basename "$f")
        files_arr=$(echo "$files_arr" | jq --arg f "$fname" '. + [$f]')
      done
      # Check for project-specific files (like features.json in scope-resolver)
      local project_files="[]"
      skills_json=$(echo "$skills_json" | jq \
        --arg name "$skill_name" \
        --argjson files "$files_arr" \
        --argjson pfiles "$project_files" \
        '. + {($name): {"status": "managed", "files": $files, "project_files": $pfiles}}')
    done
  fi

  # Discover rules
  local rules_json="{}"
  if [[ -d "${TOOLKIT_ROOT}/rules" ]]; then
    for rule_file in "${TOOLKIT_ROOT}"/rules/*.md; do
      [[ -f "$rule_file" ]] || continue
      local rule_name
      rule_name=$(basename "$rule_file")
      local hash
      hash=$(_file_hash "$rule_file")
      rules_json=$(echo "$rules_json" | jq --arg name "$rule_name" --arg hash "$hash" \
        '. + {($name): {"status": "managed", "toolkit_hash": $hash}}')
    done
  fi

  # Build manifest
  local manifest
  manifest=$(jq -n \
    --arg version "$version" \
    --arg generated "$timestamp" \
    --argjson agents "$agents_json" \
    --argjson skills "$skills_json" \
    --argjson rules "$rules_json" \
    '{
      toolkit_version: $version,
      generated_at: $generated,
      last_subtree_merge: "",
      agents: $agents,
      skills: $skills,
      rules: $rules
    }')

  echo "$manifest" > "$manifest_path"
  echo "Manifest created: $manifest_path"
  echo "  Agents: $(echo "$agents_json" | jq 'length')"
  echo "  Skills: $(echo "$skills_json" | jq 'length')"
  echo "  Rules: $(echo "$rules_json" | jq 'length')"
}

# ============================================================================
# manifest_customize
# ============================================================================

manifest_customize() {
  # Marks a file as "customized" with timestamp.
  # Usage: manifest_customize <path-within-manifest>
  # Example: manifest_customize agents/reviewer.md
  local path="$1"
  local project_dir="${2:-.}"
  local manifest_path="${project_dir}/${MANIFEST_FILE}"

  _require_jq || return 1

  if [[ ! -f "$manifest_path" ]]; then
    echo "Error: Manifest not found at $manifest_path. Run manifest_init first." >&2
    return 1
  fi

  local timestamp
  timestamp=$(_timestamp)

  # Determine section (agents, skills, rules) and key
  local section=""
  local key=""
  if [[ "$path" == agents/* ]]; then
    section="agents"
    key=$(basename "$path")
  elif [[ "$path" == skills/* ]]; then
    section="skills"
    # Extract skill name (first directory component after skills/)
    key=$(echo "$path" | sed 's|skills/||' | cut -d'/' -f1)
  elif [[ "$path" == rules/* ]]; then
    section="rules"
    key=$(basename "$path")
  else
    echo "Error: Path must start with agents/, skills/, or rules/" >&2
    return 1
  fi

  # Update manifest
  local updated
  updated=$(jq --arg section "$section" --arg key "$key" --arg ts "$timestamp" \
    '.[$section][$key].status = "customized" | .[$section][$key].customized_at = $ts' \
    "$manifest_path")

  echo "$updated" > "$manifest_path"
  echo "Marked as customized: $section/$key (at $timestamp)"
}

# ============================================================================
# manifest_update_skill
# ============================================================================

manifest_update_skill() {
  # Compares a skill's files against toolkit source, updates if changed.
  # Usage: manifest_update_skill <skill_name> [project_dir]
  local skill_name="$1"
  local project_dir="${2:-.}"
  local manifest_path="${project_dir}/${MANIFEST_FILE}"

  _require_jq || return 1

  if [[ ! -f "$manifest_path" ]]; then
    echo "Error: Manifest not found. Run manifest_init first." >&2
    return 1
  fi

  local toolkit_skill_dir="${TOOLKIT_ROOT}/skills/${skill_name}"
  local project_skill_dir="${project_dir}/.claude/skills/${skill_name}"

  if [[ ! -d "$toolkit_skill_dir" ]]; then
    echo "Error: Skill '$skill_name' not found in toolkit at $toolkit_skill_dir" >&2
    return 1
  fi

  local status
  status=$(jq -r --arg name "$skill_name" '.skills[$name].status // "unknown"' "$manifest_path")

  if [[ "$status" == "customized" ]]; then
    echo "Warning: Skill '$skill_name' is marked as customized. Use --force to override." >&2
    return 0
  fi

  # Compare and copy files
  local updated=0
  for toolkit_file in "$toolkit_skill_dir"/*; do
    [[ -f "$toolkit_file" ]] || continue
    local fname
    fname=$(basename "$toolkit_file")
    local project_file="${project_skill_dir}/${fname}"

    if [[ ! -f "$project_file" ]] || ! diff -q "$toolkit_file" "$project_file" &>/dev/null; then
      mkdir -p "$project_skill_dir"
      cp "$toolkit_file" "$project_file"
      echo "  Updated: $skill_name/$fname"
      updated=1
    fi
  done

  if [[ $updated -eq 0 ]]; then
    echo "  Skill '$skill_name' is up to date."
  fi
}

# ============================================================================
# manifest_check_drift
# ============================================================================

manifest_check_drift() {
  # Detects customized files with upstream changes, warns about drift.
  # Usage: manifest_check_drift [project_dir]
  local project_dir="${1:-.}"
  local manifest_path="${project_dir}/${MANIFEST_FILE}"

  _require_jq || return 1

  if [[ ! -f "$manifest_path" ]]; then
    echo "Error: Manifest not found. Run manifest_init first." >&2
    return 1
  fi

  local drift_count=0

  echo "Checking for drift..."

  # Check agents
  local agent_names
  agent_names=$(jq -r '.agents | keys[]' "$manifest_path" 2>/dev/null || true)
  for agent in $agent_names; do
    local status
    status=$(jq -r --arg name "$agent" '.agents[$name].status' "$manifest_path")
    local toolkit_hash
    toolkit_hash=$(jq -r --arg name "$agent" '.agents[$name].toolkit_hash // ""' "$manifest_path")

    local current_toolkit_hash
    current_toolkit_hash=$(_file_hash "${TOOLKIT_ROOT}/agents/${agent}")

    if [[ "$status" == "customized" ]] && [[ "$toolkit_hash" != "$current_toolkit_hash" ]] && [[ "$current_toolkit_hash" != "file-missing" ]]; then
      echo "  DRIFT: agents/$agent (customized, but toolkit has newer version)"
      drift_count=$((drift_count + 1))
    fi
  done

  # Check rules
  local rule_names
  rule_names=$(jq -r '.rules | keys[]' "$manifest_path" 2>/dev/null || true)
  for rule in $rule_names; do
    local status
    status=$(jq -r --arg name "$rule" '.rules[$name].status' "$manifest_path")
    local toolkit_hash
    toolkit_hash=$(jq -r --arg name "$rule" '.rules[$name].toolkit_hash // ""' "$manifest_path")

    local current_toolkit_hash
    current_toolkit_hash=$(_file_hash "${TOOLKIT_ROOT}/rules/${rule}")

    if [[ "$status" == "customized" ]] && [[ "$toolkit_hash" != "$current_toolkit_hash" ]] && [[ "$current_toolkit_hash" != "file-missing" ]]; then
      echo "  DRIFT: rules/$rule (customized, but toolkit has newer version)"
      drift_count=$((drift_count + 1))
    fi
  done

  if [[ $drift_count -eq 0 ]]; then
    echo "  No drift detected."
  else
    echo ""
    echo "  $drift_count file(s) have upstream changes. Review and merge manually."
  fi

  return 0
}
