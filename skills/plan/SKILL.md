---
name: plan
description: Use when a feature or change needs a detailed implementation plan before building.
argument-hint: "<feature-name> [--auto-implement]"
user-invocable: true
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
/plan user-notifications --auto-implement  # Auto-spawn /implement after plan
```

### Natural Language

```text
"plan a notifications feature"
"create a plan for user preferences"
"help me plan the dark mode implementation"
```

## Flags

| Flag | Description | Default |
| ---- | ----------- | ------- |
| `<feature-name>` | Required. The feature or change to plan | -- |
| `--auto-implement` | After plan is finalized, automatically spawn `/implement` skill with the generated plan | off |

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
2. **Check for an existing idea document**: Look for `docs/ideas/<feature-name>.md` (produced by the `/brainstorm` skill).
   - **Slug normalization**: Normalize the feature name to a slug for matching: lowercase, replace spaces and underscores with hyphens, strip special characters (e.g., "User Notifications" becomes `user-notifications`).
   - **Exact match first**: Check for `docs/ideas/<slug>.md`.
   - **Glob fallback**: If no exact match, search with `docs/ideas/*{slug}*` to catch partial matches or naming variations (e.g., `docs/ideas/user-notifications-v2.md` would match slug `user-notifications`). If multiple matches, prefer the most recently modified file.
   - If found:
     - Read the idea doc fully — it contains research findings, evaluated approaches, a recommendation, constraints, and open questions
     - Use this as your starting context — the research phase can be significantly abbreviated
     - Reduce clarifying questions to only what the idea doc does NOT already cover (typically: scope boundaries and milestone granularity)
     - Reference the recommended approach as the starting architecture unless the user says otherwise
3. If NO idea doc exists, identify ambiguities, unknowns, or decisions that need user input
4. Ask ALL clarifying questions in ONE batch — cover:
   - Scope boundaries (what's in/out)
   - Technical constraints or preferences
   - Integration points with existing code
   - Priority trade-offs (simplicity vs features vs performance)
5. Wait for answers before proceeding

**Do NOT skip this phase.** Making assumptions leads to wasted planning.

### Phase 1: Research

1. **Codebase exploration** (automatic, no prompts)
   - Read existing code to understand patterns, architecture, conventions
   - Identify files that will need modification
   - Find reusable functions, utilities, and abstractions
   - Check CLAUDE.md and rules for project conventions

2. **External research** (if applicable)
   - If an idea doc was found in Phase 0, skip redundant web research — focus only on implementation-specific questions not covered by the idea doc (e.g., specific API signatures, library installation steps, integration patterns)
   - If no idea doc, use WebSearch to research best practices
   - Use WebFetch to get documentation for relevant libraries
   - Use context7 MCP tools for library-specific docs

3. **Create initial plan draft**
   - Launch plan agent via Task tool with `subagent_type: "general-purpose"` (the agent needs Read, Write, Edit, Grep, Glob, Bash, WebSearch, WebFetch, and context7 tools)
   - If an idea doc exists, include its recommended approach, research findings, and constraints in the agent prompt
   - Agent writes plan to `docs/plans/<feature-name>.md`

   **Plan agent Task() invocation**:

   ```text
   Task:
     subagent_type: "general-purpose"
     prompt: |
       You are a plan author. Create a detailed implementation plan for "{feature_name}".

       Write the plan to docs/plans/{feature_name}.md using the plan template format
       (milestones with exit criteria, evaluation criteria, etc.).

       ## Context
       {codebase_findings}
       {idea_doc_content_if_available}
       {user_requirements}

       ## Constraints
       {user_constraints_and_priorities}

       ## Rules
       - Follow the plan template structure exactly
       - Every milestone needs testable exit criteria as checkboxes
       - No time estimates -- focus on what, not when
       - List specific file paths in each milestone
       - End with evaluation criteria grouped by category
   ```

### Phase 2: Feedback Loop (Codex)

After the initial plan is created, iterate with codex for feedback:

**Loop Rules**:

- Maximum 10 iterations
- Stop early if codex response starts with "SOLID:"
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
4. **Auto-flow to /implement** (if `--auto-implement` flag is set):

   IF `--auto-implement` is set:

   Spawn a fresh Task agent with clean context to run the implement skill. The agent must read the skill file itself — do not pass session state or planning context.

   ```text
   Task:
     subagent_type: "general-purpose"
     prompt: |
       Read the skill file at skills/implement/SKILL.md, then execute /implement with
       the plan at docs/plans/<feature-name>.md.
       Start fresh — do not assume any context from a previous session.
   ```

   ELSE (flag not set):

   Display: `Next step: Run /implement docs/plans/<feature-name>.md to execute the plan`

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
