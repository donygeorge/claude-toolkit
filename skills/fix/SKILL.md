---
name: fix
description: Root-cause, fix, validate, scan for similar patterns, test, and commit a bug.
argument-hint: '"description of the bug" or paste an error/stack trace'
user-invocable: true
disable-model-invocation: true
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

**Distinct from `/solve`**: `/fix` is standalone (bug description -> root-cause -> fix -> scan similar -> test -> commit). `/solve` is GitHub issue workflow (fetch issue -> reproduce -> plan -> fix -> commit referencing issue).

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

### Step 3: Validate the Fix

1. **Run tests**:

   ```bash
   # Run the project's configured test command
   <project-test-command>
   # Run the project's configured lint command
   <project-lint-command>
   ```

2. **If tests fail**, fix them -- determine if the test was wrong or if the fix introduced a regression
3. **If the change touches shared code**, run the full test suite

### Step 4: Verify Changes Take Effect

- Verify the application picks up the changes (auto-reload, rebuild, etc.)
- If database models changed: warn user about potential schema changes

### Step 5: Scan for Similar Patterns

1. **Search for the same bug pattern** elsewhere in the codebase:
   - If the bug was a missing null check, grep for other similar patterns
   - If the bug was a wrong API response shape, check other endpoints
2. **Fix any similar issues found**
3. **If no similar issues exist**, skip this step

### Step 6: Add Tests (If Relevant)

Add a test ONLY if:

- The bug could recur (not a one-off typo)
- No existing test covers this code path
- The test is simple and targeted

Do NOT add tests for simple typo fixes, import corrections, or config changes.

### Step 7: Commit

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

## Rationalization Prevention

Catch yourself when you think any of these:

| Rationalization | Response |
| ------- | -------- |
| "Quick fix for now, investigate later" | Investigate NOW. Quick fixes become permanent. |
| "Just try changing X and see if it works" | That's guessing, not debugging. Identify root cause first. |
| "I don't fully understand but this might work" | If you don't understand, you can't verify the fix. |
| "One more fix attempt" (when already tried 2+) | After 3 failed fixes, question the architecture. |
| "The fix works in my test, ship it" | Run the FULL test suite. Edge cases exist. |
| "This is probably unrelated" | Verify it's unrelated. Assumptions hide root causes. |
| "Let me just revert and try something else" | Document what failed and WHY before reverting. |

## Rules

- **Read before edit** -- always read the full file before modifying it
- **Minimal changes** -- fix the bug, nothing more
- **No speculative fixes** -- don't fix things that aren't broken
- **No over-engineering** -- a simple bug gets a simple fix
- **Preserve behavior** -- change only the broken behavior
- **Never skip validation** -- always run tests after the fix
