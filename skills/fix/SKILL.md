---
name: fix
description: Use when a bug needs fixing but there is no GitHub issue to track it.
argument-hint: '"description of the bug" or paste an error/stack trace'
user-invocable: true
model: opus
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - TodoWrite
  - mcp__plugin_playwright_playwright__*
---

# Fix Skill

Systematic bug fix workflow: root-cause, fix, validate, scan for similar issues, test, commit.

**Distinct from `/fix-github`**: `/fix` is standalone (bug description -> root-cause -> fix -> scan similar -> test -> commit). `/fix-github` is GitHub issue workflow (fetch issue -> reproduce -> plan -> fix -> commit referencing issue).

> **Customization**: Override defaults in `toolkit.toml` under `[skills.fix]`. Run `bash toolkit.sh customize skills/fix/SKILL.md` to take full ownership of this skill.

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Root cause before fix** | Identify the root cause through investigation and evidence before proposing any code change. |
| **2. Reproduce before fixing** | Confirm the bug exists (run it, read the trace, or analyze the code path) before writing a fix. |
| **3. Scan for similar patterns** | After fixing the bug, search the codebase for the same anti-pattern in other locations. |
| **4. Single hypothesis at a time** | Test one fix hypothesis, verify it, then move on; never apply multiple speculative changes at once. |
| **5. 3-fix escalation** | After 3 failed fix attempts, stop and ask the user for guidance instead of attempting a 4th. |

---

## Workflow

### Step 1: Systematic Debugging (4 Phases)

#### Phase 1: Root Cause Investigation

1. **Read the error/bug description carefully** -- extract the symptom, affected file(s), and reproduction steps
2. **Reproduce the bug** -- confirm you can trigger the failure before attempting any fix
3. **Check recent changes** -- run `git log` on affected files to see what changed recently
4. **Locate the code** -- use Grep/Glob to find the relevant source files. Read entire files, not just snippets
5. **Trace the bug** -- follow the execution path from entry point to failure. Check:
   - The function/method where the error occurs
   - Its callers (how did we get here?)
   - Its data inputs (what state triggers this?)
6. **Gather evidence** -- collect logs, error messages, stack traces, and relevant state
7. **Identify root cause** -- distinguish between the symptom and the actual bug

> **Phase Gate**: You CANNOT propose ANY fix until the root cause is identified. If you cannot identify the root cause, gather more evidence. Do not guess.

#### Phase 2: Pattern Analysis

1. **Find working examples** -- search the codebase for similar code that works correctly
2. **Compare working vs broken** -- identify the specific difference between the working example and the broken code
3. **Check for systemic issues** -- look for similar patterns elsewhere that may have the same bug (these will be fixed in Step 5)

#### Phase 3: Hypothesis Testing

1. **Single hypothesis at a time** -- form one clear hypothesis about the fix, make the minimal change to test it
2. **Verify the hypothesis** -- run tests or manually confirm the fix addresses the root cause
3. **Track attempts** -- keep count of fix attempts

> **3-Fix Escalation Rule**: After 3 failed fix attempts, STOP. Do not attempt fix #4. Instead:
>
> 1. **Question the architecture**: "Is the approach fundamentally wrong?"
> 2. **Present findings**: Show the user evidence from all 3 attempts -- what was tried, what happened, why it failed
> 3. **Ask the user**: Request guidance on how to proceed before continuing
>
> This prevents the spiral of increasingly desperate changes that make the problem worse.

#### Phase 4: Implement the Fix

1. **Read the full file** before editing -- understand surrounding context
2. **Make minimal, targeted changes** -- fix the bug without refactoring unrelated code
3. **Match existing code style** -- follow patterns already in the file
4. **Handle edge cases** the bug reveals

**Test-first for non-trivial bugs** (logic errors, edge cases, race conditions):

1. Write a test that REPRODUCES the bug (test should FAIL)
2. Confirm the test fails for the right reason
3. Implement the fix
4. Run the test -- confirm it now PASSES
5. Run the full test suite

Skip the reproducing test for:

- Typo fixes, import corrections, config changes
- Bugs that are obvious and unlikely to recur
- Cases where the test would just duplicate the implementation

### Step 2: Validate the Fix

1. **Run tests**:

   ```bash
   # Run the project's configured test command
   <project-test-command>
   # Run the project's configured lint command
   <project-lint-command>
   ```

2. **If tests fail**, fix them -- determine if the test was wrong or if the fix introduced a regression
3. **If the change touches shared code**, run the full test suite

### Step 3: Verify Changes Take Effect

- Verify the application picks up the changes (auto-reload, rebuild, etc.)
- If database models changed: warn user about potential schema changes

### Step 4: Scan for Similar Patterns

**Scan scope strategy**:

1. **Same module first**: Start by searching files in the same directory/module as the bug. These are most likely to share the same pattern.
2. **Expand to related modules**: If the pattern is architectural (e.g., missing error handling on all API endpoints), expand to sibling modules and direct dependencies.
3. **Cap at 20 matches**: Stop collecting after 20 grep matches. If more than 20 matches are found, report the total count to the user (e.g., "Found 47 instances of this pattern — showing first 20. Consider a dedicated refactoring pass for the remaining 27.").
4. **Report findings**: For each match, note the file, line, and whether it has the same bug or is a false positive.

**Scan execution**:

1. **Search for the same bug pattern** elsewhere in the codebase:
   - If the bug was a missing null check, grep for other similar patterns
   - If the bug was a wrong API response shape, check other endpoints
2. **Fix any similar issues found** (within the 20-match cap)
3. **If no similar issues exist**, skip this step

### Step 5: Add Tests (Decision Tree)

Use this decision tree to determine whether to add a test:

```text
Is the fix a typo, import correction, or config change?
├── YES → Do NOT add a test. Stop.
└── NO → Continue.
    │
    Does an existing test already cover this code path?
    ├── YES → Do NOT add a new test. Verify the existing test passes. Stop.
    └── NO → Continue.
        │
        Could this bug recur (logic error, edge case, race condition)?
        ├── YES → Add a targeted regression test that:
        │         1. Reproduces the original bug (fails without the fix)
        │         2. Passes with the fix applied
        │         3. Is minimal — tests only the fixed behavior
        └── NO (one-off, unlikely to recur) → Do NOT add a test. Stop.
```

### Step 6: Commit

Stage only files you touched and commit:

```bash
git add <specific-files-you-modified>
git commit -F <commit-msg-file>
```

Write commit message file first, then use -F to avoid guard hook issues.

## Output Summary

After completing all steps, provide:

```text
## Fix Summary
- **Bug**: <what was broken>
- **Root cause**: <why it was broken>
- **Fix**: <what you changed>
- **Similar issues**: <found and fixed N / none found>
- **Tests added**: <yes: test_name / no: reason>
- **Files changed**: <list>
- **Commit**: <hash>
```

## Rules

- **Read before edit** -- always read the full file before modifying it
- **Minimal changes** -- fix the bug, nothing more
- **No speculative fixes** -- don't fix things that aren't broken
- **No over-engineering** -- a simple bug gets a simple fix
- **Preserve behavior** -- change only the broken behavior
- **Never skip validation** -- always run tests after the fix
