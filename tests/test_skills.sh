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
WARNINGS=0
FAILED_NAMES=()
WARN_NAMES=()

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

# _warn — log a warning that does NOT cause test failure.
# Used for soft lint checks (line count, year refs, model names, etc.)
_warn() {
  WARNINGS=$((WARNINGS + 1))
  WARN_NAMES+=("$1")
  echo "WARN: $1"
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
  if grep -qE "^## (Usage|Internal Usage|Workflow|Execution Flow|Two Modes|Two-Tier Architecture|Overview)" "$skill_md"; then
    _pass
  else
    _fail "$skill_name: missing structural section (Usage, Internal Usage, Workflow, Execution Flow, Two Modes, Two-Tier Architecture, or Overview)"
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
# Symlink validation — every skills/*/ directory should have a corresponding
# entry in .claude/skills/ (symlink or copy). Missing entries mean the skill
# won't be discoverable by Claude Code.
# ============================================================================
echo "--- Skill symlink validation ---"

CLAUDE_SKILLS_DIR="$TOOLKIT_DIR/.claude/skills"

# Only run symlink check in the toolkit repo itself (not consuming projects).
# In consuming projects, skills are copied by `toolkit.sh init`, not symlinked.
if [ -f "$TOOLKIT_DIR/toolkit.sh" ] && [ -d "$CLAUDE_SKILLS_DIR" ]; then
  for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    _test "$skill_name: registered in .claude/skills/"
    if [ -e "$CLAUDE_SKILLS_DIR/$skill_name" ] || [ -L "$CLAUDE_SKILLS_DIR/$skill_name" ]; then
      _pass
    else
      _fail "$skill_name: missing from .claude/skills/ — skill won't be discoverable (run: ln -s ../../skills/$skill_name/ .claude/skills/$skill_name)"
    fi
  done
else
  echo "  (skipped — not in toolkit repo root or .claude/skills/ not found)"
fi

echo ""

# ============================================================================
# Skill quality lint checks
#
# These checks validate skill design quality patterns from the skill quality
# plan (docs/plans/toolkit-vs-superpowers.md). ERROR checks cause test failure;
# WARN checks log warnings but do NOT fail the test suite.
# ============================================================================

# ============================================================================
# Lint: Description Trap (ERROR)
#
# The Description Trap occurs when a skill description summarizes its workflow
# (e.g., "Commit changes...", "Display conventions...") instead of specifying
# when to invoke it. Claude may follow the short description instead of reading
# the full skill body, leading to shallow execution.
#
# Valid description patterns:
#   - "Use when..." (trigger condition)
#   - "Use after..." (trigger condition)
#   - "Internal skill..." (non-user-invocable)
# ============================================================================
echo "--- Lint: Description Trap (ERROR) ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  # Extract description from frontmatter
  frontmatter=$(sed -n '2,/^---$/p' "$skill_md" | sed '$d')
  desc=$(echo "$frontmatter" | grep "^description:" | sed 's/^description: *//' | sed 's/^["'"'"']//;s/["'"'"']$//')

  _test "$skill_name: description uses trigger format (not workflow)"
  if echo "$desc" | grep -qiE "^(Use when |Use after |Internal skill)"; then
    _pass
  else
    _fail "$skill_name: description trap — starts with '$desc' (must start with 'Use when', 'Use after', or 'Internal skill')"
  fi
done

echo ""

# ============================================================================
# Lint: Critical Rules presence (WARN)
#
# User-invocable skills should have a "Critical Rules" section that front-loads
# the most important instructions. This leverages the "Lost in the Middle"
# research — front-loaded critical information is more likely to be followed.
#
# Non-user-invocable skills (e.g., scope-resolver) are exempt.
# ============================================================================
echo "--- Lint: Critical Rules presence (WARN) ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  # Check if user-invocable
  frontmatter=$(sed -n '2,/^---$/p' "$skill_md" | sed '$d')
  invocable=$(echo "$frontmatter" | grep "^user-invocable:" | sed 's/^user-invocable: *//')

  if [ "$invocable" = "true" ]; then
    _test "$skill_name: has Critical Rules section"
    if grep -q "Critical Rules" "$skill_md"; then
      _pass
    else
      _warn "$skill_name: user-invocable skill missing 'Critical Rules' section"
    fi
  fi
done

echo ""

# ============================================================================
# Lint: Rationalization prevention (WARN)
#
# Judgment-heavy skills should have a "Rationalization" section to prevent the
# agent from rationalizing shortcuts. Skills that make complex judgment calls
# (solve, loop, review-suite, implement, plan, verify, fix) are checked.
#
# Exempt: utility skills (commit, conventions, scope-resolver) and toolkit
# management skills (toolkit-setup, toolkit-update, toolkit-doctor,
# toolkit-contribute) which follow deterministic workflows.
# ============================================================================
echo "--- Lint: Rationalization prevention (WARN) ---"

# Skills that should have rationalization prevention
JUDGMENT_SKILLS="solve loop review-suite implement plan verify fix"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  # Only check judgment-heavy skills
  is_judgment=false
  for js in $JUDGMENT_SKILLS; do
    if [ "$skill_name" = "$js" ]; then
      is_judgment=true
      break
    fi
  done

  if [ "$is_judgment" = "true" ]; then
    _test "$skill_name: has Rationalization section"
    if grep -q "Rationalization" "$skill_md"; then
      _pass
    else
      _warn "$skill_name: judgment-heavy skill missing 'Rationalization' section"
    fi
  fi
done

echo ""

# ============================================================================
# Lint: Line count budget (WARN)
#
# Soft targets by skill category. Skills exceeding their budget may need
# splitting (as was done with setup-toolkit -> 4 skills in M6).
#
# Categories:
#   - utility (<150): commit, conventions, scope-resolver
#   - workflow (<350): fix, solve
#   - orchestration (<600): implement, verify, plan, review-suite, loop,
#                           toolkit-setup, toolkit-update, toolkit-doctor,
#                           toolkit-contribute
#   - multi-mode (<1000): brainstorm
# ============================================================================
echo "--- Lint: Line count budget (WARN) ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")
  line_count=$(wc -l < "$skill_md" | tr -d ' ')

  # Determine budget based on category
  case "$skill_name" in
    commit|conventions|scope-resolver)
      budget=150
      category="utility"
      ;;
    fix|solve)
      budget=350
      category="workflow"
      ;;
    implement|verify|plan|review-suite|loop|toolkit-setup|toolkit-update|toolkit-doctor|toolkit-contribute)
      budget=600
      category="orchestration"
      ;;
    brainstorm)
      budget=1000
      category="multi-mode"
      ;;
    *)
      budget=600
      category="unknown"
      ;;
  esac

  _test "$skill_name: line count within $category budget (<$budget)"
  if [ "$line_count" -le "$budget" ]; then
    _pass
  else
    _warn "$skill_name: $line_count lines exceeds $category budget of $budget"
  fi
done

echo ""

# ============================================================================
# Lint: No hardcoded year references (WARN)
#
# Skills should use dynamic year references (e.g., "current year") instead of
# hardcoded years (e.g., "2025", "2026"). Hardcoded years become stale after
# model upgrades or calendar year changes.
#
# This is a whole-body grep that may flag years in examples or code blocks.
# WARN severity is appropriate since some legitimate uses exist.
# ============================================================================
echo "--- Lint: No hardcoded year references (WARN) ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  year_count=$(grep -cE '(201[0-9]|202[0-9])' "$skill_md" || true)

  _test "$skill_name: no hardcoded year references"
  if [ "$year_count" = "0" ]; then
    _pass
  else
    _warn "$skill_name: $year_count hardcoded year reference(s) found"
  fi
done

echo ""

# ============================================================================
# Lint: No hardcoded model names (WARN)
#
# Skills should avoid referencing specific model names (haiku, sonnet, opus)
# in body text. Model names may change with new releases. Instead, use tier
# descriptions (e.g., "fastest model", "most capable model") or config refs.
#
# This is a whole-body grep (case-insensitive) that may flag model names in
# frontmatter or selection tables. WARN severity is appropriate.
# ============================================================================
echo "--- Lint: No hardcoded model names (WARN) ---"

for skill_md in "$SKILLS_DIR"/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_md")")

  model_count=$(grep -ciE '\b(haiku|sonnet|opus)\b' "$skill_md" || true)

  _test "$skill_name: no hardcoded model name references"
  if [ "$model_count" = "0" ]; then
    _pass
  else
    _warn "$skill_name: $model_count model name reference(s) found (haiku/sonnet/opus)"
  fi
done

echo ""

# ============================================================================
# Summary
# ============================================================================
echo "=== Results ==="
echo "  Total:    $TESTS_RUN"
echo "  Passed:   $TESTS_PASSED"
echo "  Failed:   $TESTS_FAILED"
echo "  Warnings: $WARNINGS"
echo ""

if [ "$WARNINGS" -gt 0 ]; then
  echo "Warnings (non-blocking):"
  for name in "${WARN_NAMES[@]}"; do
    echo "  - $name"
  done
  echo ""
fi

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo "Failed tests:"
  for name in "${FAILED_NAMES[@]}"; do
    echo "  - $name"
  done
  echo ""
  exit 1
fi

echo "All tests passed ($WARNINGS warning(s))."
exit 0
