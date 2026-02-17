---
name: verify
description: Use after completing implementation, bug fixes, or any code changes to verify correctness.
argument-hint: "[plan-file | commit-range | uncommitted] [--quick]"
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - TodoWrite
---

# Verify Skill

Deep verification of code changes. Runs checks, scans for edge cases, fixes issues directly, and asks the user when unsure. Produces an inline summary -- no report files.

**Distinct from hooks**: Hooks like `task-completed-gate` and `verify-completion` run automatically on lifecycle events. `/verify` is an explicit, thorough verification you invoke after completing work.

## Two Modes

| Mode | Invocation | Purpose |
| ---- | ---------- | ------- |
| **Deep** (default) | `/verify`, `/verify docs/plans/my-feature.md` | Full verification -- edge case scan, clean-room agent, thorough checks. Use after `/implement`, `/solve`, `/fix`, or any manual work. |
| **Quick** | `/verify --quick`, `/verify docs/plans/my-feature.md --quick` | Focused spec-compliance check -- tests pass, lint passes, exit criteria met, changes committed. Designed to be invoked programmatically from within `/implement` per-milestone. |

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Evidence over assertion** | Every claim must be backed by a command you ran and output you read. |
| **2. Fix what you find** | Do not just report issues. Fix them directly when the fix is unambiguous. |
| **3. Ask when unsure** | For ambiguous issues or judgment calls, present options to the user and wait. |
| **4. No report files** | Summarize findings inline in your response. Do not create artifact files. |
| **5. Generic skill** | No project-specific content in this file. |

### Forbidden Language

Do NOT use any of these phrases in your output:

- "should" / "should be"
- "probably" / "probably fine"
- "seems to" / "seems like"
- "likely" / "most likely"
- "I think" / "I believe"
- "looks good" / "looks correct"

Replace with concrete evidence: "Tests pass (14/14)" not "Tests should pass." "The null check exists at line 42" not "It seems to handle nulls."

---

## Aliases

```yaml
aliases:
  /verify: /verify
  /check: /verify

defaults:
  mode: deep
```

## Usage

### Slash Commands

```bash
/verify                                   # Verify uncommitted changes (deep)
/verify docs/plans/my-feature.md          # Verify plan exit criteria (deep)
/verify abc123..def456                    # Verify commit range (deep)
/verify --quick                           # Quick check of uncommitted changes
/verify docs/plans/my-feature.md --quick  # Quick spec-compliance check
```

### Natural Language

```text
"verify my changes"
"check that everything passes"
"verify the implementation plan is complete"
"quick check before I commit"
```

## Arguments

| Argument | Description |
| -------- | ----------- |
| `<scope>` | Optional. Plan file path, commit range (`abc..def`), or omitted for uncommitted changes |
| `--quick` | Run in quick mode (focused spec-compliance only) |

---

## Scope Inference

The skill determines what to verify based on the argument:

### 1. Plan-Based Scope

**Trigger**: Argument is a path to a plan file (e.g., `docs/plans/my-feature.md`)

```text
1. Read the plan file
2. Extract all milestones and their exit criteria
3. Check plan state file (artifacts/execute/<plan>/plan_state.json) if it exists
4. Verify each exit criterion independently
5. Run test and lint commands
6. (Deep mode) Spawn clean-room agent, scan edge cases
```

### 2. Commit-Based Scope

**Trigger**: Argument contains `..` (commit range syntax, e.g., `abc123..def456`)

```text
1. Run: git log --oneline <range>
2. Run: git diff <range> -- to get full diff
3. Verify all changes in the range
4. Check for uncommitted changes on top
5. Run test and lint commands
6. (Deep mode) Scan diff for edge cases, spawn clean-room agent
```

### 3. Uncommitted Scope

**Trigger**: No argument, or argument is `uncommitted`

```text
1. Run: git status
2. Run: git diff (unstaged) and git diff --cached (staged)
3. Verify all uncommitted changes
4. Run test and lint commands
5. (Deep mode) Scan diff for edge cases, spawn clean-room agent
```

### 4. Within /implement (Quick Mode)

**Trigger**: Invoked programmatically with `--quick` and a plan file

```text
1. Read the plan and identify the current milestone
2. Check only that milestone's exit criteria
3. Run test and lint commands
4. Report pass/fail -- no clean-room agent, no edge case scan
```

---

## Verification Gate Function

Every claim of "done" or "working" MUST pass through this 5-step gate. Do not skip steps. Do not combine steps.

### Step 1: IDENTIFY

Identify the specific command or check that would prove the claim.

```text
Claim: "Tests pass"
Gate: What is the project's test command? Find it.
```

### Step 2: RUN

Execute the command. Do not assume the result.

```text
Run: <project-test-command>
Capture: full stdout and stderr
```

### Step 3: READ

Read the actual output. Do not skim. Do not summarize prematurely.

```text
Read: the complete output
Note: exit code, pass/fail counts, error messages, warnings
```

### Step 4: VERIFY

Compare the output against the claim. Does the evidence support the claim?

```text
Check: Did ALL tests pass? Not just "most"?
Check: Any skipped tests? Any warnings treated as non-fatal?
Check: Did the command actually run the relevant tests?
```

### Step 5: CLAIM

Only now state the result, with evidence.

```text
VERIFIED: Tests pass (47/47, 0 skipped, exit code 0)
-- or --
FAILED: 2 tests failing (test_auth_flow, test_session_timeout)
```

### Gate Application Table

Apply the gate to every verification check:

| Check | IDENTIFY | RUN | READ | VERIFY | CLAIM |
| ----- | -------- | --- | ---- | ------ | ----- |
| Tests pass | Find test command | Execute it | Read output | All pass? No skips? | State result with counts |
| Lint passes | Find lint command | Execute it | Read output | Zero errors? Zero warnings? | State result with counts |
| Changes committed | `git status` | Execute it | Read output | Clean working tree? | State result |
| Exit criterion met | Read criterion text | Find evidence | Read evidence | Does evidence satisfy criterion? | State with file/line reference |
| Edge case handled | Identify edge case | Find code path | Read implementation | Does it handle the case? | State with code reference |

---

## Rationalization Prevention Table

When verifying, you will be tempted to rationalize away issues. Recognize these patterns and respond with the rebuttal.

| Rationalization | Rebuttal |
| --------------- | -------- |
| "The test failure is unrelated to my changes" | Run `git stash` and re-run tests. If they still fail, it is pre-existing. If they pass, your changes broke it. Prove it either way. |
| "That edge case is unlikely in practice" | Unlikely is not impossible. Check if input validation prevents it. If not, handle it or document why it is acceptable. |
| "The lint warning is just style, not a real issue" | Run the linter. If it produces warnings, either fix them or confirm the project ignores that rule. Zero warnings is the target. |
| "It works when I test it manually" | Manual testing is not verification. Run the automated test suite. If no automated tests cover this path, that is a finding. |
| "The exit criterion is vaguely worded, so this counts" | Read the criterion literally. If the implementation does not clearly satisfy the literal text, it is not met. Ask the user to clarify if genuinely ambiguous. |
| "This is a pre-existing issue, not introduced by these changes" | Verify with `git diff` or `git stash`. If it is truly pre-existing, note it as a pre-existing issue but do not count it as verified. |
| "The code handles this implicitly through another mechanism" | Trace the execution path. Show the specific code that handles it. If you cannot point to a line, it is not handled. |
| "I already checked this earlier" | Check it again now. State has changed since "earlier." Re-run the command and read the current output. |
| "The documentation says this is expected behavior" | Read the documentation. Quote the specific passage. Verify it matches the actual behavior by running the code. |
| "One more small change and it will work" | Stop. Run the gate function on the current state. Is it working NOW? If not, fix it before claiming progress. |

---

## Deep Mode Execution Flow

### Step 1: Determine Scope

Parse the argument to determine plan-based, commit-based, or uncommitted scope (see Scope Inference above).

### Step 2: Gather Changes

```text
FOR plan-based scope:
  1. Read plan file, extract exit criteria
  2. Read plan state file if it exists
  3. Run: git diff <base-branch>..HEAD (or appropriate range)

FOR commit-based scope:
  1. Run: git log --oneline <range>
  2. Run: git diff <range>

FOR uncommitted scope:
  1. Run: git status
  2. Run: git diff
  3. Run: git diff --cached
```

### Step 3: Run Verification Gate on Standard Checks

Apply the 5-step gate to each:

1. **Tests pass** -- IDENTIFY the test command, RUN it, READ output, VERIFY all pass, CLAIM with counts
2. **Lint passes** -- IDENTIFY the lint command, RUN it, READ output, VERIFY zero errors, CLAIM with counts
3. **Changes committed** -- RUN `git status`, READ output, VERIFY clean tree (or note uncommitted changes)

### Step 4: Exit Criteria Verification (Plan-Based Only)

For each exit criterion in the plan:

```text
1. Read the criterion text literally
2. Find evidence in the codebase (file exists, test exists, behavior implemented)
3. Apply the verification gate: can you point to specific code/files that satisfy this?
4. If YES: mark as VERIFIED with file:line reference
5. If NO: mark as UNMET and attempt to fix (see Fix-or-Ask Workflow)
6. If AMBIGUOUS: ask the user to clarify
```

### Step 5: Edge Case Scan

Read the full diff and scan for:

| Category | What to Look For |
| -------- | ---------------- |
| **Null/nil handling** | New parameters, return values, or fields that could be null but lack checks |
| **Error paths** | New operations that could fail (I/O, network, parsing) without error handling |
| **Boundary conditions** | Off-by-one errors, empty collections, zero values, maximum values |
| **Input validation** | New user inputs or API parameters accepted without validation |
| **Resource cleanup** | Opened files, connections, or locks that may not be closed on error paths |
| **Concurrency** | Shared mutable state accessed without synchronization |
| **Type safety** | Type coercions, unchecked casts, or implicit conversions |
| **Security** | Hardcoded secrets, unsanitized inputs, missing auth checks |

For each finding:
- Note the file, line, and category
- Assess severity: **high** (crash/security), **medium** (incorrect behavior), **low** (code quality)
- Apply the Fix-or-Ask Workflow

### Step 6: Clean-Room Verification

Spawn a fresh agent with zero context from the implementation process. This agent reads all changed files independently and looks for issues the implementer may have been blind to.

```text
Task:
  subagent_type: "code-reviewer"
  prompt: |
    You are a clean-room verifier. You have NO context about the implementation
    process -- you are seeing these changes for the first time.

    Review all changed files listed below. For each file:
    1. Read the entire file (not just the diff)
    2. Check: does the code do what the surrounding context indicates it must do?
    3. Look for: missing error handling, incorrect logic, inconsistent naming,
       incomplete implementations, dead code, missing imports
    4. Check: are there any TODO/FIXME/HACK comments that indicate unfinished work?
    5. Verify: do function signatures match their callers?

    Changed files:
    <list of changed files from git diff --name-only>

    Report your findings as a numbered list. For each finding, include:
    - File and line number
    - What you found
    - Severity: high / medium / low

    If you find NO issues, state: "Clean-room review: no issues found."
    Do not use hedging language ("might", "could", "possibly").
    State findings as facts or do not state them.
```

### Step 7: Fix-or-Ask Workflow

Process all findings from Steps 3-6:

```text
FOR each finding:
  IF fix is unambiguous (missing null check, unclosed resource, obvious typo):
    1. Fix it directly using Edit/Write
    2. Re-run relevant tests
    3. Note: "FIXED: <description> in <file>:<line>"

  ELIF fix requires judgment (design choice, API change, behavior change):
    1. Present the issue to the user with:
       - What was found (with file:line reference)
       - Why it matters (severity and impact)
       - 2-3 concrete options for resolution
    2. Wait for user input
    3. Apply the chosen fix
    4. Re-run relevant tests

  ELIF finding is informational (code quality, style preference):
    1. Note it in the summary but do not fix
    2. Label as "NOTE" not "ISSUE"
```

### Step 8: Re-Verify After Fixes

If any fixes were applied in Step 7:

```text
1. Re-run the verification gate on tests and lint
2. Re-run git status to confirm changes are tracked
3. If new issues emerge from fixes, apply Fix-or-Ask again (max 2 rounds)
```

### Step 9: Summary

Present an inline summary (do NOT create files):

```text
## Verification Summary

**Scope**: <plan-based | commit-based | uncommitted>
**Mode**: deep

### Standard Checks
- Tests: VERIFIED (47/47 pass, 0 skipped)
- Lint: VERIFIED (0 errors, 0 warnings)
- Git status: <clean | N uncommitted files>

### Exit Criteria (plan-based only)
- [x] Criterion 1 — VERIFIED (evidence: src/auth.py:42)
- [x] Criterion 2 — VERIFIED (evidence: tests/test_auth.py exists, 3/3 pass)
- [ ] Criterion 3 — UNMET (reason: feature not implemented)

### Edge Case Scan
- FIXED: Missing null check in src/parser.py:78
- FIXED: Unclosed file handle in src/loader.py:112
- NOTE: No input validation on API endpoint (low severity, existing pattern)

### Clean-Room Review
- No issues found / N issues found (M fixed, K noted)

### Issues Requiring User Input
- <description> (options presented above, awaiting decision)

### Verdict
PASS — all checks verified, N issues fixed, M notes recorded
-- or --
FAIL — N unresolved issues remain (listed above)
```

---

## Quick Mode Execution Flow

Quick mode runs a subset of deep mode. No clean-room agent, no edge case scan.

### Step 1: Determine Scope

Same as deep mode (see Scope Inference).

### Step 2: Run Verification Gate on Standard Checks

Apply the 5-step gate to:

1. **Tests pass**
2. **Lint passes**
3. **Changes committed**

### Step 3: Exit Criteria Check (Plan-Based Only)

For each exit criterion:

```text
1. Read the criterion text
2. Find evidence (file exists, test passes, behavior present)
3. Mark as VERIFIED or UNMET
4. If UNMET: attempt fix (1 round only)
```

### Step 4: Summary

```text
## Quick Verification

- Tests: VERIFIED (47/47)
- Lint: VERIFIED (0 errors)
- Committed: YES / NO
- Exit criteria: 5/5 met / 4/5 met (criterion 3 unmet: <reason>)

Verdict: PASS / FAIL
```

---

## Error Handling

| Error | Recovery |
| ----- | -------- |
| No test command found | Ask user for the test command. Do not skip testing. |
| No lint command found | Note "no lint command configured" in summary. Not a failure. |
| Test command fails to run (not test failures) | Report the error. Distinguish between "tests failed" and "test runner crashed." |
| Plan file not found | Fall back to uncommitted scope. Inform user. |
| Plan state file missing | Verify against plan exit criteria only (no milestone state). |
| Git not initialized | Report error. Cannot verify without git. |
| Clean-room agent fails to spawn | Skip clean-room review. Note in summary: "Clean-room review skipped (agent spawn failed)." |
| Commit range invalid | Report error with git's error message. Ask user to correct. |
| No changes to verify | Report: "No uncommitted changes and no scope specified. Nothing to verify." |

---

## Integration with Other Skills

### After /implement

```text
/verify docs/plans/my-feature.md
```

Reads the plan state, verifies all milestones and evaluation criteria. The deep mode clean-room agent catches issues that per-milestone verification missed.

### After /solve or /fix

```text
/verify
```

Verifies uncommitted changes or the most recent commit. Checks for missing test coverage, edge cases in the fix, and similar patterns elsewhere.

### Within /implement (Quick Mode)

```text
/verify docs/plans/my-feature.md --quick
```

Invoked programmatically per-milestone to check spec compliance. Runs tests, lint, and exit criteria checks without the overhead of clean-room agents or edge case scanning.

### Standalone

```text
/verify
/verify abc123..def456
```

Verifies any code changes -- manual edits, refactoring, or any work not tracked by a plan file.
