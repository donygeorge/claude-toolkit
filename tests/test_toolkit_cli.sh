#!/usr/bin/env bash
# test_toolkit_cli.sh — Integration tests for toolkit.sh
#
# Runs in a temporary directory, creates a mock project, and tests
# all major toolkit.sh subcommands.
#
# Usage: bash tests/test_toolkit_cli.sh
# Exit: 0 on success, 1 on failure

set -euo pipefail

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

# ============================================================================
# Test framework
# ============================================================================

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — file not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local desc="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — file unexpectedly exists: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_symlink() {
  local desc="$1" path="$2"
  if [[ -L "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — not a symlink: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_symlink() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]] && [[ ! -L "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — is a symlink or doesn't exist: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local desc="$1" path="$2"
  if [[ -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — directory not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" file="$2" pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — pattern '$pattern' not found in $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_valid() {
  local desc="$1" file="$2"
  if python3 -m json.tool "$file" &>/dev/null; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — not valid JSON: $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2"
  shift 2
  local actual=0
  "$@" &>/dev/null || actual=$?
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected exit $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_output_contains() {
  local desc="$1" pattern="$2"
  shift 2
  local output
  output=$("$@" 2>&1) || true
  if echo "$output" | grep -q "$pattern"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — pattern '$pattern' not found in output"
    echo "    Output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Setup: create a test project with toolkit copied in
# ============================================================================

# Array to track temp dirs for cleanup
ALL_TMPDIRS=()

cleanup() {
  if [[ ${#ALL_TMPDIRS[@]} -gt 0 ]]; then
    for d in "${ALL_TMPDIRS[@]}"; do
      [[ -d "$d" ]] && rm -rf "$d"
    done
  fi
}
trap cleanup EXIT

setup_test_project() {
  # Creates a temp project directory with toolkit files copied in
  # (not via subtree, since toolkit.sh may not be committed yet).
  # Sets PROJECT_DIR as a side effect, returns the path via stdout.
  local tmpdir
  tmpdir=$(mktemp -d)
  ALL_TMPDIRS+=("$tmpdir")

  local project_dir="${tmpdir}/test-project"
  mkdir -p "$project_dir"

  # Init git repo
  git -C "$project_dir" init --initial-branch=main >/dev/null 2>&1 || git -C "$project_dir" init >/dev/null 2>&1
  git -C "$project_dir" config user.email "test@test.com"
  git -C "$project_dir" config user.name "Test"

  # Create an initial commit
  touch "${project_dir}/README.md"
  git -C "$project_dir" add README.md
  git -C "$project_dir" commit -m "Initial commit" >/dev/null 2>&1

  # Copy toolkit source into .claude/toolkit/ (mimics subtree)
  mkdir -p "${project_dir}/.claude/toolkit"
  # Copy everything from TOOLKIT_SRC except .git, tests, __pycache__
  rsync -a --exclude='.git' --exclude='__pycache__' --exclude='tests' \
    "${TOOLKIT_SRC}/" "${project_dir}/.claude/toolkit/"

  # Commit the toolkit files
  git -C "$project_dir" add .claude/toolkit/
  git -C "$project_dir" commit -m "Add toolkit" >/dev/null 2>&1

  echo "$project_dir"
}

# ============================================================================
# Test: init with --from-example
# ============================================================================

test_init_from_example() {
  echo ""
  echo "=== Test: init --from-example ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Run init with --from-example
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Check toolkit.toml was created
  assert_file_exists "toolkit.toml created" "${project_dir}/.claude/toolkit.toml"

  # Check agents are symlinked
  assert_dir_exists "agents directory" "${project_dir}/.claude/agents"
  assert_symlink "reviewer.md is symlink" "${project_dir}/.claude/agents/reviewer.md"
  assert_symlink "qa.md is symlink" "${project_dir}/.claude/agents/qa.md"

  # Check skills are copied (not symlinked)
  assert_dir_exists "skills directory" "${project_dir}/.claude/skills"
  assert_dir_exists "implement skill copied" "${project_dir}/.claude/skills/implement"
  assert_file_exists "implement SKILL.md exists" "${project_dir}/.claude/skills/implement/SKILL.md"
  assert_not_symlink "implement SKILL.md is a copy" "${project_dir}/.claude/skills/implement/SKILL.md"

  # Check rules
  assert_dir_exists "rules directory" "${project_dir}/.claude/rules"
  assert_symlink "git-protocol.md is symlink" "${project_dir}/.claude/rules/git-protocol.md"

  # Check rule templates were applied (python stack from example)
  assert_file_exists "python.md rule from template" "${project_dir}/.claude/rules/python.md"
  assert_not_symlink "python.md is a copy (from template)" "${project_dir}/.claude/rules/python.md"

  # Check agent-memory
  assert_dir_exists "agent-memory directory" "${project_dir}/.claude/agent-memory"
  assert_file_exists "reviewer memory" "${project_dir}/.claude/agent-memory/reviewer/MEMORY.md"

  # Check generated files
  assert_file_exists "toolkit-cache.env generated" "${project_dir}/.claude/toolkit-cache.env"
  assert_file_exists "settings.json generated" "${project_dir}/.claude/settings.json"
  assert_json_valid "settings.json is valid JSON" "${project_dir}/.claude/settings.json"

  # Check manifest
  assert_file_exists "manifest created" "${project_dir}/.claude/toolkit-manifest.json"
  assert_json_valid "manifest is valid JSON" "${project_dir}/.claude/toolkit-manifest.json"
}

# ============================================================================
# Test: init fails without toolkit.toml
# ============================================================================

test_init_requires_toml() {
  echo ""
  echo "=== Test: init requires toolkit.toml ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # init without toolkit.toml should fail
  assert_exit_code "init fails without toolkit.toml" 1 bash "$toolkit_sh" init
}

# ============================================================================
# Test: init --force overwrites
# ============================================================================

test_init_force() {
  echo ""
  echo "=== Test: init --force ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # First init
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Modify an agent file (remove symlink, create regular file)
  rm "${project_dir}/.claude/agents/reviewer.md"
  echo "custom content" > "${project_dir}/.claude/agents/reviewer.md"
  assert_not_symlink "reviewer.md is now a regular file" "${project_dir}/.claude/agents/reviewer.md"

  # Re-init with --force should recreate symlink
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example --force) >/dev/null 2>&1
  assert_symlink "reviewer.md re-symlinked after --force" "${project_dir}/.claude/agents/reviewer.md"
}

# ============================================================================
# Test: validate
# ============================================================================

test_validate() {
  echo ""
  echo "=== Test: validate ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Validate should pass
  assert_exit_code "validate passes after init" 0 bash "$toolkit_sh" validate
}

# ============================================================================
# Test: validate catches broken symlinks
# ============================================================================

test_validate_broken_symlink() {
  echo ""
  echo "=== Test: validate catches broken symlinks ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Break a symlink by creating a dangling one
  rm "${project_dir}/.claude/agents/reviewer.md"
  ln -s "../toolkit/agents/nonexistent.md" "${project_dir}/.claude/agents/reviewer.md"

  # Validate should fail
  assert_exit_code "validate fails with broken symlink" 1 bash "$toolkit_sh" validate
}

# ============================================================================
# Test: validate catches missing toolkit.toml
# ============================================================================

test_validate_missing_toml() {
  echo ""
  echo "=== Test: validate catches missing toolkit.toml ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Remove toolkit.toml
  rm "${project_dir}/.claude/toolkit.toml"

  # Validate should fail
  assert_exit_code "validate fails without toolkit.toml" 1 bash "$toolkit_sh" validate
}

# ============================================================================
# Test: status shows version
# ============================================================================

test_status() {
  echo ""
  echo "=== Test: status ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Status should show toolkit version
  assert_output_contains "status shows version" "Toolkit version:" bash "$toolkit_sh" status
  assert_output_contains "status shows project" "Project:" bash "$toolkit_sh" status
}

# ============================================================================
# Test: generate-settings
# ============================================================================

test_generate_settings() {
  echo ""
  echo "=== Test: generate-settings ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Remove generated files
  rm -f "${project_dir}/.claude/settings.json"
  rm -f "${project_dir}/.claude/toolkit-cache.env"

  # Regenerate
  (cd "$project_dir" && bash "$toolkit_sh" generate-settings) >/dev/null 2>&1

  assert_file_exists "settings.json regenerated" "${project_dir}/.claude/settings.json"
  assert_json_valid "settings.json is valid JSON" "${project_dir}/.claude/settings.json"
  assert_file_exists "toolkit-cache.env regenerated" "${project_dir}/.claude/toolkit-cache.env"
}

# ============================================================================
# Test: customize converts symlink to copy
# ============================================================================

test_customize() {
  echo ""
  echo "=== Test: customize ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Verify reviewer.md starts as symlink
  assert_symlink "reviewer.md starts as symlink" "${project_dir}/.claude/agents/reviewer.md"

  # Customize it
  (cd "$project_dir" && bash "$toolkit_sh" customize agents/reviewer.md) >/dev/null 2>&1

  # Should now be a regular file
  assert_not_symlink "reviewer.md is now a regular file" "${project_dir}/.claude/agents/reviewer.md"
  assert_file_exists "reviewer.md still exists" "${project_dir}/.claude/agents/reviewer.md"

  # Manifest should show customized
  local status
  status=$(jq -r '.agents["reviewer.md"].status' "${project_dir}/.claude/toolkit-manifest.json")
  assert_eq "manifest shows customized" "customized" "$status"

  # Check customized_at timestamp exists
  local customized_at
  customized_at=$(jq -r '.agents["reviewer.md"].customized_at // "missing"' "${project_dir}/.claude/toolkit-manifest.json")
  if [[ "$customized_at" != "missing" ]] && [[ "$customized_at" != "null" ]]; then
    echo "  PASS: customized_at timestamp recorded"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: customized_at timestamp missing"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test: customize skill
# ============================================================================

test_customize_skill() {
  echo ""
  echo "=== Test: customize skill ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Customize a skill
  (cd "$project_dir" && bash "$toolkit_sh" customize skills/implement/SKILL.md) >/dev/null 2>&1

  # Manifest should show customized
  local status
  status=$(jq -r '.skills["implement"].status' "${project_dir}/.claude/toolkit-manifest.json")
  assert_eq "manifest shows skill customized" "customized" "$status"
}

# ============================================================================
# Test: help
# ============================================================================

test_help() {
  echo ""
  echo "=== Test: help ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  assert_output_contains "help shows init" "init" bash "$toolkit_sh" help
  assert_output_contains "help shows update" "update" bash "$toolkit_sh" help
  assert_output_contains "help shows customize" "customize" bash "$toolkit_sh" help
  assert_output_contains "help shows status" "status" bash "$toolkit_sh" help
  assert_output_contains "help shows validate" "validate" bash "$toolkit_sh" help
  assert_exit_code "help exits 0" 0 bash "$toolkit_sh" help
}

# ============================================================================
# Test: unknown command
# ============================================================================

test_unknown_command() {
  echo ""
  echo "=== Test: unknown command ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  assert_exit_code "unknown command exits 1" 1 bash "$toolkit_sh" nonexistent
}

# ============================================================================
# Test: MCP json generated
# ============================================================================

test_mcp_json() {
  echo ""
  echo "=== Test: .mcp.json generated ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  assert_file_exists ".mcp.json generated" "${project_dir}/.mcp.json"
  assert_json_valid ".mcp.json is valid JSON" "${project_dir}/.mcp.json"

  # Should have mcpServers
  local has_servers
  has_servers=$(python3 -c "import json; d=json.load(open('${project_dir}/.mcp.json')); print('yes' if 'mcpServers' in d else 'no')")
  assert_eq ".mcp.json has mcpServers" "yes" "$has_servers"
}

# ============================================================================
# Test: init --dry-run shows plan without mutating
# ============================================================================

test_init_dry_run() {
  echo ""
  echo "=== Test: init --dry-run ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Create toolkit.toml first (dry-run needs to read it)
  cp "${project_dir}/.claude/toolkit/templates/toolkit.toml.example" "${project_dir}/.claude/toolkit.toml"

  # Run init with --dry-run
  local output
  output=$(bash "$toolkit_sh" init --dry-run 2>&1)

  # Should say "dry-run"
  if echo "$output" | grep -qi "dry-run"; then
    echo "  PASS: dry-run output mentions dry-run"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: dry-run output doesn't mention dry-run"
    echo "    Output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi

  # Should mention what would be done
  if echo "$output" | grep -q "Would"; then
    echo "  PASS: dry-run shows what would happen"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: dry-run output doesn't show plans"
    FAIL=$((FAIL + 1))
  fi

  # Should NOT have created agents directory
  assert_file_not_exists "agents not created in dry-run" "${project_dir}/.claude/agents/reviewer.md"

  # Should NOT have created settings.json
  assert_file_not_exists "settings.json not created in dry-run" "${project_dir}/.claude/settings.json"

  # Should NOT have created manifest
  assert_file_not_exists "manifest not created in dry-run" "${project_dir}/.claude/toolkit-manifest.json"
}

# ============================================================================
# Test: init --dry-run via global flag
# ============================================================================

test_init_dry_run_global_flag() {
  echo ""
  echo "=== Test: init --dry-run (global flag) ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Create toolkit.toml first
  cp "${project_dir}/.claude/toolkit/templates/toolkit.toml.example" "${project_dir}/.claude/toolkit.toml"

  # Run with --dry-run as global flag (before subcommand)
  local output
  output=$(bash "$toolkit_sh" --dry-run init 2>&1)

  if echo "$output" | grep -qi "dry-run"; then
    echo "  PASS: global --dry-run flag works"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: global --dry-run flag not recognized"
    echo "    Output: $(echo "$output" | head -5)"
    FAIL=$((FAIL + 1))
  fi

  # Should NOT have mutated
  assert_file_not_exists "no mutation with global dry-run" "${project_dir}/.claude/settings.json"
}

# ============================================================================
# Test: generate-settings --dry-run
# ============================================================================

test_generate_settings_dry_run() {
  echo ""
  echo "=== Test: generate-settings --dry-run ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init normally first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Remove generated files
  rm -f "${project_dir}/.claude/settings.json"
  rm -f "${project_dir}/.claude/toolkit-cache.env"

  # Run generate-settings with --dry-run
  local output
  output=$(bash "$toolkit_sh" --dry-run generate-settings 2>&1)

  if echo "$output" | grep -qi "dry-run"; then
    echo "  PASS: generate-settings dry-run output correct"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: generate-settings dry-run missing indicator"
    FAIL=$((FAIL + 1))
  fi

  # Files should NOT be regenerated
  assert_file_not_exists "settings.json not regenerated in dry-run" "${project_dir}/.claude/settings.json"
}

# ============================================================================
# Test: doctor command exists
# ============================================================================

test_doctor() {
  echo ""
  echo "=== Test: doctor ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # Init first
  (cd "$project_dir" && bash "$toolkit_sh" init --from-example) >/dev/null 2>&1

  # Doctor should run and succeed
  assert_exit_code "doctor exits 0 after init" 0 bash "$toolkit_sh" doctor
  assert_output_contains "doctor shows health check" "health check" bash "$toolkit_sh" doctor
}

# ============================================================================
# Test: explain command
# ============================================================================

test_explain() {
  echo ""
  echo "=== Test: explain ==="

  local project_dir
  project_dir=$(setup_test_project)
  local toolkit_sh="${project_dir}/.claude/toolkit/toolkit.sh"

  # explain with no args shows overview
  assert_output_contains "explain overview" "Claude Toolkit" bash "$toolkit_sh" explain
  assert_exit_code "explain exits 0" 0 bash "$toolkit_sh" explain

  # explain hooks
  assert_output_contains "explain hooks" "guard-destructive" bash "$toolkit_sh" explain hooks

  # explain agents
  assert_output_contains "explain agents" "reviewer.md" bash "$toolkit_sh" explain agents

  # explain skills
  assert_output_contains "explain skills" "/implement" bash "$toolkit_sh" explain skills

  # explain rules
  assert_output_contains "explain rules" "git-protocol" bash "$toolkit_sh" explain rules

  # explain config
  assert_output_contains "explain config" "toolkit.toml" bash "$toolkit_sh" explain config

  # explain stacks
  assert_output_contains "explain stacks" "python" bash "$toolkit_sh" explain stacks

  # explain unknown topic fails
  assert_exit_code "explain unknown topic exits 1" 1 bash "$toolkit_sh" explain nonexistent

  # help output mentions explain
  assert_output_contains "help shows explain" "explain" bash "$toolkit_sh" help
}

# ============================================================================
# Run all tests
# ============================================================================

echo "Running toolkit.sh CLI tests..."
echo "Toolkit source: ${TOOLKIT_SRC}"

test_init_from_example
test_init_requires_toml
test_init_force
test_validate
test_validate_broken_symlink
test_validate_missing_toml
test_status
test_generate_settings
test_customize
test_customize_skill
test_help
test_unknown_command
test_mcp_json
test_init_dry_run
test_init_dry_run_global_flag
test_generate_settings_dry_run
test_doctor
test_explain

echo ""
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
