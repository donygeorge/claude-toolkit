#!/usr/bin/env bash
# cmd-doctor.sh — Comprehensive toolkit health check
#
# Goes beyond `validate` by checking tool versions, hook health,
# config freshness, and potential compatibility issues.
#
# Sourced by toolkit.sh. Expects: TOOLKIT_DIR, PROJECT_DIR, CLAUDE_DIR,
# MANIFEST_PATH, and helper functions (_info, _warn, _error, _ok, etc.)

cmd_doctor() {
  local checks=0
  local passed=0
  local warnings=0
  local failures=0

  echo "Running toolkit health check..."
  echo ""

  # ---- 1. Required tools ----
  echo "Checking required tools..."
  checks=$((checks + 1))
  if command -v bash &>/dev/null; then
    _ok "bash found: $(bash --version | head -1)"
    passed=$((passed + 1))
  else
    _error "bash not found"
    failures=$((failures + 1))
  fi

  checks=$((checks + 1))
  if command -v jq &>/dev/null; then
    _ok "jq found: $(jq --version 2>&1)"
    passed=$((passed + 1))
  else
    _error "jq not found (install with: brew install jq)"
    failures=$((failures + 1))
  fi

  checks=$((checks + 1))
  if command -v python3 &>/dev/null; then
    _ok "python3 found: $(python3 --version 2>&1)"
    passed=$((passed + 1))
  else
    _error "python3 not found"
    failures=$((failures + 1))
  fi

  checks=$((checks + 1))
  if command -v git &>/dev/null; then
    _ok "git found: $(git --version 2>&1)"
    passed=$((passed + 1))
  else
    _error "git not found"
    failures=$((failures + 1))
  fi

  # ---- 2. Bash version ----
  echo ""
  echo "Checking bash version..."
  checks=$((checks + 1))
  local bash_major="${BASH_VERSINFO[0]}"
  if [[ "$bash_major" -ge 4 ]]; then
    _ok "Bash ${BASH_VERSION} (fully compatible)"
    passed=$((passed + 1))
  elif [[ "$bash_major" -ge 3 ]]; then
    _warn "Bash ${BASH_VERSION} (basic compatibility — some features may be limited)"
    warnings=$((warnings + 1))
  else
    _error "Bash ${BASH_VERSION} is too old (minimum: 3.2)"
    failures=$((failures + 1))
  fi

  # ---- 3. Python version ----
  checks=$((checks + 1))
  if command -v python3 &>/dev/null; then
    local py_version
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "unknown")
    local py_major py_minor
    py_major=$(echo "$py_version" | cut -d. -f1)
    py_minor=$(echo "$py_version" | cut -d. -f2)
    if [[ "$py_major" -ge 3 ]] && [[ "$py_minor" -ge 11 ]]; then
      _ok "Python ${py_version} (tomllib available)"
      passed=$((passed + 1))
    else
      _error "Python ${py_version} (requires 3.11+ for tomllib)"
      failures=$((failures + 1))
    fi
  else
    _error "python3 not found — cannot check version"
    failures=$((failures + 1))
  fi

  # ---- 4. Toolkit directory ----
  echo ""
  echo "Checking toolkit installation..."
  checks=$((checks + 1))
  if [[ -d "$TOOLKIT_DIR" ]]; then
    _ok "Toolkit directory: ${TOOLKIT_DIR}"
    passed=$((passed + 1))
  else
    _error "Toolkit directory not found: ${TOOLKIT_DIR}"
    failures=$((failures + 1))
  fi

  # ---- 5. Version file ----
  checks=$((checks + 1))
  local version_file="${TOOLKIT_DIR}/VERSION"
  if [[ -f "$version_file" ]]; then
    local version
    version=$(tr -d '[:space:]' < "$version_file")
    _ok "Toolkit version: ${version}"
    passed=$((passed + 1))
  else
    _warn "VERSION file not found"
    warnings=$((warnings + 1))
  fi

  # ---- 6. Config files ----
  echo ""
  echo "Checking configuration..."
  local toml_file="${CLAUDE_DIR}/toolkit.toml"
  checks=$((checks + 1))
  if [[ -f "$toml_file" ]]; then
    _ok "toolkit.toml exists"
    passed=$((passed + 1))
  else
    _error "toolkit.toml not found at ${toml_file}"
    failures=$((failures + 1))
  fi

  # ---- 7. Config cache freshness ----
  local cache_file="${CLAUDE_DIR}/toolkit-cache.env"
  checks=$((checks + 1))
  if [[ -f "$cache_file" ]]; then
    if [[ -f "$toml_file" ]] && [[ "$toml_file" -nt "$cache_file" ]]; then
      _warn "Config cache is stale (toolkit.toml newer than toolkit-cache.env)"
      _info "  Fix: Run '$0 generate-settings'"
      warnings=$((warnings + 1))
    else
      _ok "Config cache is fresh"
      passed=$((passed + 1))
    fi
  else
    _warn "Config cache not found (run 'generate-settings')"
    warnings=$((warnings + 1))
  fi

  # ---- 8. Settings.json freshness ----
  local settings_file="${CLAUDE_DIR}/settings.json"
  checks=$((checks + 1))
  if [[ -f "$settings_file" ]]; then
    if jq empty "$settings_file" 2>/dev/null; then
      _ok "settings.json is valid JSON"
      passed=$((passed + 1))
    else
      _error "settings.json is not valid JSON"
      failures=$((failures + 1))
    fi
  else
    _warn "settings.json not found (run 'generate-settings')"
    warnings=$((warnings + 1))
  fi

  # ---- 8b. Settings.json matches what generate-settings would produce ----
  checks=$((checks + 1))
  if [[ -f "$settings_file" ]] && [[ -f "$toml_file" ]] && command -v python3 &>/dev/null; then
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
        fi
      done <<< "$stacks"
      if [[ -n "$stack_files" ]]; then
        stacks_args="--stacks ${stack_files}"
      fi
    fi
    local project_args=""
    local project_file="${CLAUDE_DIR}/settings-project.json"
    if [[ -f "$project_file" ]]; then
      project_args="--project ${project_file}"
    fi
    local expected_output
    local gen_exit=0
    # shellcheck disable=SC2086
    expected_output=$(python3 "${TOOLKIT_DIR}/generate-settings.py" \
      --base "${TOOLKIT_DIR}/templates/settings-base.json" \
      $stacks_args \
      $project_args 2>/dev/null) || gen_exit=$?
    if [[ $gen_exit -ne 0 ]]; then
      _warn "generate-settings failed (exit ${gen_exit}) — settings may have validation errors"
      _info "  Fix: Run '$0 generate-settings' to see details"
      warnings=$((warnings + 1))
    elif [[ -n "$expected_output" ]]; then
      local current_output
      current_output=$(cat "$settings_file")
      if [[ "$expected_output" == "$current_output" ]]; then
        _ok "settings.json is up to date"
        passed=$((passed + 1))
      else
        _warn "settings.json differs from what generate-settings would produce"
        if [[ ! -f "$project_file" ]]; then
          _info "  No settings-project.json found — project-specific settings are at risk"
          _info "  Fix: cp .claude/settings.json .claude/settings-project.json && $0 generate-settings"
        else
          _info "  Fix: Run '$0 generate-settings'"
        fi
        warnings=$((warnings + 1))
      fi
    else
      _info "Could not verify settings.json freshness"
      passed=$((passed + 1))
    fi
  else
    _info "Skipping settings.json freshness check (missing prerequisites)"
    passed=$((passed + 1))
  fi

  # ---- 9. Symlink health ----
  echo ""
  echo "Checking symlinks..."

  # Read agent install list for filtering
  local agent_install_list=""
  local has_agents_config=false
  local agent_install_all=false
  local agent_install_none=false
  if [[ -f "$toml_file" ]]; then
    agent_install_list=$(_read_toml_array "$toml_file" "agents.install" 2>/dev/null || true)
    if [[ -n "$agent_install_list" ]]; then
      has_agents_config=true
      if printf '%s\n' "$agent_install_list" | grep -Fxq "all"; then
        agent_install_all=true
      elif printf '%s\n' "$agent_install_list" | grep -Fxq "none"; then
        agent_install_none=true
      fi
    fi
  fi

  local broken_count=0
  local total_links=0

  # Check agent symlinks — only for agents that should be installed
  for link in "${CLAUDE_DIR}"/agents/*.md; do
    [[ -L "$link" ]] || continue
    local link_name
    link_name=$(basename "$link")
    local link_base="${link_name%.md}"

    # If agents config exists, only count agents in the install list
    if [[ "$has_agents_config" == true ]] && [[ "$agent_install_all" != true ]]; then
      if [[ "$agent_install_none" == true ]]; then
        continue
      fi
      if ! printf '%s\n' "$agent_install_list" | grep -Fxq "$link_base"; then
        continue
      fi
    fi

    total_links=$((total_links + 1))
    if [[ ! -e "$link" ]]; then
      _error "Broken symlink: ${link#"${PROJECT_DIR}"/}"
      broken_count=$((broken_count + 1))
    fi
  done

  # Check rule symlinks
  for link in "${CLAUDE_DIR}"/rules/*.md; do
    [[ -L "$link" ]] || continue
    total_links=$((total_links + 1))
    if [[ ! -e "$link" ]]; then
      _error "Broken symlink: ${link#"${PROJECT_DIR}"/}"
      broken_count=$((broken_count + 1))
    fi
  done

  checks=$((checks + 1))
  if [[ $broken_count -eq 0 ]]; then
    if [[ $total_links -gt 0 ]]; then
      _ok "All ${total_links} symlinks resolve"
    else
      _info "No symlinks found (run 'init')"
    fi
    passed=$((passed + 1))
  else
    _error "${broken_count} broken symlink(s) found"
    _info "  Fix: Run '$0 init --force'"
    failures=$((failures + 1))
  fi

  # ---- 9b. Agent context budget ----
  echo ""
  echo "Checking agent context budget..."
  checks=$((checks + 1))
  local agent_count=0
  local agent_total_bytes=0
  local total_available=0
  # Count available agents from toolkit source
  for agent_src in "${TOOLKIT_DIR}"/agents/*.md; do
    [[ -f "$agent_src" ]] || continue
    total_available=$((total_available + 1))
  done
  # Sum sizes of installed agent files in .claude/agents/
  for agent_file in "${CLAUDE_DIR}"/agents/*.md; do
    [[ -f "$agent_file" || -L "$agent_file" ]] || continue
    [[ -e "$agent_file" ]] || continue  # skip broken symlinks
    agent_count=$((agent_count + 1))
    local file_size=0
    file_size=$(wc -c < "$agent_file" 2>/dev/null || echo 0)
    agent_total_bytes=$((agent_total_bytes + file_size))
  done
  # Convert to KB with one decimal place
  local agent_total_kb
  if [[ $agent_total_bytes -gt 0 ]]; then
    agent_total_kb=$(awk "BEGIN { printf \"%.1f\", $agent_total_bytes / 1024 }")
  else
    agent_total_kb="0.0"
  fi
  _ok "Agent context: ${agent_total_kb}KB (${agent_count} of ${total_available} agents installed)"
  if [[ $agent_total_bytes -gt 20480 ]]; then
    _warn "Agent context exceeds 20KB — consider reducing agents.install to save context"
    warnings=$((warnings + 1))
  else
    passed=$((passed + 1))
  fi

  # ---- 10. Manifest health ----
  echo ""
  echo "Checking manifest..."
  checks=$((checks + 1))
  if [[ -f "$MANIFEST_PATH" ]]; then
    if jq empty "$MANIFEST_PATH" 2>/dev/null; then
      _ok "Manifest is valid JSON"
      passed=$((passed + 1))
    else
      _error "Manifest is corrupted (not valid JSON)"
      _info "  Fix: Run '$0 init' to regenerate"
      failures=$((failures + 1))
    fi
  else
    _warn "Manifest not found (run 'init')"
    warnings=$((warnings + 1))
  fi

  # ---- 11. Hook executability ----
  echo ""
  echo "Checking hooks..."
  local hook_issues=0
  checks=$((checks + 1))
  for hook in "${TOOLKIT_DIR}"/hooks/*.sh; do
    [[ -f "$hook" ]] || continue
    local hook_name
    hook_name=$(basename "$hook")
    if [[ "$hook_name" == "_config.sh" ]]; then
      continue  # sourced library, not executable
    fi
    if [[ ! -x "$hook" ]]; then
      _warn "Hook not executable: ${hook_name}"
      hook_issues=$((hook_issues + 1))
    fi
  done
  if [[ $hook_issues -eq 0 ]]; then
    _ok "All hooks are executable"
    passed=$((passed + 1))
  else
    _warn "${hook_issues} hook(s) not executable"
    _info "  Fix: chmod +x hooks/*.sh"
    warnings=$((warnings + 1))
  fi

  # ---- 12. Hook health (sample input test) ----
  echo ""
  echo "Checking hook health..."
  local hook_health_issues=0
  checks=$((checks + 1))
  # Test guard-destructive with a safe command (should exit 0 = allow)
  local sample_input='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  local hook_file="${TOOLKIT_DIR}/hooks/guard-destructive.sh"
  if [[ -x "$hook_file" ]]; then
    local hook_exit=0
    echo "$sample_input" | CLAUDE_PROJECT_DIR="${PROJECT_DIR}" bash "$hook_file" >/dev/null 2>&1 || hook_exit=$?
    if [[ $hook_exit -eq 0 ]]; then
      _ok "guard-destructive.sh handles sample input correctly"
    else
      _warn "guard-destructive.sh returned exit code ${hook_exit} for safe input"
      hook_health_issues=$((hook_health_issues + 1))
    fi
  fi
  # Test auto-approve with a safe Read tool
  local approve_input='{"tool_name":"Read","tool_input":{"file_path":"README.md"}}'
  local approve_hook="${TOOLKIT_DIR}/hooks/auto-approve-safe.sh"
  if [[ -x "$approve_hook" ]]; then
    local approve_exit=0
    echo "$approve_input" | CLAUDE_PROJECT_DIR="${PROJECT_DIR}" bash "$approve_hook" >/dev/null 2>&1 || approve_exit=$?
    if [[ $approve_exit -eq 0 ]]; then
      _ok "auto-approve-safe.sh handles sample input correctly"
    else
      _warn "auto-approve-safe.sh returned exit code ${approve_exit} for Read input"
      hook_health_issues=$((hook_health_issues + 1))
    fi
  fi
  if [[ $hook_health_issues -eq 0 ]]; then
    passed=$((passed + 1))
  else
    warnings=$((warnings + 1))
  fi

  # ---- 13. Optional tools ----
  echo ""
  echo "Checking optional tools..."
  if command -v shellcheck &>/dev/null; then
    _ok "shellcheck found: $(shellcheck --version 2>&1 | grep '^version:' || echo 'available')"
  else
    _info "shellcheck not found (recommended for development)"
  fi

  if command -v rsync &>/dev/null; then
    _ok "rsync found"
  else
    _info "rsync not found (used by tests)"
  fi

  # ---- 14. MCP server dependencies ----
  echo ""
  echo "Checking MCP server dependencies..."
  if command -v npx &>/dev/null; then
    _ok "npx found (required for MCP servers: codex, context7, playwright)"
  else
    _warn "npx not found — MCP servers (codex, context7, playwright) will not work"
    _info "  Fix: Install Node.js (https://nodejs.org) or run: brew install node"
    warnings=$((warnings + 1))
  fi
  checks=$((checks + 1))

  # Check OPENAI_API_KEY for codex MCP
  checks=$((checks + 1))
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    _ok "OPENAI_API_KEY is set (required for codex MCP)"
    passed=$((passed + 1))
  else
    _warn "OPENAI_API_KEY not set — codex MCP may not authenticate"
    _info "  Fix: export OPENAI_API_KEY=<your-key>"
    warnings=$((warnings + 1))
  fi

  # ---- 15. Optional integrations ----
  echo ""
  echo "Checking optional integrations..."
  if command -v gemini &>/dev/null; then
    _ok "Gemini CLI found (used by agents/gemini.md and brainstorm --gemini)"
  else
    _info "Gemini CLI not found (optional — install: npm install -g @google/gemini-cli)"
  fi

  local mcp_json="${PROJECT_DIR}/.mcp.json"
  if [[ -f "$mcp_json" ]]; then
    if jq -e '.mcpServers.codex' "$mcp_json" &>/dev/null; then
      _ok "Codex MCP configured in .mcp.json"
    else
      _warn "Codex MCP not found in .mcp.json — run 'generate-settings' to add it from base"
      warnings=$((warnings + 1))
    fi
  else
    _info "No .mcp.json found (run 'generate-settings' to create)"
  fi

  # ---- Summary ----
  echo ""
  echo "==============================="
  echo "Health check: ${checks} checks, ${passed} passed, ${warnings} warning(s), ${failures} failure(s)"
  echo "==============================="

  if [[ $failures -gt 0 ]]; then
    return 1
  fi
  return 0
}
