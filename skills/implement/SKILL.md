---
name: implement
description: Executes implementation plans autonomously with multi-milestone support, testing, and reviews.
argument-hint: "<plan-file> [milestone] [--continue]"
user-invocable: true
disable-model-invocation: true
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

1. **Plan Executor** (top-level, YOU): **Cannot write or edit files** -- Write and Edit tools are removed from allowed-tools. You manage state, spawn agents, report status.
2. **Milestone Orchestrator** (per-milestone): Fresh context per milestone via Task() agent, does ALL implementation work.

> **WHY**: Write/Edit are intentionally excluded so the Plan Executor physically cannot implement code inline. ALL code changes MUST go through Task() agents. Milestone agents spawned via Task() DO have full Write/Edit tools available.
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
  "started_at": "2026-01-28T10:00:00Z",
  "current_milestone": "M2",
  "milestones": [
    {
      "id": "M0",
      "title": "Foundation",
      "status": "completed",
      "started_at": "2026-01-28T10:00:00Z",
      "completed_at": "2026-01-28T10:45:00Z",
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

#### Step 2b: Completion Verification (Clean-Room Agent)

After all milestones complete, spawn a fresh agent with ZERO implementation context to verify every exit criterion independently. Up to 2 fix rounds if gaps found.

#### Step 2c: Final Sweep

Run up to 3 rounds of holistic review on the full diff, focusing on cross-milestone issues.

#### Step 2d: QA Deep (After All Milestones)

If any milestone touched UI/API/services, run QA agent in deep mode.

#### Step 3: Session Summary

Report milestones completed, commits created, reviews passed, tests added.

---

### TIER 2: Milestone Orchestrator

**The full prompt template is in `.claude/skills/implement/milestone-template.md`.**

When spawning a milestone orchestrator via Task(), read that file and inject its contents as the prompt, replacing the placeholder variables.

Key phases in the template (12 phases total):

- Phase 0: Prerequisites (git clean)
- Phase 1: Parse milestone from plan
- Phase 2: Architecture analysis
- Phase 3: Create todos from exit criteria
- Phase 4: Layer-by-layer implementation
- Phase 5: Full test suite
- Phase 6: UI verification
- Phase 7: Codex review (mandatory, max 3 iterations)
- Phase 8: Reviewer agent (mandatory, max 2 iterations)
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
    - Resume milestone from last completed phase
  ELSE:
    - Start next pending milestone
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
| Build fails | Save error, skip tests, flag for user |
| Test flaky | Retry 3x, flag as potential flake |
| QA agent timeout | Log warning, continue |
| UX agent timeout | Log warning, continue |

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
