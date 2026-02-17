# Superpowers-Inspired Enhancements — Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-17
>
> **Codex Iterations**: 0 of 10

## Summary

Incorporate key findings from the [obra/superpowers](https://github.com/obra/superpowers) analysis into claude-toolkit: a new `/verify` skill, adversarial review in `/implement`, systematic debugging in `/fix` and `/solve`, TDD enforcement, skill description audit, and token cost visibility.

## North Star

Every skill that produces code changes should have built-in verification discipline — agents can't claim success without evidence, can't fix bugs without root-cause analysis, and can't implement without tests. The `/verify` skill serves as a standalone final gate the user can invoke after any workflow.

## Principles

1. **Complement, don't replace** — Add prompt-level discipline on top of existing code-level hooks
2. **Minimal footprint** — Modify existing skills inline rather than creating new abstractions
3. **No over-engineering** — Each change should be a focused addition, not a rewrite
4. **Generic content only** — All additions must stay project-agnostic per toolkit rules

---

## Implementation Milestones

### M0: Add `/verify` Skill (New Skill)

Create `skills/verify/SKILL.md` — a standalone deep verification skill that can be invoked after `/implement`, `/solve`, `/fix`, or any manual work.

**What it does**:

- Runs verification checks directly (no report files — summarizes findings inline)
- Checks: all changes committed, tests pass, lint passes, exit criteria met (if plan exists)
- Verifies edge cases were handled (reads the diff, checks for null handling, error paths, boundary conditions)
- Applies the "verification gate" pattern: IDENTIFY command → RUN it → READ output → VERIFY claim
- **Fixes issues it finds** — doesn't just report, actively resolves what it can
- **Asks user when unsure** — for ambiguous issues or judgment calls, presents options and waits
- Forbidden language in its own output: "should", "probably", "seems to", "Great!", "Perfect!"

**Two modes**:

- **Default (deep)**: Full verification — edge case scan, clean-room agent, thorough checks. For standalone use after `/implement`, `/solve`, `/fix`.
- **Quick (`--quick`)**: Focused spec-compliance check — tests pass, lint passes, exit criteria met, changes committed. Designed to be invoked programmatically from within `/implement` per-milestone.

**Scope inference**:
- After `/implement`: reads plan state to verify all milestones and evaluation criteria
- After `/solve` or `/fix`: verifies the fix commit, checks for uncommitted changes, re-runs tests
- Standalone: verifies uncommitted changes or a specific commit range
- Within `/implement` (quick mode): verifies a single milestone's exit criteria

**Skill frontmatter**:
```yaml
name: verify
description: Use after completing implementation, bug fixes, or any code changes to verify correctness.
argument-hint: "[plan-file | commit-range | uncommitted] [--quick]"
user-invocable: true
disable-model-invocation: false
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Task, TodoWrite]
```

Note: `disable-model-invocation: false` so that `/implement` can invoke it programmatically.

**Key sections**:
- Verification Gate Function (the 5-step gate from superpowers)
- Rationalization Prevention Table (8-10 entries mapping common agent excuses to rebuttals)
- Checklist: commits clean, tests pass, lint passes, edge cases, exit criteria
- Clean-room verification: fresh agent reads all changed files independently
- Edge case scan: reads diff, looks for missing null checks, error handling, boundary conditions
- Fix-or-ask workflow: fix issues directly when confident, ask user when ambiguous
- Summary output: inline text summary (no artifact files)

**Files to create**:

- `skills/verify/SKILL.md`

**Exit Criteria**:

- [x] `skills/verify/SKILL.md` exists with complete skill definition
- [x] Skill has YAML frontmatter with name, description, argument-hint, allowed-tools (includes Write/Edit)
- [x] Includes verification gate function (5-step: IDENTIFY→RUN→READ→VERIFY→CLAIM)
- [x] Includes rationalization prevention table (8+ entries)
- [x] Includes clean-room verification agent spawn pattern
- [x] Includes edge case scanning checklist
- [x] Fixes issues directly when confident, asks user when unsure
- [x] Summarizes findings inline (no report files)
- [x] Handles three scopes: plan-based, commit-based, uncommitted
- [x] Generic content only — no project-specific references

---

### M1: Integrate `/verify --quick` into `/implement`

Instead of duplicating verification logic, reuse the `/verify` skill in quick mode within `/implement`. This keeps verification logic in one place.

**Changes to `skills/implement/SKILL.md`**:

- Replace Step 2b (Completion Verification) with an invocation of `/verify --quick` against the plan file
- Enhance the adversarial framing: "The implementer finished suspiciously quickly. Verify everything independently."
- Add forbidden language list to Step 2b: "should work", "probably fine", "seems correct"

**Changes to `skills/implement/milestone-template.md`**:

Between Phase 8 (Reviewer Agent) and Phase 9 (Documentation), add a new **Phase 8b: Spec Compliance Verification** that invokes the verify skill in quick mode:

- Invoke verify skill (quick mode) with the milestone's exit criteria as scope
- Verify checks: does implementation actually satisfy each exit criterion?
- Must run tests and check outputs, not just read code
- If issues found → verify fixes them → re-verify (max 2 rounds)

This reuses the verify skill's gate function, rationalization table, and fix-or-ask workflow. No duplicated logic.

**Files to modify**:

- `skills/implement/SKILL.md` (update Step 2b to use `/verify --quick`)
- `skills/implement/milestone-template.md` (add Phase 8b invoking verify in quick mode)

**Exit Criteria**:

- [x] Step 2b in SKILL.md references `/verify --quick` for plan-level verification
- [x] Phase 8b added to milestone-template.md between Phase 8 and Phase 9
- [x] Phase 8b invokes the verify skill in quick mode (not a separate custom agent)
- [x] Adversarial framing and forbidden language list present
- [x] No project-specific content added

---

### M2: Add Systematic Debugging to `/fix` and `/solve`

Enhance the root-cause analysis in both skills with superpowers' structured debugging approach: phase gates, pattern analysis, and the 3-fix escalation rule.

**Changes to `skills/fix/SKILL.md`**:

Replace the existing Step 1 (Root Cause Analysis) with a more structured 4-phase process:

1. **Phase 1: Root Cause Investigation** (existing content, enhanced)
   - Read the error, reproduce it, check recent changes, gather evidence, trace data flow
   - **Phase gate**: Cannot propose ANY fix until root cause is identified
   - Add: "Check git log for recent changes to affected files"

2. **Phase 2: Pattern Analysis** (new)
   - Find working examples of similar code in the codebase
   - Compare working vs broken — identify the difference
   - Look for similar patterns elsewhere that may have the same bug

3. **Phase 3: Hypothesis Testing** (new)
   - Single hypothesis at a time, minimal change to test it
   - **3-fix escalation rule**: After 3 failed fix attempts, STOP. Do not attempt fix #4. Instead:
     - Question the architecture: "Is the approach fundamentally wrong?"
     - Present findings to user with evidence from all 3 attempts
     - Ask user how to proceed before continuing

4. **Phase 4: Implement the Fix** (existing Step 2, unchanged)

Also add a **Rationalization Prevention** section with a focused table:

| Rationalization | Response |
|---|---|
| "Quick fix for now, investigate later" | Investigate NOW. Quick fixes become permanent. |
| "Just try changing X and see if it works" | That's guessing, not debugging. Identify root cause first. |
| "I don't fully understand but this might work" | If you don't understand, you can't verify the fix. |
| "One more fix attempt" (when already tried 2+) | After 3 failed fixes, question the architecture. |
| "The fix works in my test, ship it" | Run the FULL test suite. Edge cases exist. |

**Changes to `skills/solve/SKILL.md`**:

Add the same structured debugging approach to Step 5 (Create Plan) and Step 6 (Implement):
- Reference the 4-phase debugging process for bug-type issues
- Add the 3-fix escalation rule to Step 7 (Test) — "If tests fail after 3 iterations, stop and question approach"
- Add a note at Step 6: "For bugs: follow the systematic debugging phases (investigate → analyze patterns → hypothesis test → implement). Do NOT jump to a fix."

**Files to modify**:

- `skills/fix/SKILL.md`
- `skills/solve/SKILL.md`

**Exit Criteria**:

- [x] `/fix` has 4-phase structured debugging process
- [x] Phase gates: cannot propose fix until root cause identified
- [x] 3-fix escalation rule in both `/fix` and `/solve`
- [x] Rationalization prevention table in `/fix` (5+ entries)
- [x] `/solve` references systematic debugging for bug-type issues
- [x] Both skills maintain existing functionality (no removals)
- [x] Generic content only

---

### M3: Add TDD Guidance to `/implement` and `/fix`

Add test-first guidance to implementation and bug-fix workflows. This is lightweight advice, NOT rigid enforcement — tests should only be written when they add value.

**Changes to `skills/implement/milestone-template.md`**:

In Phase 4 (Implementation - Layer by Layer), add a TDD sub-section before the implementation loop:

```
### Test-First Guidance (within each layer)

When implementing non-trivial logic, prefer writing tests first:
1. Write a failing test that describes the expected behavior
2. Run the test — confirm it FAILS (red)
3. Write the minimum code to make it pass (green)
4. Run all tests — confirm they pass
5. Refactor if needed, keeping tests green

Do NOT write tests for:
- Configuration file changes
- Database migrations (test the result, not the migration itself)
- UI layout-only changes (visual verification instead)
- Wiring/glue code that just connects tested components
- Simple one-line changes or obvious fixes
- Boilerplate, scaffolding, or setup code
- Changes to files that have no existing test coverage (unless adding coverage is part of the plan)

The goal is preventing regressions in complex logic, not achieving 100% coverage.
```

**Changes to `skills/fix/SKILL.md`**:

In the enhanced Phase 4 (Implement the Fix), add:

```
For non-trivial bugs (logic errors, edge cases, race conditions):
1. Write a test that REPRODUCES the bug (test should FAIL)
2. Confirm the test fails for the right reason
3. Implement the fix
4. Run the test — confirm it now PASSES
5. Run the full test suite

Skip the reproducing test for:
- Typo fixes, import corrections, config changes
- Bugs that are obvious and unlikely to recur
- Cases where the test would just duplicate the implementation
```

**Files to modify**:

- `skills/implement/milestone-template.md` (add test-first sub-section to Phase 4)
- `skills/fix/SKILL.md` (add test-first pattern to Phase 4)

**Exit Criteria**:

- [x] Milestone template Phase 4 includes test-first guidance sub-section
- [x] Guidance has a clear "Do NOT write tests for" list to prevent over-engineering
- [x] `/fix` Phase 4 has test-first guidance for non-trivial bugs with skip list
- [x] Neither addition uses aggressive enforcement language
- [x] Generic content only

---

### M4: Audit and Fix Skill Descriptions

Address the superpowers finding that skill descriptions that summarize workflows cause Claude to follow the description as a shortcut instead of reading the full SKILL.md. Descriptions should state TRIGGERING CONDITIONS only.

**Current descriptions to audit**:

| Skill | Current Description | Issue |
|---|---|---|
| implement | "Executes implementation plans autonomously with multi-milestone support, testing, and reviews." | Summarizes workflow (multi-milestone, testing, reviews) |
| fix | "Root-cause, fix, validate, scan for similar patterns, test, and commit a bug." | Summarizes entire workflow |
| solve | "GitHub issue workflow - fetch, reproduce, fix, test, and commit." | Summarizes entire workflow |
| review-suite | "Run code review agents (reviewer, qa, security, ux, pm, docs, architect)." | Lists agents (workflow summary) |
| refine | "Iterative evaluate-fix-validate convergence loop for code quality improvement." | Summarizes mechanism |
| brainstorm | "Deep research and idea exploration with dynamic agent teams..." | Summarizes mechanism |
| plan | "Creates detailed implementation plans with milestones, exit criteria, and architecture decisions. Saves to docs/plans/ for use with /implement." | Summarizes output format |

**Proposed fixes** — descriptions should only state WHEN to use, not HOW it works:

| Skill | New Description |
|---|---|
| implement | "Use when you have an approved plan file and are ready to build." |
| fix | "Use when a bug needs fixing but there is no GitHub issue to track it." |
| solve | "Use when working on one or more GitHub issues." |
| review-suite | "Use when code changes need review before merging or completing." |
| refine | "Use when existing code needs iterative quality improvement." |
| brainstorm | "Use when exploring a new idea, technology choice, or design problem before planning." |
| plan | "Use when a feature or change needs a detailed implementation plan before building." |
| verify | (new — already in trigger-condition format, see M0) |
| commit | "Commit uncommitted session changes with an auto-generated message." | (OK as-is — describes triggering condition) |
| gemini | "Second opinion from Google's Gemini model for alternative solutions or research." | (OK as-is) |
| conventions | "Displays coding conventions for the project." | (OK as-is) |
| setup-toolkit | "Detect project stacks and commands, validate config, generate toolkit.toml and CLAUDE.md..." | Too long, summarizes workflow |
| setup-toolkit (new) | "Use when setting up, updating, or contributing back to the toolkit." |

**Files to modify**:

- `skills/implement/SKILL.md` (description field)
- `skills/fix/SKILL.md` (description field)
- `skills/solve/SKILL.md` (description field)
- `skills/review-suite/SKILL.md` (description field)
- `skills/refine/SKILL.md` (description field)
- `skills/brainstorm/SKILL.md` (description field)
- `skills/plan/SKILL.md` (description field)
- `skills/setup-toolkit/SKILL.md` (description field)

**Exit Criteria**:

- [x] All 8 skill descriptions updated to state triggering conditions only
- [x] No description summarizes the workflow or lists steps
- [x] Descriptions are concise (under 80 characters preferred)
- [x] YAML frontmatter remains valid after edits

---

### M5: Add Token Cost Visibility Script

Add a lightweight Python script that analyzes Claude Code session transcripts to show per-subagent token usage and cost estimates. Useful for understanding the cost of `/implement` and `/review` multi-agent workflows.

**What it does**:
- Reads Claude Code session JSONL transcript files
- Parses per-message token counts (input, output, cache_creation, cache_read)
- Groups by subagent (via `toolUseResult.agentId` or similar)
- Calculates cost estimates at current API pricing
- Outputs a summary table

**Files to create**:

- `tools/analyze-tokens.py`

**Exit Criteria**:

- [ ] Script reads JSONL session transcript files
- [ ] Groups token usage by subagent/agent
- [ ] Shows per-agent breakdown (input tokens, output tokens, cache tokens)
- [ ] Shows cost estimates (with configurable pricing)
- [ ] Has `--help` with usage instructions
- [ ] Works with Python 3.11+ stdlib only (no external dependencies)
- [ ] Handles missing/malformed lines gracefully
- [ ] Tested manually with a real session transcript

---

## Architecture

### New Files

| File | Purpose |
|---|---|
| `skills/verify/SKILL.md` | Standalone verification skill |
| `tools/analyze-tokens.py` | Token cost analysis script |

### Modified Files

| File | Changes |
|---|---|
| `skills/implement/SKILL.md` | Step 2b updated to invoke `/verify --quick` |
| `skills/implement/milestone-template.md` | New Phase 8b (invoke verify quick mode) + test-first guidance in Phase 4 |
| `skills/fix/SKILL.md` | 4-phase debugging + TDD + rationalization table |
| `skills/solve/SKILL.md` | Systematic debugging reference + 3-fix escalation |
| 8 skill SKILL.md files | Description field updates (M4) |

### Unchanged

- No hook changes needed — existing `task-completed-gate.sh` and `verify-completion.sh` complement these additions
- No agent prompt changes — the reviewer agent already works with the new Phase 8b
- No config changes — no new toolkit.toml keys required

---

## Testing Strategy

### Manual Verification

- Read each modified skill and verify content is generic
- Verify YAML frontmatter is valid in all modified SKILL.md files
- Run `python3 tools/analyze-tokens.py --help` to verify the script works

### Automated

- Shellcheck: N/A (no shell script changes)
- Python tests: Add basic tests for `tools/analyze-tokens.py` if it has non-trivial logic
- Existing tests should continue passing (no behavioral changes to hooks or CLI)

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Skill descriptions too terse after M4 | Test with Claude Code to verify skills still trigger correctly on natural language |
| TDD enforcement too aggressive | Listed practical exceptions; kept as guidance not hard gates |
| Phase 8b slows down implement too much | It's one additional subagent per milestone — acceptable given quality improvement |
| Token script pricing gets stale | Make pricing configurable via command-line flags |

---

## Open Questions

- None — all items from the user's request are addressed.

## Answering User Question #6: Brainstorm vs Design Gate

Your `/brainstorm` skill already covers the "design before code" concept more comprehensively than superpowers' brainstorming skill. Key comparison:

| Aspect | Superpowers | Your Toolkit |
|---|---|---|
| Design phase | `brainstorming` skill with HARD-GATE XML tag | `/brainstorm` with full persona-based team |
| Gate enforcement | Prompt-level HARD-GATE preventing any code | No hard gate — relies on skill separation (brainstorm→plan→implement) |
| Depth | Single-agent design discussion | Multi-agent research with personas, evaluation matrices |

**Gap identified**: Your toolkit has no *enforcement* that brainstorming or planning must happen before implementing. A user can skip directly to `/implement` with a hand-written plan. However, this is arguably a feature, not a bug — your toolkit is tools-based (use what you need) rather than methodology-based (you must follow this process). The `/verify` skill (M0) adds a post-hoc check that partially addresses this: if exit criteria are vague or missing, verify will catch it.

**Recommendation**: No changes needed to brainstorm. The skill is already stronger than superpowers' equivalent.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. `/verify` skill can be invoked standalone, fixes issues, and summarizes findings inline
2. `/implement` milestone template includes spec compliance verification (Phase 8b)
3. `/fix` has 4-phase systematic debugging with 3-fix escalation rule
4. `/solve` references systematic debugging and has 3-fix escalation
5. Test-first guidance present in implement milestone template and fix skill (with clear skip lists)
6. All 8 skill descriptions updated to trigger-condition format

### Code Quality

1. All SKILL.md files have valid YAML frontmatter
2. All content is generic — no project-specific references
3. `tools/analyze-tokens.py` runs with stdlib only (Python 3.11+)

### Consistency

1. Existing test suite passes unchanged
2. No changes to hooks, agents, or toolkit CLI
3. Skill descriptions are consistent in format and tone

---

## Feedback Log

_Pending codex/agent feedback._
