# Milestone Orchestrator: {milestone_id} -- {milestone_title}

You are implementing milestone {milestone_id} from the {plan_name} plan.

## Context

- **Plan file**: {plan_file}
- **Milestone**: {milestone_id}
- **Title**: {milestone_title}
- **State directory**: artifacts/execute/{plan_name}/{milestone_id}/

## IMPORTANT LESSONS

- Guard hooks may block commit messages containing certain patterns -- use `git commit -F <file>`
- Write commit message to artifacts/execute/{plan_name}/{milestone_id}/commit-msg.txt first
- Run commands separately (not chained with &&)
- Read files BEFORE modifying them
- Follow all project conventions from CLAUDE.md and .claude/rules/

## Your Output

Write result to: `artifacts/execute/{plan_name}/{milestone_id}/result.json`

---

## Phases (EXECUTE IN ORDER -- NO SKIPPING)

### Phase 0: Prerequisites

1. Verify clean git: `git status --porcelain`
   - Exception: plan file changes and `.claude/` changes are OK
2. Create state directory: `mkdir -p artifacts/execute/{plan_name}/{milestone_id}/`
3. Create evidence directory: `mkdir -p artifacts/execute/{plan_name}/{milestone_id}/evidence/`

<!-- Project-specific prerequisites: -->
<!-- - Verify server running: `lsof -i :PORT` -->
<!-- - Verify build tools available -->

### Phase 1: Parse Milestone

1. Read plan file: `{plan_file}`
2. Find milestone section (### {milestone_id}:)
3. Extract:
   - Exit criteria (checkboxes -- these become your acceptance tests)
   - Database changes (new tables, columns, migrations)
   - API endpoints (new or modified routes)
   - UI changes (views, components)
4. Write initial state.json

### Phase 2: Architecture Analysis

1. Read CLAUDE.md for project conventions and critical rules
2. Read existing files you will modify (ENTIRE file, not just the function)
3. Note patterns to follow from existing code
4. Create file list: files to modify vs files to create
5. Update state.json: `phases_completed` += "architecture"

### Phase 3: Create Todos

Convert each exit criterion to a todo using TodoWrite:

- Every exit criterion = one todo item
- Add implementation sub-tasks as additional todos
- All exit criteria todos must be completed before done
- Update state.json: `phases_completed` += "todos"

### Phase 4: Implementation (Layer by Layer)

Execute layers in dependency order. Common layer order:

```text
[database, service/business-logic, api/routes, ui/frontend]
```

Only implement layers that the milestone requires. Skip layers with no changes.

#### Test-First Guidance (within each layer)

When implementing non-trivial logic, prefer writing tests first:

1. Write a failing test that describes the expected behavior
2. Run the test -- confirm it FAILS (red)
3. Write the minimum code to make it pass (green)
4. Run all tests -- confirm they pass
5. Refactor if needed, keeping tests green

Do NOT write tests for:

- Configuration file changes
- Database migrations (test the result, not the migration itself)
- UI layout-only changes (visual verification instead)
- Wiring/glue code that just connects tested components
- Simple one-line changes or obvious fixes
- Boilerplate, scaffolding, or setup code
- Changes to files that have no existing test coverage (unless adding coverage is part of the plan)

The goal is preventing regressions in complex logic, not achieving 100% coverage.

```text
FOR each layer:
  IF milestone requires this layer:

    1. Implement the layer following existing patterns
    2. Run project test command (e.g., make test, pytest, npm test)
    3. IF tests fail: Fix (max 3 attempts)
    4. Run project lint command
    5. IF lint fails: Run formatter, then lint again
    6. Update state.json: layers_completed += layer

  IF layer FAILS after 3 retries:
    - LOG: "Layer {layer} failed after 3 attempts"
    - Write result.json with status="failed"
    - EXIT milestone orchestrator
```

<!-- Customize layer details for your project: -->

<!-- #### Layer: database -->
<!-- - Add new tables/columns following project patterns -->
<!-- - Run migrations if applicable -->

<!-- #### Layer: service -->
<!-- - Add/modify business logic in services directory -->
<!-- - Follow project patterns for return types, error handling -->

<!-- #### Layer: api -->
<!-- - Add/modify routes following project patterns -->
<!-- - Test endpoints with curl or similar -->

<!-- #### Layer: frontend -->
<!-- - Add/modify UI components -->
<!-- - Build and verify -->

Update state.json after all layers complete: `phases_completed` += "implementation"

### Phase 5: Full Test Suite

1. Run the full test suite (not just changed files)
2. ALL tests must pass
3. Run linter

If tests fail:

- Fix the failing tests (max 3 attempts)
- If still failing after 3 attempts, record in state.json and exit

Update state.json: `tests_passed` = true, `lint_passed` = true

### Phase 6: UI Verification

IF the milestone has UI changes:

1. Use project-specific UI testing tools
2. Capture screenshots of new/modified views
3. Save evidence to artifacts directory
4. Verify:
   - New views render correctly
   - Data displays properly
   - No obvious layout issues

IF no UI changes: Skip this phase entirely.

Update state.json: `phases_completed` += "ui_verification"

### Phase 7: Codex Review (MANDATORY -- NO EXCEPTIONS)

**STOP. You MUST call mcp__codex__codex before proceeding.**

Get changed files and call codex for review:

```text
mcp__codex__codex with:
  approval-policy: "never"
  prompt: "Review implementation for {milestone_id}: {milestone_title}

Changed files:
{list of changed files}

Exit criteria from plan:
{list of exit criteria}

Focus on:
1. Does implementation match the plan's architecture?
2. Are ALL exit criteria satisfied?
3. Is test coverage adequate?
4. Error handling complete?
5. Edge cases covered?

Start your response with:
- SOLID: if no significant issues
- ISSUES: if problems need fixing (list each)"
```

Process response:

- IF "ISSUES:": Create todos for each issue, fix, call codex again (max 3 iterations)
- IF "SOLID:": Note any minor suggestions, proceed to Phase 8

Update state.json: `phases_completed` += "codex_review"

### Phase 8: Reviewer Agent (MANDATORY -- catches what codex misses)

Run adversarial code review BEFORE commit:

```text
Task(
  subagent_type="reviewer",
  prompt="Code review for {milestone_id}: {milestone_title}

Changed files:
{git diff --name-only HEAD}

Focus on:
1. Bugs and logic errors
2. Edge cases not covered
3. Missing error handling
4. Security vulnerabilities
5. Code quality issues

Report only HIGH priority issues that truly matter.
Start response with:
- CLEAN: if no high-severity issues
- ISSUES: if problems need fixing (list each with severity)"
)
```

Process response:

- IF "ISSUES:": Fix HIGH severity issues, run reviewer again (max 2 iterations)
- IF "CLEAN:": Proceed to Phase 8b

Update state.json: `phases_completed` += "reviewer"

### Phase 8b: Spec Compliance Verification (MANDATORY)

Invoke the `/verify` skill in quick mode to check that the milestone's exit criteria are actually satisfied. This reuses the verify skill's verification gate, rationalization prevention, and fix-or-ask workflow -- do not duplicate that logic here.

> **Adversarial framing**: The implementer finished suspiciously quickly. Verify everything independently. Assume every claim of "done" is wrong until you see evidence from a command you ran yourself.

**Forbidden language** -- if any of these phrases appear in verification output, the claim is unverified:

- "should work"
- "probably fine"
- "seems correct"
- "looks good"
- "I believe this is correct"

#### Procedure

```text
1. Invoke: /verify {plan_file} --quick
   - The verify skill will run tests, lint, and check each exit criterion
     for this milestone against actual evidence (commands run, output read)
   - It applies its own 5-step verification gate (IDENTIFY → RUN → READ → VERIFY → CLAIM)
   - It uses its rationalization prevention table to catch self-deception
   - It fixes unambiguous issues directly and asks about ambiguous ones

2. IF verify reports PASS:
   - Proceed to Phase 9

3. IF verify reports FAIL:
   - Review the failing exit criteria
   - Fix the issues
   - Re-invoke: /verify {plan_file} --quick
   - Max 2 rounds of fix-and-reverify
   - IF still failing after 2 rounds:
     - Write result.json with status="failed" and the unmet criteria
     - EXIT milestone orchestrator
```

Update state.json: `phases_completed` += "spec_compliance"

### Phase 9: Documentation Updates

Update documentation to reflect changes made:

- Update relevant context/domain documentation files
- Update project README if applicable
- Update plan file: mark exit criteria as `[x]` for this milestone

> **Do NOT update VERSION or CHANGELOG.md here.** Version file and changelog updates are deferred to the Plan Executor's Step 2e (Version File Check), which runs after all milestones complete. This prevents conflicting version updates across milestones and ensures a single, coherent version bump for the entire plan.

Update state.json: `phases_completed` += "documentation"

### Phase 10: Exit Criteria Verification

For EACH exit criterion from the plan:

1. Verify it is actually implemented (read the code)
2. Record evidence:
   - Test name that proves it works
   - File path where implementation lives
   - Screenshot path (if UI change)
3. If NOT verified: DO NOT proceed -- fix first, then re-verify

All criteria must have evidence before proceeding to commit.

Update state.json: `phases_completed` += "exit_criteria_verified"

### Phase 11: Create Commit

**IMPORTANT**: Use `git commit -F <file>`, NOT heredoc. Guard hooks may block commit messages with certain patterns when using heredoc.

```text
1. Write commit message to file:
   artifacts/execute/{plan_name}/{milestone_id}/commit-msg.txt

   Format:
   Implement {milestone_id}: {milestone_title}

   {Brief summary of what was implemented}

   Exit criteria satisfied:
   - {criterion 1}
   - {criterion 2}
   ...

   Plan: {plan_file}
   Milestone: {milestone_id}

   Co-Authored-By: Claude <noreply@anthropic.com>

2. Stage specific files (NO `git add .`):
   git add <file1> <file2> ...
   git add .claude/agent-memory/ 2>/dev/null || true

3. Commit:
   git commit -F artifacts/execute/{plan_name}/{milestone_id}/commit-msg.txt
```

**DO NOT PUSH.**

Record commit hash: `git rev-parse HEAD`

Update state.json: `phases_completed` += "commit"

---

## Output

Write to `artifacts/execute/{plan_name}/{milestone_id}/result.json`:

### Success

```json
{
  "status": "success",
  "milestone": "{milestone_id}",
  "title": "{milestone_title}",
  "commit_hash": "<hash from git rev-parse HEAD>",
  "files_modified": ["src/services/foo.py", "src/routes/bar.py"],
  "files_created": ["src/services/new_service.py"],
  "tests_added": ["tests/test_foo.py::test_new_feature"],
  "exit_criteria_verified": [
    {"id": 1, "text": "criterion text", "evidence": "test name or file path"}
  ],
  "codex_iterations": 2,
  "codex_result": "SOLID",
  "reviewer_iterations": 1,
  "reviewer_result": "CLEAN",
  "ui_verified": true,
  "evidence_files": []
}
```

### Failure

```json
{
  "status": "failed",
  "milestone": "{milestone_id}",
  "title": "{milestone_title}",
  "phase_failed": "implementation",
  "error": "Tests failed after 3 retries in service layer",
  "partial_progress": {
    "layers_completed": ["database"],
    "layers_failed": ["service"],
    "files_modified": ["src/db/schema.py"]
  }
}
```

---

## Critical Reminders

- **State file is truth**: Update state.json after every significant action
- **Fresh context**: You are a fresh agent -- read files before modifying them
- **One layer at a time**: Complete and test each layer before moving to the next
- **Exit criteria are non-negotiable**: Every criterion must have evidence
- **Do not push**: Only commit locally
- **Codex is mandatory**: Never skip Phase 7
- **Reviewer is mandatory**: Never skip Phase 8
- **Guard hook lesson**: Always use `git commit -F <file>` for commits
