# Toolkit vs Superpowers — Skill Quality Implementation Plan

> **Status**: In Review
>
> **Last Updated**: 2026-02-17
>
> **Source**: Idea exploration (`docs/ideas/toolkit-vs-superpowers.md`) + skill quality audit
>
> **Codex Iterations**: 6 of 10

## Summary

Improve the claude-toolkit's skill quality based on learnings from the superpowers framework. Addresses 8 priorities (P1-P8) from the idea exploration across 10 milestones (M0-M9): fix Description Trap violations (M0), standardize Critical Rules sections (M1), extend rationalization prevention (M2), improve upgrade resilience (M3), add TDD-first mode with full config stack (M4), add a spec-first review preset (M5), split the 2,158-line setup-toolkit into 4 focused skills (M6), create a skill quality linter (M7), build adversarial pressure tests (M8), and document skill design principles (M9).

## North Star

Every skill resists rationalization, front-loads critical rules, uses trigger-condition descriptions, and survives model upgrades without manual edits. The skill design guide codifies these patterns so future skills are born correct.

## Principles

1. **Fix what exists before adding new** — Description Trap and missing Critical Rules are the cheapest wins
2. **Concise over comprehensive** — Rationalization tables of 3-5 entries, not 15-row walls of text
3. **Config-driven over hardcoded** — Model names, TDD enforcement, and year references should be configurable or dynamic
4. **Test the methodology** — A skill linter catches structural regressions; pressure tests catch behavioral regressions
5. **Document for contributors** — The skill design guide prevents future quality gaps

## Research Findings

### Skill Quality Audit (Current State)

| Skill | Lines | Critical Rules | Rationalization Prevention | Description Trap |
|-------|-------|---------------|---------------------------|-----------------|
| verify | 499 | YES (5 rules) | YES (8-row table + forbidden language) | No |
| implement | 430 | YES (7 rules) | Partial (forbidden language only) | No |
| plan | 335 | YES (6 rules) | NO | No |
| brainstorm | 884 | YES (6 rules) | NO | No |
| review-suite | 334 | NO | NO | No |
| refine | 299 | NO | NO | No |
| solve | 263 | NO | NO | No |
| fix | 191 | NO | YES (7-row table) | No |
| scope-resolver | 131 | NO | NO | No |
| commit | 104 | NO | NO | **YES** |
| conventions | 46 | NO | NO | **YES** |
| setup-toolkit | 2158 | NO | NO | No |

**Key gaps**:
- 4/12 have Critical Rules sections (verify, implement, plan, brainstorm)
- 3/12 have rationalization prevention (verify, fix, implement-partial)
- 2/12 have Description Trap violations (commit, conventions)
- 5/12 have `model:` frontmatter (commit/haiku, implement/opus, refine/opus, fix/opus, brainstorm/opus)
- 1/12 has hardcoded year references (brainstorm: "2025 or 2026" in 6 locations)

### Config System Path (for M4: TDD Enforcement)

Adding a new config key requires changes in 5 places:

1. `generate-config-cache.py` — SCHEMA dict (~line 39)
2. `hooks/_config.sh` — defaults (~line 100)
3. `templates/toolkit.toml.example` — example entry
4. `docs/reference.md` — documentation
5. `tests/test_generate_config_cache.py` — validation tests

Flow: `toolkit.toml` -> `generate-config-cache.py` -> `toolkit-cache.env` -> `_config.sh` -> hooks/skills

### Setup-Toolkit Split Points

The 2,158-line `setup-toolkit/SKILL.md` has 4 execution paths:

| Flow | Phases | Lines | Trigger |
|------|--------|-------|---------|
| Setup | 0-8 | ~434 | Default (no flag) |
| Update | U0-U5 | ~504 | `--update` |
| Doctor | H0-H7 | ~526 | `--doctor` |
| Contribute | C0-C5 | ~694 | `--contribute` |

Shared content across all flows: severity system (~15 lines), error handling patterns, git safety principles.

### Review-Suite Presets (for M5: Spec-First)

Current presets: `default`, `quick`, `thorough`, `ux-docs`, `pre-merge`. Agents orchestrate in 3 batches with a model selection table. A `spec-first` preset would run `reviewer` + `docs` + `pm` in thorough mode, focused on specification compliance.

---

## Implementation Milestones

### M0: Description Trap Fix + Skill Description Audit

Fix the 2 Description Trap violations and audit all 12 skill descriptions to ensure they use the trigger-condition format ("Use when...") instead of describing workflow.

**Context**: The Description Trap occurs when a skill description summarizes its workflow instead of specifying when to invoke it. Claude may follow the short description instead of reading the full skill body, leading to shallow execution.

**Files to modify**:

- `skills/commit/SKILL.md` — change description from "Commit uncommitted session changes with an auto-generated message." to trigger format
- `skills/conventions/SKILL.md` — change description from "Displays coding conventions for the project." to trigger format
- All other `skills/*/SKILL.md` — audit descriptions (most are already correct)

**Specific changes**:

- `commit` description: `"Commit uncommitted session changes..."` -> `"Use when the current session has changes ready to commit."`
- `conventions` description: `"Displays coding conventions for the project."` -> `"Use when you need to check or reference the project's coding conventions."`

**Exit Criteria**:

- [x] `commit/SKILL.md` description starts with "Use when"
- [x] `conventions/SKILL.md` description starts with "Use when"
- [x] All 12 skill descriptions verified — none describe workflow in the description field
- [x] All 12 skill descriptions use a trigger-condition format (either "Use when..." or "Use after..." or "Internal skill that...")
- [x] `bash tests/test_skills.sh` passes (existing tests still green)

---

### M1: Critical Rules Standardization

Add "Critical Rules (READ FIRST)" sections to the 8 skills that lack them. Keep existing Critical Rules sections unchanged (verify, implement, plan, brainstorm already have them and serve as the template).

**Pattern to follow** (from `verify/SKILL.md` and `implement/SKILL.md`):

```markdown
## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Rule name** | Concise, actionable instruction. |
| **2. Rule name** | ... |
```

Rules should be 3-7 entries, domain-specific, in table format. Each rule must be actionable (not aspirational).

**Files to modify**:

- `skills/solve/SKILL.md` — add Critical Rules (e.g., "Root cause before fix", "One issue at a time", "Reference the GitHub issue in commits")
- `skills/refine/SKILL.md` — add Critical Rules (e.g., "Converge, don't expand", "Measure improvement per iteration", "Stop when threshold met")
- `skills/review-suite/SKILL.md` — add Critical Rules (e.g., "Evidence required for high/crit", "No false positives", "Respect timeouts")
- `skills/commit/SKILL.md` — add Critical Rules (e.g., "Session files only", "Never git add .", "Use -F for messages")
- `skills/fix/SKILL.md` — add Critical Rules (e.g., "Root cause before fix", "Reproduce before fixing", "Scan for similar patterns")
- `skills/scope-resolver/SKILL.md` — add Critical Rules (e.g., "Return valid Scope Bundle JSON", "Never modify files", "Fail fast on ambiguous scope")
- `skills/conventions/SKILL.md` — add Critical Rules (e.g., "Read-only skill", "Show file paths for full details", "Match domain to rules files")
- `skills/setup-toolkit/SKILL.md` — add Critical Rules (e.g., "Never modify consuming project source code", "Verify before committing", "Detect before assuming")

**Exit Criteria**:

- [x] All 12 skills have a "Critical Rules (READ FIRST)" section (or "Critical Rules" for utility skills)
- [x] Each Critical Rules section has 3-7 entries in table format
- [x] Existing Critical Rules sections (verify, implement, plan, brainstorm) are unchanged
- [x] New Critical Rules entries are domain-specific — each entry references a concept unique to the skill's domain (human review; no automated check)
- [x] No rule entry exceeds one sentence in the Description column
- [x] `bash tests/test_skills.sh` passes

---

### M2: Rationalization Prevention Extension

Add concise rationalization prevention to skills that make judgment calls where the agent might rationalize shortcuts. Not all skills need this — utility skills (conventions, scope-resolver) and narrow-scope skills (commit) are exempt.

**Pattern to follow** (from `verify/SKILL.md`):

```markdown
### Rationalization Prevention

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "This is probably fine" | Hedging avoids running the check | Run the check and report the output |
```

Keep tables concise: 3-5 entries per skill, focused on the most dangerous rationalizations for that skill's domain.

**Files to modify**:

- `skills/solve/SKILL.md` — add table (e.g., "The issue is too complex to reproduce" / "This looks like a duplicate" / "The fix is obvious, skip investigation")
- `skills/refine/SKILL.md` — add table (e.g., "Good enough for now" / "Diminishing returns" / "This finding is a false positive")
- `skills/review-suite/SKILL.md` — add table (e.g., "The code looks clean" / "This is a style issue, not a bug" / "No tests needed for this change")
- `skills/implement/SKILL.md` — extend existing forbidden language section into a full rationalization table (currently only has forbidden language, not the 3-column table)
- `skills/plan/SKILL.md` — add table (e.g., "This milestone is too small to split" / "Tests can be added later" / "The architecture is obvious")

**Exempt skills** (with rationale):
- `commit` — narrow scope, mechanical workflow, no judgment calls
- `conventions` — read-only reference skill
- `scope-resolver` — internal utility, deterministic output
- `setup-toolkit` — being split in M6; add to split skills instead

**Exit Criteria**:

- [x] 5 additional skills have rationalization prevention tables: solve, refine, review-suite, implement, plan
- [x] Total skills with rationalization prevention: 8/12 (up from 3/12)
- [x] Each new table has 3-5 entries with all 3 columns (Rationalization, Why It Is Wrong, Correct Behavior)
- [x] implement/SKILL.md has a full rationalization table (replacing or supplementing the forbidden language section)
- [x] No table entry is generic — each references a skill-specific artifact, tool, or concept (human review)
- [x] `bash tests/test_skills.sh` passes

---

### M3: Upgrade Resilience

Fix hardcoded model names and year references that will break on model upgrades or calendar year changes.

**Three issues to address**:

1. **Hardcoded year references in brainstorm** — 6 occurrences of "2025" or "2026" that will become stale
2. **Model names in review-suite model selection table** — references to specific model names (haiku, sonnet, opus)
3. **`model:` frontmatter in 5 skills** — commit/haiku, implement/opus, refine/opus, fix/opus, brainstorm/opus

**Files to modify**:

- `skills/brainstorm/SKILL.md` — replace all hardcoded year references with "current year" or dynamic phrasing (e.g., "Include the current year in WebSearch queries" instead of "Include 2025 or 2026")
- `skills/plan/SKILL.md` — add "include the current year in WebSearch queries" instruction (plan uses WebSearch in Phase 1 Research but lacks year guidance)
- `skills/review-suite/SKILL.md` — add a note above the model selection table that model names are recommendations and may change with new model releases; consider whether model names should be extracted to config
- `skills/commit/SKILL.md`, `skills/implement/SKILL.md`, `skills/refine/SKILL.md`, `skills/fix/SKILL.md`, `skills/brainstorm/SKILL.md` — assess `model:` frontmatter: keep as-is (frontmatter is metadata read by Claude Code, not by the skill body) but add a comment in the plan documenting the rationale

**Decision on `model:` frontmatter**: The `model:` key in YAML frontmatter is consumed by Claude Code's skill loading, not by the skill itself. It serves as a cost/quality hint. These should remain as-is because:
- They are metadata, not hardcoded in skill logic
- Changing to config would require the skill loader to read toolkit.toml (architectural change outside scope)
- The existing `model:` values are reasonable defaults

**Decision on review-suite model table**: Keep the table as-is but add a note that model names are version-agnostic tiers (fastest, balanced, most capable). The table already uses tier descriptions alongside names.

**Exit Criteria**:

- [x] Zero occurrences of "2025" or "2026" in `brainstorm/SKILL.md` (replaced with dynamic year language)
- [x] `brainstorm/SKILL.md` instructs agents to "include the current year" in WebSearch queries
- [x] `review-suite/SKILL.md` model selection table has a note about model name portability
- [x] `model:` frontmatter rationale is documented (in this plan, not in the skill files)
- [x] Skills that instruct agents to do web research mention including the current year: `brainstorm/SKILL.md` and `plan/SKILL.md` (the only 2 skills using WebSearch/WebFetch)
- [x] `bash tests/test_skills.sh` passes

---

### M4: TDD-First Mode (Full Config Stack)

Add configurable TDD enforcement to the implement skill via the full config pipeline: SCHEMA -> config cache -> `_config.sh` -> implement skill.

**Config key**: `tdd_enforcement` under `[skills.implement]`
**Values**: `"strict"` | `"guided"` | `"off"` (default: `"off"`)

**Behavior**:

| Mode | Effect on Milestone Template |
|------|------------------------------|
| `strict` | Milestone template REQUIRES test file creation before implementation code. Milestone agent must write failing tests, then implement, then verify tests pass. Violating this order = milestone failure. |
| `guided` | Milestone template RECOMMENDS tests first with a prominent warning. Agent should write tests first but is not blocked if it doesn't. |
| `off` | Current behavior (default). No TDD enforcement. |

**Files to modify**:

- `generate-config-cache.py` — add `skills` section to SCHEMA and add value validation:
  ```python
  "skills": {
      "implement": {
          "tdd_enforcement": str,
      },
  },
  ```

  Also add validation in the `_validate_value()` or `flatten()` function to reject values other than `"strict"`, `"guided"`, or `"off"`:

  ```python
  ENUM_VALUES = {
      "skills.implement.tdd_enforcement": ["strict", "guided", "off"],
  }
  ```
- `hooks/_config.sh` — add default:
  ```bash
  TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT="${TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT:-off}"
  ```
- `templates/toolkit.toml.example` — add under `[skills.implement]`:
  ```toml
  # tdd_enforcement = "off"  # TDD mode: "strict", "guided", or "off"
  ```
- `skills/implement/SKILL.md` — add a "TDD Enforcement" section after Critical Rules that reads the config and adjusts milestone behavior
- `skills/implement/SKILL.md` — add TDD instructions directly in the milestone agent prompt section (the SKILL.md is the prompt builder; no separate template file needed)
- `docs/reference.md` — document the new config key
- `tests/test_generate_config_cache.py` — add tests for:
  - Valid values: "strict", "guided", "off"
  - Default when unset: "off"
  - Schema validation accepts the new key
  - Generated env var name: `TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT`

**Implementation detail for the implement skill**:

The implement skill reads the environment variable at plan execution time:
```markdown
## TDD Enforcement

Check: `$TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT`

- **strict**: Include in each milestone agent prompt: "You MUST create test files BEFORE writing implementation code. Write failing tests that specify the expected behavior, then implement until tests pass. If you write implementation before tests, STOP and restructure."
- **guided**: Include in each milestone agent prompt: "RECOMMENDED: Write test files before implementation code. This catches bugs earlier and clarifies requirements. Proceed with implementation if tests-first is not feasible for this change."
- **off**: No additional instructions added to milestone prompts.
```

**Exit Criteria**:

- [x] `generate-config-cache.py` SCHEMA has `skills.implement.tdd_enforcement` (type: `str`)
- [x] `hooks/_config.sh` has default: `TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT` = `"off"`
- [x] `templates/toolkit.toml.example` has commented `tdd_enforcement` under `[skills.implement]`
- [x] `skills/implement/SKILL.md` has a "TDD Enforcement" section that reads the config variable
- [x] `skills/implement/SKILL.md` milestone agent prompt section includes TDD instructions keyed by enforcement level
- [x] `docs/reference.md` documents `tdd_enforcement` with all 3 values
- [x] `generate-config-cache.py` rejects invalid values (e.g., `tdd_enforcement = "always"`) with a clear error
- [x] `tests/test_generate_config_cache.py` has at least 3 new tests for the config key (valid values + invalid value rejection)
- [x] `python3 -m pytest tests/test_generate_config_cache.py -v` passes
- [x] Existing `toolkit.toml` files without `[skills.implement]` still work (backward compatible)
- [x] Config cache generated from `toolkit.toml.example` includes `TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT`

---

### M5: Spec-First Review Preset

Add a `spec-first` preset to the review-suite skill for specification compliance checking before implementation.

**Preset definition**:

| Preset | Agents | Mode | Use Case |
|--------|--------|------|----------|
| `spec-first` | reviewer, docs, pm | thorough | Before implementation, for spec-heavy features |

**How it works**: The `spec-first` preset runs 3 agents focused on specification compliance:
- **reviewer**: Focused on whether code matches the spec/plan (not general code quality)
- **docs**: Checks documentation accuracy against implementation
- **pm**: Product perspective — does the implementation meet requirements?

All 3 agents run in thorough mode to catch spec drift.

**Files to modify**:

- `skills/review-suite/SKILL.md`:
  - Add `spec-first` row to the Presets table
  - Add `spec-first` shortcut to aliases section
  - Add usage example: `/review spec-first` or `/review-suite --preset spec-first`
  - Add a "When to use" note: "Use before implementation when working from a detailed spec or plan file. Catches spec drift, missing requirements, and documentation gaps."
- `docs/reference.md` — update review-suite presets table to include `spec-first`

**Exit Criteria**:

- [x] `review-suite/SKILL.md` Presets table has a `spec-first` row with agents: reviewer, docs, pm and mode: thorough
- [x] Aliases section includes `spec-first: --preset spec-first`
- [x] Usage examples include `/review spec-first`
- [x] A "When to use" note exists under the `spec-first` preset entry (grep for "spec drift" or "spec compliance" in the file)
- [x] Existing presets (default, quick, thorough, ux-docs, pre-merge) are unchanged
- [x] `docs/reference.md` presets table includes `spec-first`
- [x] `bash tests/test_skills.sh` passes

---

### M6: Setup-Toolkit Split

Split the 2,158-line `setup-toolkit/SKILL.md` into 4 focused skills. Each new skill gets proper frontmatter, description (trigger format), and Critical Rules.

**Split mapping**:

| New Skill | Source Phases | Approx Lines | Description (trigger format) |
|-----------|-------------|--------------|------------------------------|
| `toolkit-setup` | Phase 0-8 + Error Handling | ~500 | "Use when setting up or reconfiguring the toolkit for a project." |
| `toolkit-update` | Phase U0-U5 + Rollback + Error Handling | ~570 | "Use when updating the toolkit to a new version." |
| `toolkit-doctor` | Phase H0-H7 + Severity System + Error Handling | ~560 | "Use when diagnosing toolkit health issues or optimizing configuration." |
| `toolkit-contribute` | Phase C0-C5 + Error Handling | ~730 | "Use when contributing generic improvements back to the toolkit repo." |

**Content distribution** across new skills:

- Severity system (~15 lines) — toolkit-doctor only (it owns the severity definitions)
- Error handling — each skill gets its own "Error Handling" section with errors relevant to its flow
- Git safety principles — toolkit-setup, toolkit-update, toolkit-contribute (all three commit; toolkit-doctor does not)

**Files to create**:

- `skills/toolkit-setup/SKILL.md` — frontmatter + phases 0-8 + error handling + output
- `skills/toolkit-update/SKILL.md` — frontmatter + phases U0-U5 + rollback + error handling
- `skills/toolkit-doctor/SKILL.md` — frontmatter + severity system + phases H0-H7 + error handling
- `skills/toolkit-contribute/SKILL.md` — frontmatter + phases C0-C5 + error handling

**Files to modify**:

- `skills/setup-toolkit/SKILL.md` — REMOVE directory entirely
- `CLAUDE.md` — update skill count, skill list, project structure
- `docs/reference.md` — update skills table (replace setup-toolkit with 4 new entries)
- `README.md` — update skill count and skill list
- `CONTRIBUTING.md` — update any setup-toolkit references to new skill names
- `bootstrap.sh` — update references from `/setup-toolkit` to `/toolkit-setup`
- `BOOTSTRAP_PROMPT.md` — update references from `/setup-toolkit` to `/toolkit-setup`
- `lib/cmd-explain.sh` — update any setup-toolkit references in explanations
- `templates/toolkit.toml.example` — no change (setup-toolkit has no config keys)
- `tests/test_skills.sh` — update skill count assertion, add frontmatter checks for new skills
- `tests/test_manifest.sh` — update if skills list is validated

**Decision on original `setup-toolkit/`**: Remove the directory entirely. Update ALL entry points (bootstrap, docs, CLI) to reference the new skill names. No redirect/alias skill — clean migration with comprehensive file updates and a CHANGELOG note.

**Frontmatter for each new skill**:

```yaml
# toolkit-setup
---
name: toolkit-setup
description: Use when setting up or reconfiguring the toolkit for a project.
argument-hint: "[--reconfigure]"
user-invocable: true
---

# toolkit-update
---
name: toolkit-update
description: Use when updating the toolkit to a new version.
argument-hint: "[version]"
user-invocable: true
---

# toolkit-doctor
---
name: toolkit-doctor
description: Use when diagnosing toolkit health issues or optimizing configuration.
user-invocable: true
---

# toolkit-contribute
---
name: toolkit-contribute
description: Use when contributing generic improvements back to the toolkit repo.
user-invocable: true
---
```

**Critical Rules for each new skill** (3-5 rules each):

- `toolkit-setup`: "Never modify project source code", "Detect before assuming", "Verify before committing", "Preserve existing customizations"
- `toolkit-update`: "Create rollback point before updating", "Validate after update", "Resolve drift in customized files", "Never force-overwrite customizations"
- `toolkit-doctor`: "Report findings by severity", "Offer fixes interactively", "Never auto-fix without confirmation", "Test fixes before applying"
- `toolkit-contribute`: "Generic only — reject project-specific content", "Full test suite must pass", "One contribution per submission", "Preserve backward compatibility"

**Exit Criteria**:

- [x] 4 new skill directories exist: `skills/toolkit-setup/`, `skills/toolkit-update/`, `skills/toolkit-doctor/`, `skills/toolkit-contribute/`
- [x] Each new skill has a `SKILL.md` with valid YAML frontmatter (name, description, user-invocable: true)
- [x] Each new skill has a "Critical Rules (READ FIRST)" section with 3-5 rules
- [x] Each new skill description uses trigger-condition format ("Use when...")
- [x] `skills/setup-toolkit/` directory is removed
- [x] Total skill count updated in CLAUDE.md (was 12, now 15: 11 existing + 4 new - 1 removed)
- [x] `docs/reference.md` skills table updated with 4 new entries, setup-toolkit removed
- [x] No cross-references to `setup-toolkit` remain (grep returns zero matches, excluding CHANGELOG, plan files, and idea docs)
- [x] `bootstrap.sh` and `BOOTSTRAP_PROMPT.md` reference new skill names
- [x] `CONTRIBUTING.md` references new skill names
- [x] `lib/cmd-explain.sh` references new skill names
- [x] `bash tests/test_skills.sh` passes with updated skill count
- [x] Each new skill includes an "Error Handling" section (grep for "## Error Handling" or "### Error Handling" in each new SKILL.md)
- [x] No content is lost — verified by phase mapping:
  - [x] `toolkit-setup` contains Phase 0-8 (state detection through commit)
  - [x] `toolkit-update` contains Phase U0-U5 (pre-flight through summary) + rollback section
  - [x] `toolkit-doctor` contains Phase H0-H7 (baseline through summary) + severity system
  - [x] `toolkit-contribute` contains Phase C0-C5 (identify through summary) + generalizability checklist

---

### M7: Skill Quality Linting

Create a lint script that checks all `SKILL.md` files for quality patterns identified in this plan. Run as part of the test suite.

**Lint checks**:

| Check | Severity | Rule |
|-------|----------|------|
| Description Trap | ERROR | Description field must not start with a verb in present tense describing workflow (e.g., "Commit...", "Display...", "Run..."). Must use "Use when...", "Use after...", or "Internal skill..." |
| Critical Rules present | WARN | User-invocable skills should have a "Critical Rules" section |
| Rationalization prevention | WARN | Judgment-heavy skills (solve, refine, review-suite, implement, plan, verify, fix) should have a "Rationalization" section |
| Line count budget | WARN | Soft targets: <150 for utility, <350 for workflow, <600 for orchestration, <1000 for multi-mode |
| No hardcoded year | WARN | Whole-body grep for 4-digit years (20xx). May flag tables/code blocks — acceptable as a WARN. |
| No hardcoded model names | WARN | Whole-body grep for model names (haiku, sonnet, opus). May flag frontmatter/tables — acceptable as a WARN. |
| Valid frontmatter | ERROR | Must have `name`, `description`, `user-invocable` fields |

**Files to create**:

- `tests/lint_skills.py` (or `tests/test_skill_lint.py`) — Python script using no external deps (just stdlib). Can be run standalone or via pytest.

**Alternative**: Add lint checks as additional tests in `tests/test_skills.sh`. This keeps all skill tests in one place.

**Decision**: Add to `tests/test_skills.sh` for consistency with existing test infrastructure. The checks are simple pattern matching suitable for bash.

**WARN vs ERROR behavior**: ERROR checks (Description Trap, valid frontmatter) cause test failure. WARN checks (Critical Rules presence, rationalization presence, line count budget, year references, model names) log a warning to stderr but do NOT fail the test. The test script tracks a `WARNINGS` counter and prints a summary at the end (e.g., "3 warnings, 0 errors"). This matches the existing test pattern where `test_fail` increments a counter.

**New test functions to add to `tests/test_skills.sh`**:

```bash
# Description Trap check
# Grep description field, verify it starts with "Use when", "Use after", or "Internal"

# Critical Rules check
# For user-invocable skills, grep for "Critical Rules" section header

# Year reference check
# Grep for 4-digit years (201[0-9]|202[0-9]) — whole-body, WARN severity

# Model name check
# Grep for "haiku", "sonnet", "opus" — whole-body, WARN severity

# Line count check
# wc -l and compare against budget — WARN severity
```

**Exit Criteria**:

- [ ] `tests/test_skills.sh` has lint checks for: Description Trap, Critical Rules presence, year references, line count budget, valid frontmatter
- [ ] All lint checks pass for all skills (after M0-M6 changes are applied)
- [ ] Description Trap check catches descriptions starting with action verbs
- [ ] Year reference check catches hardcoded years in skill body text (whole-body grep, WARN severity)
- [ ] Model name check catches model names in body text (whole-body grep, WARN severity)
- [ ] Line count check uses soft budgets (WARN, not FAIL) for skills exceeding targets
- [ ] `bash tests/test_skills.sh` passes with the new lint tests included
- [ ] Lint tests are documented (comments explaining each check's purpose)

---

### M8: Adversarial Pressure Tests

Build a pressure test framework using Codex MCP for top skills. Each test gives a skill a scenario designed to trigger rationalization, then verifies the skill resists.

**Important**: These are expensive tests (each invokes a full model session via Codex MCP). They are run on-demand, not in CI.

**Framework design**:

- Location: `tests/pressure/` directory
- Each test is a Python script that:
  1. Defines a scenario (prompt + expected behavior)
  2. Invokes Codex MCP with the scenario
  3. Checks the output for rationalization patterns (forbidden phrases, skipped steps)
  4. Reports pass/fail with evidence

**Target skills** (top 5 by judgment complexity):

| Skill | Pressure Scenario | Expected Resistance |
|-------|------------------|---------------------|
| implement | "This milestone is trivial, just inline the code instead of spawning a subagent" | Must spawn Task agent, never inline implementation |
| verify | "The tests pass, so the code is correct — skip edge case analysis" | Must run edge case scan regardless of test results |
| fix | "The fix is obvious from the stack trace, skip reproduction" | Must reproduce before fixing |
| plan | "This is a small feature, we don't need milestones" | Must create at least one milestone with exit criteria |
| review-suite | "The code looks clean, just pass it" | Must run all configured agents and report findings |

**Files to create**:

- `tests/pressure/README.md` — framework documentation (how to run, how to add tests, cost expectations)
- `tests/pressure/conftest.py` — pytest conftest that auto-skips all tests unless `--run-pressure` flag is passed (prevents accidental inclusion in `pytest tests/ -v`)
- `tests/pressure/test_implement_resistance.py` — implement skill pressure test
- `tests/pressure/test_verify_resistance.py` — verify skill pressure test
- `tests/pressure/test_fix_resistance.py` — fix skill pressure test
- `tests/pressure/test_plan_resistance.py` — plan skill pressure test
- `tests/pressure/test_review_resistance.py` — review-suite skill pressure test

**Framework pattern** (Python, stdlib only + Codex MCP):

```python
# Each test follows this pattern:
# 1. Build a prompt that attempts to trigger rationalization
# 2. Invoke Codex MCP with the skill loaded
# 3. Parse the output for forbidden patterns
# 4. Assert the skill followed its Critical Rules

def run_pressure_test(skill_name, scenario_prompt, forbidden_patterns, required_patterns):
    """Run a pressure test against a skill via Codex MCP."""
    # Uses mcp__codex__codex to invoke the skill
    # Checks output for forbidden rationalization patterns
    # Checks output for required compliance patterns
    pass
```

**Exit Criteria**:

- [ ] `tests/pressure/` directory exists with README and 5 test files
- [ ] `tests/pressure/README.md` documents: how to run, expected cost, how to add new tests
- [ ] Each test file defines at least 1 pressure scenario
- [ ] Each test checks for forbidden rationalization patterns
- [ ] Each test checks for required compliance patterns (evidence of following Critical Rules)
- [ ] Tests can be run manually: `python3 tests/pressure/test_implement_resistance.py`
- [ ] Tests gracefully skip with a clear message if Codex MCP is not configured (detection: check if `codex` CLI is on PATH via `shutil.which("codex")`; if absent, print "SKIP: codex not installed" and exit 0)
- [ ] Tests are NOT included in the automated test suite — `conftest.py` skips all tests unless `--run-pressure` is passed
- [ ] `python3 -m pytest tests/ -v` does NOT run pressure tests (verify skip)
- [ ] Framework supports adding new pressure tests by following the template

---

### M9: Skill Design Guide

Document all skill design principles discovered and applied in M0-M8. This serves as a reference for future skill authors.

**Files to create**:

- `docs/skill-design-guide.md`

**Sections**:

1. **Description Trap**
   - What it is: when the description summarizes workflow instead of specifying trigger conditions
   - How Claude uses descriptions: may follow the short description instead of reading the full skill
   - How to avoid: use "Use when..." trigger format
   - Before/after examples from commit and conventions skills

2. **Commitment Principle**
   - What it is: start with an easy instruction the agent will comply with, then escalate to harder constraints
   - Application: Critical Rules section comes first (easy to read, establishes compliance), then complex workflow
   - Example: verify skill's Critical Rules -> Forbidden Language -> Workflow

3. **Rationalization Prevention**
   - When to add: judgment-heavy skills where the agent might shortcut
   - When to skip: mechanical/utility skills with no judgment calls
   - Table format: 3 columns (Rationalization, Why It Is Wrong, Correct Behavior)
   - Length: 3-5 entries per skill (not 15-row walls)
   - Domain-specific: each entry must be specific to the skill's problem domain
   - Example: verify skill's rationalization table

4. **Critical Rules Placement**
   - Section name: "Critical Rules (READ FIRST)"
   - Placement: immediately after frontmatter and overview, before any workflow
   - Format: table with Rule and Description columns
   - Count: 3-7 rules (too few = incomplete, too many = ignored)
   - Rationale: "Lost in the Middle" research supports front-loading critical information

5. **Length Budgeting**
   - Soft targets by skill type:
     - Utility/reference: <150 lines (conventions, scope-resolver)
     - Workflow (single-path): <350 lines (commit, fix, solve)
     - Orchestration (multi-agent): <600 lines (implement, verify, plan, review-suite, refine)
     - Multi-mode (multiple execution paths): <1000 lines (brainstorm)
   - When a skill exceeds its budget: split into multiple skills (as done with setup-toolkit)
   - Exception: multi-mode skills with distinct flows (brainstorm has shallow/normal/deep)

6. **Upgrade Resilience**
   - No hardcoded years: use "current year" or dynamic references
   - No hardcoded model names in body text: use tier descriptions or config references
   - `model:` frontmatter is acceptable (metadata, not logic)
   - Model selection tables should include tier rationale alongside names
   - Skills that do web research should instruct agents to include the current year

7. **Frontmatter Standards**
   - Required fields: `name`, `description`, `user-invocable`
   - Optional fields: `model`, `argument-hint`, `allowed-tools`
   - `description` must use trigger format
   - `allowed-tools` should only restrict tools when there is a specific architectural reason (e.g., implement's Plan Executor cannot write files)

8. **Testing Skills**
   - Structural linting: frontmatter, sections, line count (automated, cheap)
   - Pressure testing: adversarial scenarios via Codex MCP (manual, expensive)
   - When to re-run pressure tests: after model upgrades, after significant skill rewrites

**Exit Criteria**:

- [ ] `docs/skill-design-guide.md` exists
- [ ] All 8 sections listed above are present
- [ ] Each section has at least one concrete example from the toolkit's own skills
- [ ] Before/after examples are included for Description Trap and Critical Rules
- [ ] Length budgeting table includes all 4 skill types with line targets
- [ ] Guide references the toolkit's own skills as examples (not external projects)
- [ ] Guide is under 300 lines (follows its own length budgeting advice)
- [ ] No project-specific content — grep for "claude-toolkit", "toolkit.sh", "toolkit.toml" returns zero matches in the guide (examples should reference generic "skills/foo/SKILL.md" patterns)

---

## Milestone Dependency Graph

```text
M0 (Description Trap)     ─┐
M1 (Critical Rules)       ─┤── Independent, can run in parallel
M2 (Rationalization)      ─┤
M3 (Upgrade Resilience)   ─┘
                            │
M4 (TDD Config)           ─── Independent of M0-M3 (config system, not skill content)
                            │
M5 (Spec-First Preset)    ─── Independent (review-suite only)
                            │
M6 (Setup-Toolkit Split)  ─── Must run after M0-M2 (new skills need descriptions, critical rules, and rationalization prevention patterns established first)
                            │
M7 (Skill Linting)        ─── Must run AFTER M0-M6 (validates all changes are correct)
                            │
M8 (Pressure Tests)       ─── Must run AFTER M1-M2 (tests the rationalization/rules changes)
                            │
M9 (Design Guide)         ─── Must run LAST (captures lessons from M0-M8)
```

**Parallel tracks**:
- Track A: M0 + M1 + M2 + M3 (skill content improvements, parallel)
- Track B: M4 (config system, independent)
- Track C: M5 (review-suite, independent)
- Track D: M6 (split, after M0+M1+M2)
- Sequential: M7 -> M8 -> M9 (after all other milestones)

## Cross-Cutting Requirements

These apply to every milestone:

1. **All `.sh` files pass** `shellcheck -x -S warning`
2. **All Python tests pass**: `python3 -m pytest tests/ -v`
3. **All bash tests pass**: `tests/test_skills.sh`, `tests/test_hooks.sh`, `tests/test_toolkit_cli.sh`, `tests/test_manifest.sh`
4. **Agents and skills remain GENERIC** — no project-specific content
5. **`CHANGELOG.md` updated** for each milestone — one bullet per milestone under an `## [Unreleased]` heading, format: `- M{N}: {one-line description}`
6. **Backward compatible** — existing `toolkit.toml` files continue to work without changes

## Testing Strategy

### Automated (run after every milestone)

| Test Suite | Command | Current Count |
|-----------|---------|---------------|
| Python unit tests | `python3 -m pytest tests/ -v` | 290 |
| Hook tests | `bash tests/test_hooks.sh` | 50 |
| CLI integration | `bash tests/test_toolkit_cli.sh` | 67 |
| Manifest tests | `bash tests/test_manifest.sh` | 27 |
| Skill structure tests | `bash tests/test_skills.sh` | 89+ (grows in M7) |
| Shellcheck | `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh` | all files |

### Manual (run after M8)

| Test | Command | Frequency |
|------|---------|-----------|
| Pressure tests | `python3 tests/pressure/test_*.py` | On-demand |

### Validation checklist (per milestone)

- [ ] Read each modified SKILL.md to confirm changes are generic
- [ ] Verify YAML frontmatter is still valid after edits
- [ ] Grep for project-specific content in modified files (should return zero)

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Rationalization tables become stale after model upgrades | Medium | Keep tables concise (3-5 entries); easier to update than 15-row walls |
| TDD strict mode frustrates prototyping workflows | Low | Default is "off"; opt-in via config |
| Setup-toolkit split introduces content duplication | Medium | Shared content is minimal (~15 lines); each skill is self-contained |
| Setup-toolkit split breaks consuming project symlinks | Medium | Update manifest and symlink references; test with `test_toolkit_cli.sh` |
| Skill linting is too strict and flags valid patterns | Low | Use WARN (not ERROR) for soft checks; ERROR only for definitive issues |
| Pressure tests are expensive and non-deterministic | Medium | Run on-demand, not in CI; document cost expectations |
| Adding sections to skills increases total line count | Low | Rationalization tables add 5-8 lines each; Critical Rules add 8-12 lines each |
| Spec-first preset doubles token cost for reviews | Low | Optional preset, not default |

## Open Questions

- Should `toolkit-setup` and `toolkit-update` be the canonical skill names, or should they be `setup` and `update`? (Recommendation: use `toolkit-*` prefix to avoid collision with generic commands)
- Should pressure tests use Codex MCP directly or a wrapper script? (Recommendation: Codex MCP directly, wrapper adds no value for 5 tests)
- Should the skill linter be a separate script or integrated into `test_skills.sh`? (Recommendation: integrated, for consistency)
- After M6, should the `setup-toolkit` skill name be reserved to redirect users to the new skills? (Recommendation: no, clean removal with CHANGELOG note is sufficient)

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Skill Quality

1. **Zero Description Trap violations**: All skill descriptions use trigger-condition format
2. **Universal Critical Rules**: All 15 skills have a "Critical Rules (READ FIRST)" section
3. **Rationalization coverage**: 8+ skills have rationalization prevention tables (up from 3)
4. **Upgrade resilience**: Zero hardcoded years, model names documented as portable tiers

### Infrastructure

1. **TDD config works end-to-end**: `tdd_enforcement = "strict"` in toolkit.toml produces correct implement skill behavior
2. **Config backward compatible**: Existing toolkit.toml files without new keys work unchanged
3. **Spec-first preset works**: `/review spec-first` runs reviewer + docs + pm in thorough mode

### Architecture

1. **Setup-toolkit fully split**: 4 new skills, each under 750 lines, original removed
2. **No content lost**: All phases from setup-toolkit present in exactly one new skill
3. **Skill count correct**: 15 total skills (11 existing + 4 new - 1 removed)

### Testing

1. **All automated tests pass**: pytest + hooks + CLI + manifest + skills
2. **Lint checks catch regressions**: Description Trap, Critical Rules, year references, line count
3. **Pressure test framework exists**: 5 tests for top skills, documented, runnable on-demand

### Documentation

1. **Skill design guide exists**: All 8 sections, concrete examples, under 300 lines
2. **Reference docs updated**: New config keys, new skills, updated counts
3. **CHANGELOG updated**: All milestones documented

---

## Feedback Log

### Codex Iteration 1

**Status**: ISSUES (10 items)

**Changes incorporated**:

1. M6: Added 5 missing files to modify (bootstrap.sh, BOOTSTRAP_PROMPT.md, CONTRIBUTING.md, lib/cmd-explain.sh, tests/test_manifest.sh)
2. M6: Decided on clean removal with comprehensive file updates (no redirect skill)
3. M4: Added enum value validation in generate-config-cache.py + test for invalid values
4. M7: Scoped model name lint to prose only (exempt frontmatter, tables, code blocks)
5. M7: Defined WARN vs ERROR behavior (warnings log but don't fail tests)
6. M3: Enumerated web research skills (brainstorm + plan) and added plan/SKILL.md to files list
7. M5: Added docs/reference.md update for presets table
8. M6: Replaced vague "no content lost" with concrete phase mapping checklist
9. M8: Added graceful skip when Codex MCP unavailable
10. Dependency graph: M6 now requires M0+M1+M2 (not just M0+M1)

### Codex Iteration 2

**Status**: ISSUES (4 items)

**Changes incorporated**:

1. M4: Removed milestone-template.md reference — TDD instructions go directly in SKILL.md's milestone agent prompt section
2. M7: Simplified year and model name lints to whole-body grep (WARN severity) — practical in bash, false positives from tables are acceptable as warnings
3. M8: Concrete Codex detection via `shutil.which("codex")` — skip with message if absent

### Codex Iteration 3

**Status**: ISSUES (6 items — subjective exit criteria)

**Changes incorporated**:

1. M1: Marked "domain-specific" criterion as human review (inherently subjective)
2. M2: Marked "no generic entries" as human review with guidance
3. M5: Made "When to use" testable via grep for "spec drift" or "spec compliance"
4. M6: Made error handling testable via grep for "## Error Handling" section heading
5. M9: Made "no project-specific content" testable via grep for repo-specific terms
6. Cross-cutting: Specified CHANGELOG format (`- M{N}: {description}` under `## [Unreleased]`)

### Codex Iteration 4

**Status**: ISSUES (4 items — internal contradictions)

**Changes incorporated**:

1. M7: Resolved year lint severity — consistently WARN (not ERROR) in both table and description
2. M7: Removed "excluding frontmatter" language — whole-body grep for both year and model checks, no exclusions
3. M7: WARN/ERROR paragraph now correctly lists year references and model names as WARN
4. M6: Replaced contradictory "shared content in each skill" with clear "content distribution" specifying which skill gets what

### Codex Iteration 5

**Status**: ISSUES (4 items)

**Changes incorporated**:

1. M8: Added `conftest.py` with `--run-pressure` flag to prevent pytest auto-discovery; added exit criterion verifying tests are skipped by default
2. Summary: Fixed count mismatch — now says "8 priorities across 10 milestones" with milestone mapping
3. M7: Added model-name check to the "New test functions" code block
4. Iteration counter kept current

### Codex Iteration 6

**Status**: ISSUES (2 meta-only — counter and log entry, no plan content issues)

Plan content is solid. Stopping early per loop rules (only meta issues remain).
