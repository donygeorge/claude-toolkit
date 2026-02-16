# Plan Skill

Creates detailed implementation plans for major features with milestones, exit criteria, testing requirements, and architecture decisions. Does NOT implement - only plans.

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

## Execution Flow

### 1. Initial Planning Phase

1. **Parse Input**
   - Extract feature name/description
   - Identify any constraints mentioned

2. **Research Phase** (automatic, no prompts)
   - Use WebSearch to research best practices
   - Use WebFetch to get documentation for relevant libraries
   - Read existing codebase to understand patterns

3. **Create Initial Plan**
   - Launch plan agent via Task tool
   - Agent writes plan to `docs/plans/<feature-name>.md`

### 2. Feedback Loop (Codex)

After the initial plan is created, iterate with codex for feedback:

**Loop Rules**:
- Maximum 10 iterations
- Stop early if codex says "no major issues" or "plan looks solid"
- Incorporate feedback and regenerate plan each iteration
- Track iteration count and feedback summary

### 3. Agent Reviews

After codex feedback loop completes, optionally run:

- Architecture review (architect agent)
- Security review (security agent)
- Product review (pm agent)

### 4. Finalize Plan

1. Incorporate agent feedback
2. Update plan status to "In Review"
3. Present final plan to user with summary

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

1. Log: "Codex unavailable - skipping automated feedback"
2. Run architect, security, and pm agents for review instead
3. Present plan with note: "Manual review recommended"

## Output Location

Plans are saved to: `docs/plans/<feature-name>.md`

Naming convention:
- Use kebab-case: `user-notifications.md`, `dark-mode.md`

## Plan Template

```markdown
# [Feature Name] - Implementation Plan

> **Status**: Draft | In Review | Approved | In Progress | Complete
>
> **Last Updated**: [Date]
>
> **Codex Iterations**: [N of 10]

## Summary
## North Star
## Principles

## Research Findings
### Best Practices
### Libraries Considered

## Architecture
### System Overview
### Data Flow
### Database Schema
### API Design

## Implementation Milestones
### M1: [Name]
### M2: [Name]
...

## Testing Strategy
### Unit Tests
### UI Testing
### Manual Verification

## Risks & Mitigations
## Open Questions

---
## Feedback Log
[Summary of codex/agent feedback incorporated]
```

## Constraints

- **No implementation**: This skill only produces plans
- **No time estimates**: Focus on what, not when
- **Automatic research**: Web search runs without prompting
- **Clear exit criteria**: Every milestone must be testable
- **Maintainability first**: Prefer simple over clever
