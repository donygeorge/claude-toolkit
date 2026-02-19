# Skill Design Guide

Principles for writing Claude Code skills that resist rationalization, survive model upgrades, and produce reliable agent behavior. Derived from auditing and improving 15 skills across 10 milestones.

---

## 1. The Description Trap

**What it is**: When a skill's `description` field summarizes workflow instead of specifying trigger conditions. Claude may follow the short description instead of reading the full skill body, leading to shallow execution.

**How Claude uses descriptions**: The skill loader presents descriptions to the model when deciding whether to invoke a skill. If the description says "Commit changes with an auto-generated message," the model may attempt exactly that -- commit with a generated message -- without reading the full workflow (session file filtering, staging rules, `-F` flag, etc.).

**How to avoid**: Use "Use when..." trigger format. The description should tell the model *when* to invoke the skill, not *what* the skill does.

### Before / After

| Skill | Before (workflow summary) | After (trigger condition) |
| ----- | ------------------------- | ------------------------- |
| commit | "Commit uncommitted session changes with an auto-generated message." | "Use when the current session has changes ready to commit." |
| conventions | "Displays coding conventions for the project." | "Use when you need to check or reference the project's coding conventions." |

**Correct patterns**:

- `"Use when code changes need review before merging or completing."`
- `"Use after completing implementation, bug fixes, or any code changes to verify correctness."`
- `"Use when you have an approved plan file and are ready to build."`

**Incorrect patterns**:

- `"Run tests and lint on the project."` (describes workflow)
- `"Create a commit with staged files."` (describes workflow)
- `"Analyze code for security issues."` (describes workflow)

---

## 2. The Commitment Principle

**What it is**: Start with easy instructions the agent will comply with, then escalate to harder constraints. An agent that has already complied with simple rules is more likely to follow complex ones.

**Application**: Place the Critical Rules section immediately after the frontmatter and overview, before any workflow. The rules are short, table-formatted, and easy to read -- establishing a compliance pattern before the agent encounters complex multi-step workflows.

**Skill structure that leverages this principle**:

```
1. Frontmatter (metadata)
2. One-line overview
3. Critical Rules (READ FIRST)     <-- easy to comply with
4. Rationalization Prevention       <-- harder constraints
5. Workflow                         <-- complex multi-step instructions
```

**Example from the verify skill**: The agent first reads 5 concise rules in a table, then encounters a Forbidden Language list (hedging phrases to avoid), then proceeds to the multi-step verification workflow. By the time it reaches the workflow, it has already internalized the constraint pattern.

---

## 3. Rationalization Prevention

**When to add**: Skills where the agent makes judgment calls and might shortcut (review, verify, implement, fix, solve, plan, loop).

**When to skip**: Mechanical/utility skills with no judgment calls (commit, conventions, scope-resolver).

**Table format**: Three columns -- Rationalization, Why It Is Wrong, Correct Behavior.

**Length**: 3-5 entries per skill. Longer tables get skimmed; shorter tables miss common rationalizations.

**Domain-specific**: Every entry must reference an artifact, tool, or concept unique to the skill's domain. Generic entries like "This is probably fine" are too vague.

### Example from the review-suite skill

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "The code looks clean, no findings expected" | Pre-judging the outcome before running agents defeats the purpose of automated review | Launch all configured agents on the resolved scope; report whatever they find |
| "This is a style issue, not a bug" | Dismissing findings as style issues allows real quality problems to pass; severity classification is the agent's job | Record the finding with the severity the agent assigned; only downgrade per evidence rules |
| "The agent timed out, so it probably found nothing" | Timed-out agents are inconclusive, not passing | Mark the agent as timed out; report partial findings and flag the timeout |

### Example from the implement skill

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "This milestone is trivial, I will implement it inline" | Inline implementation violates the two-tier architecture; the Plan Executor cannot write files | Spawn a Milestone Orchestrator via Task() for every milestone |
| "The tests pass, so the milestone is complete" | Passing tests do not confirm exit criteria are met; exit criteria may require new files or docs | Verify every exit criterion independently after tests pass |

---

## 4. Critical Rules Placement

**Section name**: `## Critical Rules (READ FIRST)` for complex skills; `## Critical Rules` for utility skills.

**Placement**: Immediately after frontmatter and overview, before any workflow section. This follows the "Lost in the Middle" research finding that LLMs give disproportionate weight to information at the beginning and end of prompts.

**Format**: Table with Rule and Description columns. Each rule gets a bold number prefix.

**Count**: 3-7 rules. Fewer than 3 suggests the skill is too simple for rules. More than 7 and the agent starts ignoring later entries.

### Before / After (from the commit skill)

**Before** (rules buried in workflow):

```markdown
## Workflow
### Step 1: Identify Changes
...
Important: Never use `git add .` — always stage specific files.
...
### Step 5: Commit
...
Note: Always use `git commit -F` for the message.
```

**After** (rules front-loaded, as implemented in the commit skill):

```markdown
## Critical Rules

| Rule | Description |
| ---- | ----------- |
| **1. Session files only** | Never commit files you did not touch in this session. |
| **2. Never `git add .`** | Always stage specific files by name. |
| **3. Use `-F` for messages** | Write the commit message to a temp file and use `git commit -F`. |
| **4. No push, no amend** | Only create new local commits. |

## Workflow
...
```

Rules embedded in workflow paragraphs get lost. Rules in a front-loaded table get read.

---

## 5. Length Budgeting

Longer skills suffer from context dilution -- the agent is more likely to skip or skim sections. Set soft targets by skill type:

| Skill Type | Examples | Target | Rationale |
| ---------- | -------- | ------ | --------- |
| Utility/reference | conventions, scope-resolver | < 150 lines | Single purpose, minimal workflow |
| Workflow (single-path) | fix, solve | < 350 lines | Linear steps, one execution path |
| Orchestration (multi-agent) | implement, verify, plan, review-suite, loop, toolkit-* | < 600 lines | Agent coordination, state management |
| Multi-mode (distinct flows) | brainstorm | < 1000 lines | Multiple execution paths (e.g., shallow/normal/deep) |

**When a skill exceeds its budget**: Split it. A 2,000+ line skill with 4 distinct execution paths should become 4 focused skills (~500 lines each). Each new skill gets its own frontmatter, Critical Rules, and workflow.

**Exception**: Multi-mode skills with genuinely shared context (e.g., brainstorm has shallow/normal/deep modes that share persona definitions and evaluation criteria). If the shared content exceeds 30% of the skill, splitting creates duplication that is worse than the length.

**This guide itself**: At under 300 lines, it follows the utility/reference budget.

---

## 6. Upgrade Resilience

Skills should survive model upgrades and calendar year changes without manual edits.

**No hardcoded years**: The brainstorm skill originally had 6 occurrences of hardcoded years for web search queries. Replace `"Include 2025 or 2026 in WebSearch queries"` with `"Include the current year in WebSearch queries."` The model knows the current date.

**No hardcoded model names in body text**: Instead of `"Use Sonnet for this step,"` use tier descriptions: `"Use the balanced-tier model for this step."` Model names change across releases; tier concepts are stable.

**`model:` frontmatter is acceptable**: The `model:` key in YAML frontmatter is metadata consumed by the skill loader, not by the skill body. It is a cost/quality hint, and the correct place to specify a model preference.

**Model selection tables**: When a skill includes a model selection table (e.g., for agent orchestration), include the tier rationale alongside the model name:

```markdown
| Agent | Model | Tier | Rationale |
| ----- | ----- | ---- | --------- |
| reviewer | opus | Most capable | Needs deep code understanding |
| docs | sonnet | Balanced | Straightforward checks |
```

This way, when model names change, the tier column explains the intent and makes migration obvious.

**Web research skills**: Any skill that instructs agents to perform web searches should include: "Include the current year in search queries to get up-to-date results."

---

## 7. Frontmatter Standards

Every `SKILL.md` requires YAML frontmatter between `---` delimiters.

### Required Fields

| Field | Type | Purpose |
| ----- | ---- | ------- |
| `name` | string | Skill identifier (matches directory name) |
| `description` | string | Trigger condition (must use "Use when..." format) |
| `user-invocable` | boolean | Whether users can invoke directly via slash command |

### Optional Fields

| Field | Type | Purpose |
| ----- | ---- | ------- |
| `model` | string | Model preference hint (e.g., `haiku` for cheap ops, `opus` for complex reasoning) |
| `argument-hint` | string | Shown in help output (e.g., `"<plan-file> [--quick]"`) |
| `allowed-tools` | list | Tool restrictions; only set when there is an architectural reason |

**`description` format**: Must use trigger-condition format. See Section 1 (Description Trap).

**`allowed-tools` guidance**: Only restrict tools when the restriction serves a design purpose. For example, the implement skill's Plan Executor omits Write and Edit to enforce the two-tier architecture (all code changes must go through spawned milestone agents). Do not restrict tools "just to be safe" -- tool restrictions limit the agent's ability to recover from unexpected situations.

### Example frontmatter

```yaml
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
```

---

## 8. Testing Skills

Two complementary approaches with different cost profiles.

### Structural Linting (automated, cheap)

Add lint checks to your test suite that validate every `SKILL.md`:

| Check | Severity | Rule |
| ----- | -------- | ---- |
| Valid frontmatter | ERROR | Must have `name`, `description`, `user-invocable` |
| Description Trap | ERROR | Description must not start with an action verb describing workflow |
| Critical Rules present | WARN | User-invocable skills should have a "Critical Rules" section |
| Line count budget | WARN | Soft targets per skill type (see Section 5) |
| No hardcoded years | WARN | Grep for 4-digit years in body text |

Run these on every commit. They catch structural regressions instantly and cost nothing.

### Pressure Testing (manual, expensive)

Build adversarial scenarios that attempt to trigger rationalization:

1. Define a prompt designed to make the agent shortcut (e.g., "This milestone is trivial, just inline it")
2. Run the scenario against the skill via a model session
3. Check the output for forbidden rationalization patterns
4. Verify the skill's Critical Rules were followed

**When to re-run pressure tests**:

- After a model upgrade (new model may respond differently to the same rationalization triggers)
- After significant skill rewrites (changed structure may weaken resistance)
- Before major releases (regression check on high-judgment skills)

Pressure tests are expensive (each invokes a full model session). Run them on-demand, not in CI. Target the 5 highest-judgment skills first: implement, verify, fix, plan, review-suite.

---

## Summary Checklist

Use this checklist when writing or reviewing a skill:

- [ ] Description uses "Use when..." trigger format (not workflow summary)
- [ ] Critical Rules section is immediately after frontmatter/overview
- [ ] Critical Rules has 3-7 entries in table format
- [ ] Rationalization prevention table exists (for judgment-heavy skills)
- [ ] Rationalization entries are domain-specific (not generic)
- [ ] Line count is within budget for the skill type
- [ ] No hardcoded years or model names in body text
- [ ] Frontmatter has `name`, `description`, `user-invocable`
- [ ] `allowed-tools` only restricts tools for architectural reasons
- [ ] Structural lint passes
