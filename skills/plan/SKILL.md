---
name: plan
description: Creates detailed implementation plans with milestones, exit criteria, and architecture decisions. Saves to docs/plans/ for use with /implement.
argument-hint: "<feature-name>"
user-invocable: true
disable-model-invocation: true
---

# Plan Skill

Creates detailed implementation plans for major features with milestones, exit criteria, testing requirements, and architecture decisions. Does NOT implement — only plans.

**Output**: Plans are saved to `docs/plans/<feature-name>.md` in the format expected by the `/implement` skill.

## Aliases

```yaml
aliases:
  /plan: /plan
  /feature-plan: /plan

defaults:
  output_dir: docs/plans
  feedback_iterations: 10
```

## Usage

### Slash Commands

```bash
/plan <feature-name>           # Plan a new feature
/plan user-notifications       # Example: plan notifications feature
/plan refactor-auth-system     # Example: plan a refactor
```

### Natural Language

```text
"plan a notifications feature"
"create a plan for user preferences"
"help me plan the dark mode implementation"
```

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. NEVER implement** | This skill only produces plan documents. Do not write any code. |
| **2. Ask questions FIRST** | Before any research or planning, ask ALL clarifying questions in one batch |
| **3. Save to docs/plans/** | Always write plan to `docs/plans/<feature-name>.md` |
| **4. Implement-compatible format** | Plans MUST use the milestone/exit-criteria format the `/implement` skill expects |
| **5. Thorough evaluation criteria** | Every plan MUST end with specific, testable evaluation criteria |
| **6. No time estimates** | Focus on what, not when |

---

## Execution Flow

### Phase 0: Clarify Requirements

**Before doing ANY research or planning:**

1. Read the user's request carefully
2. Identify ambiguities, unknowns, or decisions that need user input
3. Ask ALL clarifying questions in ONE batch — cover:
   - Scope boundaries (what's in/out)
   - Technical constraints or preferences
   - Integration points with existing code
   - Priority trade-offs (simplicity vs features vs performance)
4. Wait for answers before proceeding

**Do NOT skip this phase.** Making assumptions leads to wasted planning.

### Phase 1: Research

1. **Codebase exploration** (automatic, no prompts)
   - Read existing code to understand patterns, architecture, conventions
   - Identify files that will need modification
   - Find reusable functions, utilities, and abstractions
   - Check CLAUDE.md and rules for project conventions

2. **External research** (if applicable)
   - Use WebSearch to research best practices
   - Use WebFetch to get documentation for relevant libraries
   - Use context7 MCP tools for library-specific docs

3. **Create initial plan draft**
   - Launch plan agent via Task tool
   - Agent writes plan to `docs/plans/<feature-name>.md`

### Phase 2: Feedback Loop (Codex)

After the initial plan is created, iterate with codex for feedback:

**Loop Rules**:

- Maximum 10 iterations
- Stop early if codex says "no major issues" or "plan looks solid"
- Incorporate feedback and regenerate plan each iteration
- Track iteration count and feedback summary

### Phase 3: Agent Reviews

After codex feedback loop completes, optionally run:

- Architecture review (architect agent)
- Security review (security agent)
- Product review (pm agent)

### Phase 4: Finalize Plan

1. Incorporate agent feedback
2. Update plan status to "In Review"
3. Present final plan to user with summary of what was planned
4. **Do NOT start implementing** — tell the user to run `/implement docs/plans/<feature-name>.md` when ready

## Codex Feedback Loop

Codex should be configured as a project MCP server in `.mcp.json`.

### How to Invoke Codex

Use the `mcp__codex__codex` tool with:

- `approval-policy: "never"` (required for autonomous operation)
- `prompt`: review prompt focusing on completeness, testing, risks, dependencies, over-engineering

### Iteration Rules

| Rule | Value |
| ---- | ----- |
| Maximum iterations | 10 |
| Stop early when | Response starts with "SOLID:" |
| Continue when | Response starts with "ISSUES:" |

### If Codex Unavailable

1. Log: "Codex unavailable — skipping automated feedback"
2. Run architect, security, and pm agents for review instead
3. Present plan with note: "Manual review recommended"

## Output Location

Plans are saved to: `docs/plans/<feature-name>.md`

Naming convention:

- Use kebab-case: `user-notifications.md`, `dark-mode.md`

## Plan Template

The plan MUST follow this structure to be compatible with `/implement`:

```markdown
# [Feature Name] — Implementation Plan

> **Status**: Draft | In Review | Approved | In Progress | Complete
>
> **Last Updated**: [Date]
>
> **Codex Iterations**: [N of 10]

## Summary

[1-3 sentence description of what this plan achieves]

## North Star

[The ideal end state — what does success look like?]

## Principles

[3-5 design principles guiding implementation decisions]

## Research Findings

### Best Practices
### Libraries Considered

## Architecture

### System Overview
### Data Flow
### Key Files

[List specific files to create/modify with paths]

## Implementation Milestones

### M0: [Foundation/Setup]

[Description of what this milestone achieves]

**Files to create/modify**:

- `path/to/file.py` (description)

**Exit Criteria**:

- [ ] Specific, testable criterion 1
- [ ] Specific, testable criterion 2
- [ ] Tests pass: `<test command>`

### M1: [Core Feature]

[Same structure as M0...]

### M2: [Integration/Polish]

[Same structure as M0...]

## Testing Strategy

### Unit Tests
### Integration Tests
### Manual Verification

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| Risk 1 | Mitigation 1 |

## Open Questions

- [Any unresolved questions — ideally none by finalization]

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **Criterion**: specific testable statement
2. **Criterion**: specific testable statement

### Code Quality

1. **Criterion**: specific testable statement

### User Experience

1. **Criterion**: specific testable statement

---

## Feedback Log

[Summary of codex/agent feedback incorporated]
```

### Template Rules

- **Milestones**: Use M0, M1, M2... naming. Each must have exit criteria as checkboxes.
- **Exit criteria**: Must be specific and testable — "tests pass", "file exists", "command runs successfully". Never vague ("works correctly", "is good").
- **Files**: List specific file paths in each milestone, not just descriptions.
- **Evaluation criteria**: Grouped by category (functional, quality, UX). Each must be independently verifiable.
- **Blank lines around lists**: Always add a blank line before and after markdown lists (lint requirement).

## Constraints

- **No implementation**: This skill only produces plans — never write code
- **No time estimates**: Focus on what, not when
- **Ask first, plan second**: Always clarify requirements before researching
- **Automatic research**: Web search runs without prompting (after questions are answered)
- **Clear exit criteria**: Every milestone must have testable checkboxes
- **Maintainability first**: Prefer simple over clever
- **Implement-compatible**: Plans must work with `/implement docs/plans/<name>.md`
