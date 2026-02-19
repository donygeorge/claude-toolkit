---
name: implement
description: Use when you have an approved plan file and are ready to build.
argument-hint: "<plan-file> [milestone] [--continue]"
user-invocable: true
model: opus
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Task
  - TodoWrite
  - mcp__codex__codex
  - mcp__codex__codex-reply
---

# Implement Skill V3

Execute complete plans autonomously with multi-milestone support, per-milestone reviews, and resume capability.

---

## Overview

This skill executes implementation plans using a **two-tier orchestration model**:

1. **Plan Executor** (top-level): Minimal context, manages plan state, spawns milestone agents
2. **Milestone Orchestrator** (per-milestone): Fresh context per milestone, does the actual implementation

This architecture enables long-running sessions (2-3+ hours) without context exhaustion.

## Two-Tier Architecture (ENFORCED)

1. **Plan Executor** (top-level, YOU): **Cannot write or edit files** -- Write and Edit tools are intentionally not listed in allowed-tools. You manage state, spawn agents, report status.
2. **Milestone Orchestrator** (per-milestone): Fresh context per milestone via Task() agent, does ALL implementation work.

> **WHY**: Write/Edit are intentionally not listed so the Plan Executor physically cannot implement code inline. ALL code changes MUST go through Task() agents. Task-spawned milestone agents inherit full tool access (including Write, Edit, and all other tools) regardless of the Plan Executor's allowed-tools list.
>
> For the full milestone orchestrator prompt template, read `.claude/skills/implement/milestone-template.md`.

---

## Critical Rules (READ FIRST)

**These rules are NON-NEGOTIABLE. Violating them = failed implementation.**

| Rule | Description |
| ------ | ------------- |
| **1. State file is truth** | Always read/write state files. Session can crash and resume. |
| **2. Fresh context per milestone** | Each milestone gets spawned as a fresh subagent |
| **3. QA after EVERY milestone** | Run QA agent after each milestone completes |
| **4. UX agent for UI changes** | If milestone has UI changes, run UX agent |
| **5. Codex review is MANDATORY** | Every milestone must have codex review before commit |
| **6. One commit per milestone** | Never batch multiple milestones in one commit |
| **7. Update plan file live** | Mark exit criteria complete as milestones finish |

### Rationalization Prevention

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "This milestone is trivial, I will implement it inline instead of spawning a Task agent" | Inline implementation violates the two-tier architecture; the Plan Executor cannot write files and must not accumulate implementation context | Spawn a Milestone Orchestrator via Task() for every milestone, regardless of perceived complexity |
| "The codex review found nothing important, skip the remaining iterations" | Codex feedback is cumulative; later iterations often catch cross-cutting issues that early iterations miss | Run all configured codex iterations (default 3); only stop early if the response starts with "SOLID:" |
| "The tests pass, so the milestone is complete" | Passing tests verify existing behavior but do not confirm exit criteria are met; exit criteria may require new files, documentation, or architectural changes | Verify every exit criterion from the plan independently after tests pass; use `/verify --quick` for spec compliance |
| "I will batch these two small milestones into one commit" | Batching violates one-commit-per-milestone; it makes rollback impossible for individual milestones and corrupts plan_state.json tracking | Create exactly one commit per milestone; update plan_state.json after each commit |
| "The QA agent will catch any issues, skip the self-review" | QA runs smoke-mode checks by default; it does not replace the codex review or the milestone's own verification steps | Run codex review, then QA agent, then verify exit criteria; each step catches different categories of issues |

---

## TDD Enforcement

Check the environment variable `$TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT` to determine TDD mode. This variable is set via `toolkit.toml` under `[skills.implement]` key `tdd_enforcement` and defaults to `"off"`.

When spawning each Milestone Orchestrator via Task(), include the appropriate TDD instruction in the prompt based on the enforcement level:

- **strict**: Include in each milestone agent prompt: "You MUST create test files BEFORE writing implementation code. Write failing tests that specify the expected behavior, then implement until tests pass. If you write implementation before tests, STOP and restructure. Violating this order means the milestone has failed."
- **guided**: Include in each milestone agent prompt: "RECOMMENDED: Write test files before implementation code. This catches bugs earlier and clarifies requirements. Proceed with implementation if tests-first is not feasible for this change."
- **off** (default): No additional TDD instructions added to milestone prompts. The existing test-first guidance in the milestone template's Phase 4 remains as-is.

> **Configuration**: Set `tdd_enforcement = "strict"` or `tdd_enforcement = "guided"` in `toolkit.toml` under `[skills.implement]` to enable TDD-first mode.

---

## Aliases

```yaml
aliases:
  /implement: /implement
  /impl: /implement
  /build: /implement
  /execute: /implement

defaults:
  codex_iterations: 3
  qa_mode: smoke
```

> **Customization**: Override defaults in `toolkit.toml` under `[skills.implement]`. Run `bash toolkit.sh customize skills/implement/SKILL.md` to take full ownership of this skill.

## Usage

### Slash Commands

```bash
/implement docs/plans/my-feature.md          # Start from first milestone
/implement docs/plans/my-feature.md M3       # Start from M3
/implement my-feature --continue             # Resume from state
/implement my-feature M3 --continue          # Resume specific milestone
```

### Natural Language

```text
"implement the feature upgrade plan"
"execute all milestones from my-feature plan"
"continue implementing my-feature"
"implement M2 from the my-feature plan"
```

## Arguments

| Argument | Description |
| ---------- | ------------- |
| `<plan>` | Plan file path or name (e.g., `my-feature.md` or `docs/plans/my-feature.md`) |
| `<milestone>` | Optional milestone to start from (e.g., `M1`, `M3`). Default: first pending |
| `--continue` | Resume from last state file checkpoint |
| `--skip-qa` | Skip QA agent (not recommended) |
| `--skip-ux` | Skip UX agent for UI milestones |
| `--codex <N>` | Codex review iterations (default: 3, max: 5) |

---

## Architecture

```text
                    PLAN EXECUTOR (Top Level)
                    ========================
                    - Minimal context
                    - Reads plan_state.json
                    - Spawns milestone agents
                    - Runs QA/UX after each
                    - Updates plan file
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
   +-------------+     +-------------+     +-------------+
   | Milestone   |     | Milestone   |     | Milestone   |
   | Orchestrator|     | Orchestrator|     | Orchestrator|
   | (M0)        |     | (M1)        |     | (M2)        |
   |             |     |             |     |             |
   | Fresh ctx   |     | Fresh ctx   |     | Fresh ctx   |
   | Full impl   |     | Full impl   |     | Full impl   |
   | -> Commit   |     | -> Commit   |     | -> Commit   |
   +-------------+     +-------------+     +-------------+
          |                   |                   |
          v                   v                   v
   +-------------+     +-------------+     +-------------+
   |  QA Agent   |     |  QA Agent   |     |  QA Agent   |
   |  (smoke)    |     |  (smoke)    |     |  (smoke)    |
   +-------------+     +-------------+     +-------------+
```

---

## State Files

### Plan-Level State

**Location**: `artifacts/execute/<plan-name>/plan_state.json`

```json
{
  "plan_file": "docs/plans/my-feature.md",
  "plan_name": "my-feature",
  "started_at": "<ISO-timestamp>",
  "current_milestone": "M2",
  "milestones": [
    {
      "id": "M0",
      "title": "Foundation",
      "status": "completed",
      "current_phase": "Phase 11",
      "phases_completed": ["Phase 0", "Phase 1", "Phase 2", "Phase 3", "Phase 4", "Phase 5", "Phase 6", "Phase 7", "Phase 8", "Phase 8b", "Phase 9", "Phase 10", "Phase 11"],
      "started_at": "<ISO-timestamp>",
      "completed_at": "<ISO-timestamp>",
      "commit": "abc123",
      "reviewer_passed": true,
      "qa_passed": true,
      "ux_passed": null
    }
  ],
  "blockers": [],
  "session_notes": []
}
```

---

## Execution Flow

### TIER 1: Plan Executor

#### Step 0: Initialize State

```bash
# 1. Parse plan file path
# 2. Create state directory
mkdir -p artifacts/execute/<plan-name>

# 3. If --continue: read existing state
# 4. If not: parse plan and initialize state
```

#### Step 1: Parse Plan

Read the plan file and extract all milestones. Write initial `plan_state.json`.

#### Step 2: Milestone Loop

```text
FOR each milestone in remaining_milestones:

  1. LOG: "Starting {milestone.id}: {milestone.title}"

  2. UPDATE plan_state.json: milestone.status = "in_progress"

  3. SPAWN Milestone Orchestrator via Task tool

  4. READ result from artifacts/execute/<plan>/<M#>/result.json

  5. IF milestone FAILED:
     - LOG failure reason
     - UPDATE plan_state.json with blocker
     - ASK user: "Milestone {M#} blocked: {reason}. Continue to next or stop?"

  6. IF milestone SUCCEEDED:
     - LOG: "{M#} completed. Commit: {hash}"

  7. RUN QA agent (unless --skip-qa)

  8. IF has_ui_changes AND NOT --skip-ux:
     RUN UX agent

  9. UPDATE plan file: mark exit criteria complete

  10. UPDATE plan_state.json

  11. CONTINUE to next milestone
END FOR
```

#### Step 2b: Completion Verification (`/verify --quick`)

After all milestones complete, invoke `/verify --quick` against the plan file to verify every exit criterion independently. The verify skill runs its own verification gate, rationalization prevention, and fix-or-ask workflow -- do not duplicate that logic here.

```text
1. Invoke: /verify <plan-file> --quick
2. The verify skill will:
   - Run test and lint commands through its verification gate
   - Check every plan-level exit criterion with evidence
   - Fix unambiguous issues directly
   - Ask the user about ambiguous issues
3. IF verify reports FAIL:
   - Review the failing criteria
   - Fix issues (max 2 rounds of fix-and-reverify)
4. IF verify reports PASS after fixes (or on first run):
   - Proceed to Step 2c
```

> **Adversarial framing**: The implementer finished suspiciously quickly. Verify everything independently. Assume nothing carried over from milestone work is trustworthy -- re-check it from scratch.

**Forbidden language in verification output** -- these phrases indicate unverified claims:

- "should work"
- "probably fine"
- "seems correct"
- "looks good"
- "I believe this is correct"

If you catch yourself writing any of these, STOP and run the actual check instead.

#### Step 2c: Final Sweep

Run up to 3 rounds of holistic review on the full diff, focusing on cross-milestone issues.

#### Step 2d: QA Deep (After All Milestones)

If any milestone touched UI/API/services, run QA agent in deep mode.

#### Step 2e: Version File Check

After all milestones complete and pass verification, check whether version files need updating. **Do NOT update versions automatically -- always ask the user first.**

```text
1. DETERMINE version file path:
   - If `project.version_file` is set in toolkit.toml, use that path
   - Otherwise, check for a VERSION file in the project root
   - If neither exists, skip version update (inform user)

2. CHECK for CHANGELOG.md:
   - Look in project root for CHANGELOG.md (or CHANGELOG)
   - If not found, ask user if they want one created

3. SUGGEST version bump:
   - Read current version from the version file
   - Analyze milestone scope to suggest bump level:
     - patch: bug fixes, documentation, minor improvements
     - minor: new features, non-breaking enhancements
     - major: breaking changes, architectural overhauls
   - Present suggestion to user with rationale

4. ASK user before updating:
   - "Plan completed all N milestones. Suggest version bump: X.Y.Z → A.B.C (minor).
     Update VERSION and CHANGELOG.md? [y/n/custom version]"
   - If user approves: update version file and prepend CHANGELOG entry
   - If user provides custom version: use that instead
   - If user declines: skip version update entirely

5. IF updating CHANGELOG.md:
   - Prepend a new version section at the top (below any header)
   - Summarize all milestones completed in this plan
   - Group changes by type: Added, Changed, Fixed, Improved
   - Include the date

6. COMMIT version changes separately:
   - Stage only version-related files (VERSION, CHANGELOG.md)
   - Use commit message: "Bump version to X.Y.Z"
   - This keeps version bumps separate from feature commits
```

> **Note**: Individual milestone orchestrators do NOT update VERSION or CHANGELOG.md. All version management is centralized here in the Plan Executor to avoid conflicts across milestones.

#### Step 3: Session Summary

Report milestones completed, commits created, reviews passed, tests added.

---

### TIER 2: Milestone Orchestrator

**The full prompt template is in `.claude/skills/implement/milestone-template.md`.**

When spawning a milestone orchestrator via Task(), read that file and inject its contents as the prompt, replacing the placeholder variables. If `$TOOLKIT_SKILLS_IMPLEMENT_TDD_ENFORCEMENT` is `"strict"` or `"guided"`, prepend the corresponding TDD instruction (see "TDD Enforcement" section above) to the milestone prompt before the Phase 0 section.

Key phases in the template (13 phases total):

- Phase 0: Prerequisites (git clean)
- Phase 1: Parse milestone from plan
- Phase 2: Architecture analysis
- Phase 3: Create todos from exit criteria
- Phase 4: Layer-by-layer implementation
- Phase 5: Full test suite
- Phase 6: UI verification
- Phase 7: Codex review (mandatory, max 3 iterations)
- Phase 8: Reviewer agent (mandatory, max 2 iterations)
- Phase 8b: Spec compliance verification (invoke `/verify --quick`)
- Phase 9: Documentation updates
- Phase 10: Exit criteria verification
- Phase 11: Commit with `git commit -F <file>` (not heredoc)

---

## Resume Capability

```text
IF --continue flag:
  1. Read artifacts/execute/<plan>/plan_state.json
  2. Find current_milestone
  IF milestone.status == "in_progress":
    - Read the milestone's phases_completed array to determine progress
    - Resume from the first phase NOT in phases_completed
    - Example: if phases_completed = ["Phase 0", "Phase 1", "Phase 2"],
      resume from Phase 3
    - Pass phases_completed to the Milestone Orchestrator so it skips
      already-completed phases
  ELSE:
    - Start next pending milestone (phases_completed will be empty)
```

---

## Reliability Mechanisms

### 1. State File as Truth

All progress written to disk immediately. Session can crash and resume.

### 2. Phase Validation

Before moving to next phase, validate previous phase completed.

### 3. Retry Logic

- Test failures: retry up to 3 times
- Lint failures: run formatter, retry once
- Codex issues: fix and retry up to 3 times

### 4. Graceful Degradation

| Failure | Recovery |
| --------- | ---------- |
| Codex unavailable | Warn, continue with extra self-review |
| Build fails | Save error to state, block milestone, ask user for guidance |
| Test flaky | Retry 3x, flag as potential flake |
| QA agent timeout | Log warning, continue |
| UX agent timeout | Log warning, continue |

> **Note**: Build failures MUST NOT skip the test phase. A build that fails means tests cannot run reliably. Block the milestone and surface the error to the user rather than proceeding with unknown state.

---

## Error Handling

| Error | Action |
| ------- | -------- |
| Plan file not found | Error with clear message, list available plans |
| Milestone not found | List available milestones in plan |
| Dependencies incomplete | Warn and ask user to proceed or not |
| Tests fail after retries | Save state, ask user for guidance |
| Codex unavailable | Skip codex, note in result |
| Milestone agent fails | Save partial state, ask user to retry or skip |

---

## Rollback

If a milestone produces broken code and was already committed, use these recovery steps:

### Rollback Last Milestone

```text
1. Identify the commit: read plan_state.json for the milestone's commit hash
2. Verify it's the most recent commit: git log --oneline -3
3. Revert the commit (creates a new revert commit, preserves history):
   git revert <commit_hash> --no-edit
4. Update plan_state.json: set milestone status to "reverted"
5. Inform user and ask how to proceed (retry, skip, or stop)
```

### Rollback Multiple Milestones

If several milestones need to be undone (e.g., M2 broke something introduced in M1):

```text
1. Find the commit BEFORE the first bad milestone in plan_state.json
2. Revert commits in reverse order (newest first):
   git revert <M2_hash> --no-edit
   git revert <M1_hash> --no-edit
3. Update plan_state.json for each reverted milestone
4. Ask user: restart from M1 with a different approach, or stop?
```

**NEVER use `git reset --hard`** — always use `git revert` to preserve history and avoid data loss. Only the user can authorize destructive git operations.
