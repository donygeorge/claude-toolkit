---
name: fix-github
description: Use when working on one or more GitHub issues.
argument-hint: "<github-issue-url-or-number>"
user-invocable: true
---

# Fix GitHub Issue Skill

Autonomously work on GitHub issues: fetch details, understand context, reproduce visual issues,
plan, implement, test, review, and commit. Supports multiple issues in a single invocation.

## Core Philosophy

**Fix the bug AND consider if prevention is warranted.**

For each fix, ask: "Would a test or code change have caught this before shipping?"

**When to add prevention**:

- Logic bugs that could recur -> Unit test
- Data flow issues -> Integration test
- Repeated pattern across codebase -> Architectural fix
- Crashes or data loss -> Defensive validation

**When NOT to add tests**:

- One-off typos or copy errors
- Simple UI tweaks (spacing, colors)
- Issues already covered by existing tests
- Fixes where the test would just duplicate the implementation
- Cases where the bug was obvious and unlikely to recur

## Aliases

```yaml
aliases:
  /fix-github: /fix-github
  /fix-github: /fix-github

defaults:
  skip_review: false
  plan_only: false
```

> **Customization**: Override defaults in `toolkit.toml` under `[skills.fix-github]`. Run `bash toolkit.sh customize skills/fix-github/SKILL.md` to take full ownership of this skill.

> **Note**: `/fix` is a separate skill for standalone bug fixes without GitHub integration. Use `/fix-github` for GitHub issue workflows.

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Root cause before fix** | Identify the root cause of each issue before proposing any code changes. |
| **2. One issue at a time** | When solving multiple issues, fully complete one before starting the next. |
| **3. Reference the GitHub issue** | Every commit message must include `Fixes #N` or `Closes #N` for the issue being solved. |
| **4. Reproduce before fixing** | Confirm the bug exists (visually or via code analysis) before attempting a fix. |
| **5. Stage only your files** | Use `git add <specific-files>`, never `git add .` or `git add -A`. |

### Rationalization Prevention

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "The issue is too complex to reproduce" | Skipping reproduction leads to fixes that mask symptoms instead of addressing root causes | Trace the code path statically with Grep/Read; reproduce via CLI or API calls; document the traced path |
| "This looks like a duplicate of issue #X" | Assumed duplicates may share symptoms but have different root causes; closing prematurely loses a real bug | Verify root cause matches by comparing code paths in both issues; only mark duplicate if the fix for #X provably resolves this issue |
| "The fix is obvious from the stack trace, skip investigation" | Stack traces show where code failed, not why; the root cause is often upstream of the crash site | Follow the full investigation flow: read the issue, trace the code path, identify the root cause, then plan the fix |
| "The existing tests pass, so the fix is correct" | Existing tests were written before this bug existed; they may not cover the failing scenario | Write a new test that reproduces the specific bug scenario; verify it fails without the fix and passes with it |
| "I cannot access the GitHub issue, so I will guess the requirements" | Guessing requirements leads to fixes that do not match what was reported | Use `gh issue view` to fetch the issue; if GitHub is unreachable, stop and ask the user for the issue details |

---

## Usage

### Single Issue

```bash
/fix-github 123                    # Work on GitHub issue #123
/fix-github 123 --plan-only        # Just create a plan, don't implement
/fix-github 123 --skip-review      # Skip review at end (faster)
```

### Multiple Issues

```bash
/fix-github 123, 145               # Work on multiple issues together
/fix-github 123 145                # Alternative syntax (space-separated)
/fix-github 123, 145 --plan-only   # Plan both issues without implementing
```

When multiple issues are specified:

- Issues are analyzed together for context, but fixed one at a time
- Each issue gets its own commit with `Fixes #N` reference
- QA and review agents run after the final issue is fixed

## Arguments

| Argument | Description |
| ---------- | ------------- |
| `<issue_numbers>` | One or more GitHub issue numbers (comma or space separated) |
| `--plan-only` | Create plan but don't implement (for review) |
| `--skip-review` | Skip review at end |

## Execution Flow

### Step 0: Ensure Server is Running (if applicable)

Check if a development server is needed and running.

### Step 1: Fetch Issues & Related Context

```bash
gh issue view <number> --json title,body,labels,state,comments
```

Extract from each issue:

- Title and description
- Labels
- Comments (may contain logs, screenshots, reproduction steps)
- Any structured diagnostics

**Check for Related Issues**:

```bash
gh issue list --search "<key terms from title>" --state all --limit 10
```

### Step 2: Download & Analyze Attachments

For any images referenced in issue body:

1. Download images to temporary directory
2. Validate image files before reading
3. Analyze screenshots for visual context

### Step 3: Reproduce Issues

**You SHOULD attempt visual reproduction of issues before fixing them.**

#### For Web UI Issues

Use Playwright MCP tools to navigate and capture state.

#### For Backend-Only Issues

Skip visual reproduction if purely backend logic.

#### When Visual Tools Are Unavailable

If Playwright or other visual tools are not configured or fail to initialize:

1. **Analyze code paths statically** -- trace the reported issue through the codebase using Grep/Read
2. **Check logs and error output** -- reproduce via CLI or API calls where possible
3. **Review test coverage** -- find existing tests that exercise the affected code path
4. **Document the limitation** -- note in the commit that visual reproduction was not performed and why

Do NOT block on visual tool availability. Code analysis and static tracing are valid reproduction strategies.

#### Document Reproduction Status

- **If reproduced visually**: Note exact steps taken and continue
- **If reproduced via code analysis**: Note the traced code path and continue
- **If NOT reproduced**: Still analyze code, note uncertainty in commit

### Step 4: Understand Context

Based on issue labels, identify relevant code areas using Grep/Glob/Read tools.

### Step 5: Create Plan

Design the implementation:

- For **bugs**: Follow systematic debugging phases -- investigate root cause, analyze patterns in working code, form a hypothesis, then plan the minimal fix. Do NOT plan a fix until the root cause is identified.
- For **features**: Follow existing patterns, design with tests
- For **crashes**: Defensive fix, error handling. Trace the crash path to find root cause before fixing.

If `--plan-only` is passed, stop here.

### Step 6: Implement

Make changes following project conventions:

- Match existing code style
- Use appropriate logging
- Handle errors gracefully
- Don't over-engineer

**For bugs**: Follow the systematic debugging phases (investigate root cause, analyze patterns, test hypothesis, then implement). Do NOT jump to a fix. Identify the root cause first, find working examples of similar code, and form a single clear hypothesis before making changes.

**Add tests to prevent recurrence** where appropriate.

### Step 7: Test

```bash
# Run the project's configured test command
<project-test-command>

# Run the project's configured lint command
<project-lint-command>
```

If tests fail, attempt to fix (max 3 iterations).

> **3-Fix Escalation Rule**: If tests still fail after 3 fix attempts, STOP. Do not attempt fix #4. Instead:
>
> 1. **Question the approach**: "Is the architecture or fix strategy fundamentally wrong?"
> 2. **Present findings**: Show the user what was tried in each attempt and why it failed
> 3. **Ask the user**: Request guidance before continuing
>
> This prevents increasingly desperate changes that compound the problem.

### Step 8: Verify Fixes

Verify fixes using the same approach used in Step 3. If visual tools were used for reproduction, use them again to confirm the fix. If code analysis or CLI reproduction was used instead, verify through the same method.

### Step 9: QA Review

Analyze the diff for correctness, security, and convention violations.
Fix any high-severity issues found.

### Step 10: Commit

```bash
git add <relevant files>
git commit -F <commit-msg-file>
```

**Staging Policy (CRITICAL)**:

Only stage files YOU modified:

```bash
# CORRECT: Stage specific files
git add src/services/data_service.py tests/test_data.py

# WRONG: Never use git add . or git add -A
```

**DO NOT PUSH** - user reviews and pushes manually.

### Step 11: Comment on GitHub Issue (Optional)

Add a resolution comment summarizing the fix.

## Output Summary (MANDATORY)

After completion, output:

- **Issues addressed**: List of issue numbers and titles
- **Reproduction status**: Whether issues were reproduced
- **Files changed**: List of modified files
- **Tests added/modified**: New or updated tests
- **Recurrence prevention**: What was added to prevent similar bugs
- **Items needing user attention**: Anything that couldn't be resolved
- **Suggested next steps**: Push, create PR, etc.

## Error Handling

| Error | Action |
| ----- | ------ |
| Issue not found | Report error, continue with others if multiple |
| Cannot reproduce | Analyze code anyway, note uncertainty |
| Tests fail | Attempt fix, max 3 iterations |
| Lint errors | Auto-fix with formatter, retry |
| Build fails | Analyze errors, attempt fix |

## Cannot Fix Scenarios

If unable to fix an issue:

1. **Document what was tried**
2. **Explain the blocker**
3. **Provide analysis** of likely root cause
4. **Suggest next steps** for the user
5. **Do NOT commit partial/broken fixes**

## Completion Checklist (VERIFY BEFORE FINISHING)

- [ ] **Tests pass**: Project test command ran successfully
- [ ] **Lint passes**: Linter ran successfully
- [ ] **Review completed** (unless `--skip-review`)
- [ ] **Review findings addressed**: High-severity issues fixed
- [ ] **Commit created**: With proper message and issue references
- [ ] **Summary output**: Full Output Summary provided to user
