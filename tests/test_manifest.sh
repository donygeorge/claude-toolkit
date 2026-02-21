#!/usr/bin/env bash
# test_manifest.sh — Tests for lib/manifest.sh functions
#
# Usage: bash tests/test_manifest.sh
# Exit: 0 on success, 1 on failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
TMPDIR=""

# ============================================================================
# Test framework
# ============================================================================

cleanup() {
  if [[ -n "$TMPDIR" ]] && [[ -d "$TMPDIR" ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

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

assert_json_value() {
  local desc="$1" file="$2" jq_expr="$3" expected="$4"
  local actual
  actual=$(jq -r "$jq_expr" "$file" 2>/dev/null || echo "JQ_ERROR")
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

# ============================================================================
# Test: manifest_init creates valid JSON
# ============================================================================

test_manifest_init() {
  echo ""
  echo "=== Test: manifest_init ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  manifest_init "$project_dir" >/dev/null 2>&1

  local manifest="${project_dir}/toolkit-manifest.json"

  assert_file_exists "manifest file created" "$manifest"
  assert_json_valid "manifest is valid JSON" "$manifest"

  # Check structure
  local expected_version
  expected_version=$(cat "${TOOLKIT_SRC}/VERSION" | tr -d '[:space:]')
  assert_json_value "has toolkit_version" "$manifest" '.toolkit_version' "$expected_version"
  assert_json_value "has generated_at" "$manifest" '.generated_at | length > 0' "true"
  assert_json_value "has agents object" "$manifest" '.agents | type' "object"
  assert_json_value "has skills object" "$manifest" '.skills | type' "object"
  assert_json_value "has rules object" "$manifest" '.rules | type' "object"

  # Check agents are discovered
  local agent_count
  agent_count=$(jq '.agents | length' "$manifest")
  if [[ "$agent_count" -gt 0 ]]; then
    echo "  PASS: agents discovered ($agent_count)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no agents discovered"
    FAIL=$((FAIL + 1))
  fi

  # Check skills are discovered
  local skill_count
  skill_count=$(jq '.skills | length' "$manifest")
  if [[ "$skill_count" -gt 0 ]]; then
    echo "  PASS: skills discovered ($skill_count)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no skills discovered"
    FAIL=$((FAIL + 1))
  fi

  # Check agent status is "managed"
  assert_json_value "agent status is managed" "$manifest" '.agents["reviewer.md"].status' "managed"

  # Check agent has toolkit_hash
  local hash
  hash=$(jq -r '.agents["reviewer.md"].toolkit_hash // "missing"' "$manifest")
  if [[ "$hash" != "missing" ]] && [[ "$hash" != "null" ]] && [[ ${#hash} -gt 5 ]]; then
    echo "  PASS: agent has toolkit_hash"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: agent missing toolkit_hash"
    FAIL=$((FAIL + 1))
  fi

  # Check skill has toolkit_hash (Fix #2: skill drift tracking)
  local skill_name
  skill_name=$(jq -r '.skills | keys[0]' "$manifest")
  if [[ -n "$skill_name" ]] && [[ "$skill_name" != "null" ]]; then
    local skill_hash
    skill_hash=$(jq -r --arg name "$skill_name" '.skills[$name].toolkit_hash // "missing"' "$manifest")
    if [[ "$skill_hash" != "missing" ]] && [[ "$skill_hash" != "null" ]] && [[ ${#skill_hash} -gt 5 ]]; then
      echo "  PASS: skill has toolkit_hash"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: skill missing toolkit_hash (got: $skill_hash)"
      FAIL=$((FAIL + 1))
    fi
  fi
}

# ============================================================================
# Test: manifest_customize marks file
# ============================================================================

test_manifest_customize() {
  echo ""
  echo "=== Test: manifest_customize ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create manifest first
  manifest_init "$project_dir" >/dev/null 2>&1
  local manifest="${project_dir}/toolkit-manifest.json"

  # Customize an agent
  manifest_customize "agents/reviewer.md" "$project_dir" >/dev/null 2>&1

  assert_json_value "status changed to customized" "$manifest" '.agents["reviewer.md"].status' "customized"

  local customized_at
  customized_at=$(jq -r '.agents["reviewer.md"].customized_at // "missing"' "$manifest")
  if [[ "$customized_at" != "missing" ]] && [[ "$customized_at" != "null" ]]; then
    echo "  PASS: customized_at timestamp set"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: customized_at timestamp missing"
    FAIL=$((FAIL + 1))
  fi

  # Customize a skill
  manifest_customize "skills/implement" "$project_dir" >/dev/null 2>&1
  assert_json_value "skill status changed to customized" "$manifest" '.skills["implement"].status' "customized"
}

# ============================================================================
# Test: manifest_customize rejects invalid paths
# ============================================================================

test_manifest_customize_invalid_path() {
  echo ""
  echo "=== Test: manifest_customize invalid path ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  manifest_init "$project_dir" >/dev/null 2>&1

  # Invalid path should fail
  local result=0
  manifest_customize "invalid/path.md" "$project_dir" &>/dev/null || result=$?
  assert_eq "invalid path returns error" "1" "$result"
}

# ============================================================================
# Test: manifest_check_drift detects changes
# ============================================================================

test_manifest_check_drift() {
  echo ""
  echo "=== Test: manifest_check_drift ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create manifest
  manifest_init "$project_dir" >/dev/null 2>&1

  # No drift expected initially
  local output
  output=$(manifest_check_drift "$project_dir" 2>&1)
  if echo "$output" | grep -q "No drift detected"; then
    echo "  PASS: no drift detected initially"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: unexpected drift detected initially"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi

  # Simulate drift: mark agent as customized, then change toolkit hash in manifest
  manifest_customize "agents/reviewer.md" "$project_dir" >/dev/null 2>&1

  # Change the recorded toolkit_hash to simulate upstream change
  local manifest="${project_dir}/toolkit-manifest.json"
  jq '.agents["reviewer.md"].toolkit_hash = "fake-old-hash"' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"

  # Now check drift — should detect
  output=$(manifest_check_drift "$project_dir" 2>&1)
  if echo "$output" | grep -q "DRIFT"; then
    echo "  PASS: drift detected after simulated upstream change"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: drift not detected"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test: manifest_check_drift detects skill drift (Fix #2)
# ============================================================================

test_manifest_check_skill_drift() {
  echo ""
  echo "=== Test: manifest_check_drift detects skill drift ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create manifest
  manifest_init "$project_dir" >/dev/null 2>&1

  # Get the first skill name
  local manifest="${project_dir}/toolkit-manifest.json"
  local skill_name
  skill_name=$(jq -r '.skills | keys[0]' "$manifest")

  if [[ -z "$skill_name" ]] || [[ "$skill_name" == "null" ]]; then
    echo "  SKIP: no skills found"
    return
  fi

  # Mark skill as customized
  manifest_customize "skills/${skill_name}" "$project_dir" >/dev/null 2>&1

  # Change the recorded toolkit_hash to simulate upstream change
  jq --arg name "$skill_name" '.skills[$name].toolkit_hash = "fake-old-hash"' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"

  # Now check drift — should detect skill drift
  local output
  output=$(manifest_check_drift "$project_dir" 2>&1)
  if echo "$output" | grep -q "DRIFT.*skills/${skill_name}"; then
    echo "  PASS: skill drift detected"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: skill drift not detected"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test: manifest_revert_all_drifted bulk reverts (Fix #4)
# ============================================================================

test_manifest_revert_all_drifted() {
  echo ""
  echo "=== Test: manifest_revert_all_drifted ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create manifest
  manifest_init "$project_dir" >/dev/null 2>&1

  local manifest="${project_dir}/toolkit-manifest.json"

  # Mark an agent as customized and simulate drift
  manifest_customize "agents/reviewer.md" "$project_dir" >/dev/null 2>&1
  jq '.agents["reviewer.md"].toolkit_hash = "fake-old-hash"' "$manifest" > "${manifest}.tmp"
  mv "${manifest}.tmp" "$manifest"

  # Create the claude dir structure (simulating a real project)
  local claude_dir="${project_dir}/.claude"
  mkdir -p "${claude_dir}/agents"
  mkdir -p "${claude_dir}/toolkit"
  # Create a fake toolkit dir link for the revert to work
  ln -sf "$TOOLKIT_SRC" "${claude_dir}/toolkit" 2>/dev/null || cp -r "$TOOLKIT_SRC/agents" "${claude_dir}/toolkit/"

  # Create a customized agent file
  echo "# customized content" > "${claude_dir}/agents/reviewer.md"

  # Run revert all
  local output
  output=$(manifest_revert_all_drifted "$project_dir" "$claude_dir" 2>&1)
  if echo "$output" | grep -q "Reverted.*agents/reviewer.md"; then
    echo "  PASS: agent reverted"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: agent not reverted"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi

  # Check manifest status is back to "managed"
  local status
  status=$(jq -r '.agents["reviewer.md"].status' "$manifest")
  if [[ "$status" == "managed" ]]; then
    echo "  PASS: status reverted to managed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: status is '$status', expected 'managed'"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================================
# Test: manifest_update_skill skips customized
# ============================================================================

test_manifest_update_skill_skips_customized() {
  echo ""
  echo "=== Test: manifest_update_skill skips customized ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir/.claude/skills/implement"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create manifest and customize a skill
  manifest_init "$project_dir" >/dev/null 2>&1
  manifest_customize "skills/implement" "$project_dir" >/dev/null 2>&1

  # Create a modified skill file
  echo "custom content" > "${project_dir}/.claude/skills/implement/SKILL.md"

  # Update should skip it
  local output
  output=$(manifest_update_skill "implement" "$project_dir" 2>&1)
  if echo "$output" | grep -q "customized"; then
    echo "  PASS: update skips customized skill"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: update did not skip customized skill"
    echo "    Output: $output"
    FAIL=$((FAIL + 1))
  fi

  # Verify content was NOT overwritten
  local content
  content=$(cat "${project_dir}/.claude/skills/implement/SKILL.md")
  assert_eq "content preserved" "custom content" "$content"
}

# ============================================================================
# Test: manifest_customize recovers from corrupted manifest
# ============================================================================

test_manifest_corruption_recovery() {
  echo ""
  echo "=== Test: manifest corruption recovery ==="

  TMPDIR=$(mktemp -d)
  local project_dir="${TMPDIR}/project"
  mkdir -p "$project_dir"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  # Create a valid manifest first
  manifest_init "$project_dir" >/dev/null 2>&1
  local manifest="${project_dir}/toolkit-manifest.json"

  assert_file_exists "manifest created" "$manifest"
  assert_json_valid "manifest is valid before corruption" "$manifest"

  # Corrupt the manifest
  echo "not valid json {{{" > "$manifest"

  # _validate_manifest should detect corruption
  local result=0
  _validate_manifest "$manifest" 2>/dev/null || result=$?
  assert_eq "_validate_manifest returns 1 for corrupted file" "1" "$result"

  # Check backup was created
  local backup_found=false
  for f in "${manifest}.corrupted."*; do
    if [[ -f "$f" ]]; then
      backup_found=true
      break
    fi
  done
  if [[ "$backup_found" == true ]]; then
    echo "  PASS: corrupted manifest backup created"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no backup of corrupted manifest"
    FAIL=$((FAIL + 1))
  fi

  # manifest_customize should recover from corruption
  manifest_customize "agents/reviewer.md" "$project_dir" >/dev/null 2>&1
  assert_json_valid "manifest recovered after corruption" "$manifest"
  assert_json_value "agent status is customized after recovery" "$manifest" '.agents["reviewer.md"].status' "customized"
}

# ============================================================================
# Test: _validate_manifest with missing file
# ============================================================================

test_validate_manifest_missing() {
  echo ""
  echo "=== Test: _validate_manifest with missing file ==="

  TMPDIR=$(mktemp -d)
  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  local result=0
  _validate_manifest "${TMPDIR}/nonexistent.json" 2>/dev/null || result=$?
  assert_eq "_validate_manifest returns 1 for missing file" "1" "$result"
}

# ============================================================================
# Test: _validate_manifest with valid file
# ============================================================================

test_validate_manifest_valid() {
  echo ""
  echo "=== Test: _validate_manifest with valid file ==="

  TMPDIR=$(mktemp -d)
  local valid_json="${TMPDIR}/valid.json"
  echo '{"key": "value"}' > "$valid_json"

  export TOOLKIT_ROOT="$TOOLKIT_SRC"
  source "${TOOLKIT_SRC}/lib/manifest.sh"

  local result=0
  _validate_manifest "$valid_json" 2>/dev/null || result=$?
  assert_eq "_validate_manifest returns 0 for valid file" "0" "$result"
}

# ============================================================================
# Run all tests
# ============================================================================

echo "Running manifest.sh tests..."
echo "Toolkit source: ${TOOLKIT_SRC}"

test_manifest_init
test_manifest_customize
test_manifest_customize_invalid_path
test_manifest_check_drift
test_manifest_check_skill_drift
test_manifest_revert_all_drifted
test_manifest_update_skill_skips_customized
test_manifest_corruption_recovery
test_validate_manifest_missing
test_validate_manifest_valid

echo ""
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
