#!/usr/bin/env bash
# Skill structure validation tests for claude-toolkit
#
# Validates that every skill has correct frontmatter, required sections,
# companion files, and consistent formatting.
#
# Usage: bash tests/test_skills.sh
set -euo pipefail

# ============================================================================
# Test framework
# ============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

TOOLKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$TOOLKIT_DIR/skills"

_test() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "  TEST: %s ... " "$name"
}

_pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "PASS"
}

_fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_NAMES+=("$1")
  echo "FAIL: $1"
}

echo ""
echo "=== Skill Structure Tests ==="
echo "  Toolkit dir: $TOOLKIT_DIR"
echo "  Skills dir:  $SKILLS_DIR"
echo ""

# ============================================================================
# Frontmatter validation — every SKILL.md needs name, description,
# user-invocable fields in YAML frontmatter
# ============================================================================
echo "--- Frontmatter validation ---"

# Guard: ensure skills directory has SKILL.md files
skill_files=("$SKILLS_DIR"/*/SKILL.md)
if [ ! -f "${skill_files[0]}" ]; then
  _test "Skills directory has SKILL.md files"
  _fail "No SKILL.md files found in $SKILLS_DIR"
  echo ""
  echo "=== Results ==="
  echo "  Total:  $TESTS_RUN"
  echo "  Passed: $TESTS_PASSED"
  echo "  Failed: $TESTS_FAILED"
  exit 1
fi

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  # Check opening frontmatter delimiter
  _test "$skill_name: has YAML frontmatter opening"
  first_line=$(head -1 "$skill_md")
  if [ "$first_line" = "---" ]; then
    _pass
  else
    _fail "$skill_name: missing frontmatter (first line is not '---')"
  fi

  # Check closing frontmatter delimiter
  _test "$skill_name: has YAML frontmatter closing"
  # Count occurrences of --- (should be at least 2: opening + closing)
  delimiter_count=$(grep -c "^---$" "$skill_md" || true)
  if [ "$delimiter_count" -ge 2 ]; then
    _pass
  else
    _fail "$skill_name: missing closing frontmatter delimiter (found $delimiter_count '---' lines)"
  fi

  # Extract frontmatter (between first and second ---)
  frontmatter=$(sed -n '2,/^---$/p' "$skill_md" | sed '$d')

  # Check name field
  _test "$skill_name: has 'name' field"
  if echo "$frontmatter" | grep -q "^name:"; then
    _pass
  else
    _fail "$skill_name: missing 'name' field in frontmatter"
  fi

  # Check description field
  _test "$skill_name: has 'description' field"
  if echo "$frontmatter" | grep -q "^description:"; then
    _pass
  else
    _fail "$skill_name: missing 'description' field in frontmatter"
  fi

  # Check user-invocable field
  _test "$skill_name: has 'user-invocable' field"
  if echo "$frontmatter" | grep -q "^user-invocable:"; then
    _pass
  else
    _fail "$skill_name: missing 'user-invocable' field in frontmatter"
  fi
done

echo ""

# ============================================================================
# Structural section validation — every SKILL.md needs at least one
# recognized structural section
# ============================================================================
echo "--- Structural section validation ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  _test "$skill_name: has structural section"
  if grep -qE "^## (Usage|Workflow|Execution Flow|Two Modes|Two-Tier Architecture|Overview)" "$skill_md"; then
    _pass
  else
    _fail "$skill_name: missing structural section (Usage, Workflow, Execution Flow, Two Modes, Two-Tier Architecture, or Overview)"
  fi
done

echo ""

# ============================================================================
# Companion file validation
# ============================================================================
echo "--- Companion file validation ---"

_test "review-suite/output-schema.json exists"
if [ -f "$SKILLS_DIR/review-suite/output-schema.json" ]; then
  _pass
else
  _fail "review-suite/output-schema.json not found"
fi

_test "review-suite/output-schema.json is valid JSON"
if python3 -c "import json; json.load(open('$SKILLS_DIR/review-suite/output-schema.json'))" 2>/dev/null; then
  _pass
else
  _fail "review-suite/output-schema.json is not valid JSON"
fi

_test "implement/milestone-template.md exists"
if [ -f "$SKILLS_DIR/implement/milestone-template.md" ]; then
  _pass
else
  _fail "implement/milestone-template.md not found"
fi

echo ""

# ============================================================================
# Skill count validation
# ============================================================================
echo "--- Skill count validation ---"

_test "Skill directory count at least 15 (toolkit base)"
skill_count=0
for dir in "$SKILLS_DIR"/*/; do
  if [ -f "${dir}SKILL.md" ]; then
    skill_count=$((skill_count + 1))
  fi
done
if [ "$skill_count" -ge 15 ]; then
  _pass
else
  _fail "Expected at least 15 skills (toolkit base), found $skill_count"
fi

echo ""

# ============================================================================
# Timestamp consistency — no underscore-format timestamps in review-suite
# ============================================================================
echo "--- Timestamp consistency ---"

_test "No underscore timestamps in review-suite/SKILL.md"
match_count=$(grep -cE '[0-9]{8}_[0-9]{6}' "$SKILLS_DIR/review-suite/SKILL.md" 2>/dev/null || true)
if [ "$match_count" = "0" ]; then
  _pass
else
  _fail "Found $match_count underscore-format timestamp(s) in review-suite/SKILL.md"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "=== Results ==="
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo "Failed tests:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - $name"
  done
  echo ""
  exit 1
fi

echo "All tests passed."
exit 0
