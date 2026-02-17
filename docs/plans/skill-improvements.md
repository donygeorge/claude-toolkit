# Skill Improvements — Implementation Plan

> **Status**: Approved
>
> **Last Updated**: 2026-02-17
>
> **Codex Iterations**: 0 of 10

## Summary

Fix 3 P0 bugs in skills, document the undiscovered `/verify` skill, improve documentation clarity in 6 skills (brainstorm, implement, refine, plan, fix, commit), add version-update checks to the implement skill, create skill test infrastructure, add a workflow map to the README, add auto-flow flags for pipeline continuity, and document skill defaults in `toolkit.toml`.

## North Star

Every skill is internally consistent, well-documented, testable, and forms a frictionless pipeline from ideation through verification. Users can discover all skills, understand defaults, and chain them with minimal manual handoffs.

## Principles

1. **Fix bugs before adding features** — P0 contradictions/mismatches fixed first
2. **Document what exists** — The `/verify` skill already solves post-implement validation; surface it
3. **Clarify, don't rewrite** — Targeted fixes to ambiguous sections, not full rewrites
4. **Test what matters** — Structural validation (frontmatter, sections, cross-refs) catches regressions
5. **Pipeline continuity** — Auto-flow flags reduce friction but always use clean Task context

## Research Findings

### Existing State

- `/verify` skill exists at `skills/verify/SKILL.md` (501 lines, deep + quick modes) but is absent from README (says "11 skills"), CLAUDE.md (lists 12), and `docs/reference.md` (12 in table)
- `output-schema.json` requires dash-format run_id (`^[0-9]{8}-[0-9]{6}$`) but SKILL.md examples use underscores
- implement skill says Write/Edit are "removed from" allowed-tools — misleading since they were never listed
- solve skill says "MUST use visual tools" then provides fallback for when reproduction fails
- brainstorm describes persona prompts conceptually but provides no concrete template
- refine `convergence_threshold: 2` is ambiguous (2 findings? 2 iterations?)
- plan has two codex stop conditions ("SOLID:" and fuzzy "no major issues") but table says only "SOLID:"
- commit session-file detection has no specified mechanism
- fix similar-pattern scan has no scope limits
- implement state schema lacks intra-milestone phase tracking for resume
- No tests validate skill file structure, frontmatter, or cross-references
- `toolkit.toml.example` has no `[skills.*]` sections for discovering tunable defaults
- Test patterns from `test_hooks.sh`: `_test`/`_pass`/`_fail` framework, JSON builders, counter-based summary
- Test patterns from `test_toolkit_cli.sh`: `assert_eq`/`assert_contains`/`assert_file_exists`, temp project setup

### Key Files

- `skills/review-suite/SKILL.md` — timestamp fix (lines 112, 274)
- `skills/review-suite/output-schema.json` — authoritative schema (line 11)
- `skills/implement/SKILL.md` — allowed-tools wording (lines 36-39), state schema (lines 147-168), resume logic (lines 297-304), new version check step after line 262
- `skills/implement/milestone-template.md` — Phase 9 version note (lines 214-220)
- `skills/solve/SKILL.md` — visual tools contradiction (lines 116, 127-129)
- `skills/brainstorm/SKILL.md` — persona template (after 213), gemini timing (after 524), shutdown (322-325), ad-hoc threshold (after 581), auto-plan flag (flags table + Phase 8)
- `skills/refine/SKILL.md` — convergence (line 35, 171), scope evolution (199-203), clean-room (227-237)
- `skills/plan/SKILL.md` — idea doc matching (65-69), agent launch (94-97), codex stop (106 vs 140), auto-implement flag
- `skills/fix/SKILL.md` — scan scope (64-70), test decision tree (72-80)
- `skills/commit/SKILL.md` — session detection (29-36)
- `skills/verify/SKILL.md` — already complete, needs docs references
- `README.md` — skill count (line 13), workflow map insertion (after line 86)
- `CLAUDE.md` — skill count (line 13), skill list, project structure
- `docs/reference.md` — skills table (lines 289-302), new defaults subsection
- `templates/toolkit.toml.example` — new `[skills.*]` sections (after line 171)
- `CHANGELOG.md` — new version entry
- `tests/test_skills.sh` — new file

## Architecture

### System Overview

All changes are documentation/configuration fixes in SKILL.md files plus one new test file and one enhanced hook. No architectural changes to the toolkit's runtime behavior.

### Data Flow

```text
toolkit.toml.example  →  (reference for skill defaults)
skills/*/SKILL.md     →  (read by Claude Code at skill invocation time)
tests/test_skills.sh  →  (validates skill file structure)
README.md / CLAUDE.md / docs/reference.md  →  (user-facing documentation)
```

### Key Files

See Research Findings > Key Files above for the complete list with line numbers.

## Implementation Milestones

### M0: Fix P0 Bugs

Fix the 3 blocking inconsistencies/contradictions across review-suite, implement, and solve skills.

**Files to create/modify**:

- `skills/review-suite/SKILL.md` (fix timestamp format at lines 112, 274)
- `skills/implement/SKILL.md` (fix allowed-tools wording at lines 36, 39)
- `skills/solve/SKILL.md` (fix MUST → SHOULD, add fallback paths at lines 114-129)

**Exit Criteria**:

- [x] All run_id examples in review-suite/SKILL.md use dash format matching `^[0-9]{8}-[0-9]{6}$`
- [x] No occurrences of underscore-format timestamps (`[0-9]{8}_[0-9]{6}`) in review-suite/SKILL.md
- [x] implement/SKILL.md says "intentionally not listed" not "removed"
- [x] implement/SKILL.md documents that Task-spawned agents inherit full tool access
- [x] solve/SKILL.md uses "SHOULD attempt" not "MUST use" for visual reproduction
- [x] solve/SKILL.md provides fallback strategies when visual tools are unavailable

### M1: Document /verify Skill and Update Counts

The `/verify` skill exists but is missing from all project documentation. Add it everywhere skills are listed and update counts.

**Files to create/modify**:

- `README.md` (update skill count from 11 to 13, add verify to any skill lists)
- `CLAUDE.md` (update skill count from 12 to 13, add verify to skill list and project structure)
- `docs/reference.md` (add verify row to skills table at line 302)

**Exit Criteria**:

- [x] README.md references 13 skill templates
- [x] CLAUDE.md lists verify in the skills list and project structure
- [x] docs/reference.md skills table includes verify with description and directory
- [x] Grep for "12 skill" or "11 skill" in README.md, CLAUDE.md, docs/reference.md returns zero matches

### M2: Improve Skill Documentation (brainstorm, implement, refine, plan, fix, commit)

Address all identified documentation gaps, ambiguities, and underspecified sections across 6 skills.

**Files to create/modify**:

- `skills/brainstorm/SKILL.md` (persona prompt template, gemini timing, team shutdown, ad-hoc threshold)
- `skills/implement/SKILL.md` (add `current_phase`/`phases_completed` to state schema, update resume logic)
- `skills/refine/SKILL.md` (convergence threshold comment, scope evolution mechanism, clean-room termination)
- `skills/plan/SKILL.md` (fuzzy idea-doc matching, agent launch mechanism, unify codex stop to "SOLID:" only)
- `skills/fix/SKILL.md` (scan scope limits, test addition decision tree)
- `skills/commit/SKILL.md` (session file detection strategy)

**Exit Criteria**:

- [x] brainstorm/SKILL.md contains a concrete persona prompt template with placeholders
- [x] brainstorm/SKILL.md specifies gemini-consultant invocation timing (after persona reports, during synthesis)
- [x] brainstorm/SKILL.md team shutdown section includes timeout (30s), parallel shutdown, failure handling
- [x] brainstorm/SKILL.md has "When NOT to Ask Ad-Hoc Questions" section with concrete threshold
- [x] implement/SKILL.md state schema includes `current_phase` and `phases_completed` fields
- [x] implement/SKILL.md resume logic references `phases_completed` array
- [x] refine/SKILL.md convergence_threshold has inline comment explaining it means "max new findings per iteration"
- [x] refine/SKILL.md scope evolution specifies discovery mechanism, limits (10/iteration, 30 total), and module priority
- [x] refine/SKILL.md clean-room section specifies behavior for 0, 1-3, and 4+ issues, and termination after 2 rounds
- [x] plan/SKILL.md includes slug normalization and glob fallback for idea doc detection
- [x] plan/SKILL.md specifies `subagent_type: general-purpose` for plan agent with prompt template
- [x] plan/SKILL.md codex stop condition is "SOLID:" only (no "no major issues" fuzzy match)
- [x] fix/SKILL.md scan scope includes strategy (same module first), cap (20 matches), and reporting behavior
- [x] fix/SKILL.md test addition uses a decision tree format
- [x] commit/SKILL.md detection strategy says "rely on conversation history, cross-reference with git status"

### M3: Add Version Update Check to Implement

Add explicit version file checking after all milestones complete, and a note in milestone template that version updates are deferred.

**Files to create/modify**:

- `skills/implement/SKILL.md` (add Step 2e: Version File Check after Step 2d)
- `skills/implement/milestone-template.md` (add note to Phase 9 that VERSION/CHANGELOG deferred to Plan Executor)

**Exit Criteria**:

- [x] implement/SKILL.md has a "Step 2e: Version File Check" section between Step 2d and Step 3
- [x] Step 2e checks for VERSION file and CHANGELOG.md, asks user before updating
- [x] Step 2e references `project.version_file` from toolkit.toml
- [x] milestone-template.md Phase 9 notes that VERSION/CHANGELOG updates happen in Plan Executor Step 2e

### M4: Add Skill Workflow Map to README

Add a text-based pipeline diagram showing how skills connect and standalone skills.

**Files to create/modify**:

- `README.md` (insert workflow section after Manual Setup, before CLI Commands)

**Exit Criteria**:

- [x] README.md contains a "## Skill Workflow" section
- [x] Section shows brainstorm → plan → implement → verify pipeline
- [x] Section lists standalone skills (solve, fix, refine, review, commit, gemini)
- [x] Diagram is text-based (not Mermaid) for universal rendering

### M5: Add Auto-Flow Flags

Add `--auto-plan` to brainstorm and `--auto-implement` to plan. Both spawn fresh Task agents for clean context.

**Files to create/modify**:

- `skills/brainstorm/SKILL.md` (add flag to table, add auto-flow logic to Phase 8)
- `skills/plan/SKILL.md` (add Flags section with `--auto-implement`, add auto-flow logic after plan finalization)

**Exit Criteria**:

- [x] brainstorm/SKILL.md flags table includes `--auto-plan` with description and default "off"
- [x] brainstorm/SKILL.md Phase 8 includes auto-flow step that spawns `Task(subagent_type: general-purpose)` with plan skill prompt
- [x] brainstorm/SKILL.md auto-flow displays manual instruction when flag is not set
- [x] plan/SKILL.md has a Flags section with `--auto-implement` flag
- [x] plan/SKILL.md auto-flow spawns Task agent with implement skill prompt
- [x] Both auto-flow prompts instruct the agent to read the skill file (clean context, no session state)

### M6: Add Skill Defaults to toolkit.toml

Document all tunable skill defaults in `toolkit.toml.example`, add customization notes to skills, and update reference docs.

**Files to create/modify**:

- `templates/toolkit.toml.example` (append commented `[skills.*]` sections)
- `skills/brainstorm/SKILL.md` (add customization note after defaults)
- `skills/implement/SKILL.md` (add customization note)
- `skills/refine/SKILL.md` (add customization note)
- `skills/plan/SKILL.md` (add customization note)
- `skills/fix/SKILL.md` (add customization note)
- `skills/solve/SKILL.md` (add customization note)
- `skills/review-suite/SKILL.md` (add customization note)
- `docs/reference.md` (add "Skill Defaults" subsection after skills table)

**Exit Criteria**:

- [x] `toolkit.toml.example` has commented `[skills.*]` sections for brainstorm, implement, refine, review-suite, plan, fix, solve
- [x] Each section documents key defaults with inline comments
- [x] All 7 major skills have a one-line customization note referencing `toolkit.sh customize`
- [x] docs/reference.md has "Skill Defaults" subsection with table of key defaults per skill

### M7: Add Skill Test Infrastructure and Update CHANGELOG

Create `test_skills.sh` to validate skill file structure and cross-references. Update CHANGELOG with all changes.

**Files to create/modify**:

- `tests/test_skills.sh` (new file — frontmatter validation, sections, cross-refs, schema, count)
- `CHANGELOG.md` (new `[1.13.0]` entry covering all milestones)

**Exit Criteria**:

- [ ] `tests/test_skills.sh` exists and is executable
- [ ] Tests validate every `skills/*/SKILL.md` has `name`, `description`, `user-invocable` frontmatter fields
- [ ] Tests validate each skill has at least one structural section (Usage, Workflow, Execution Flow, or Two Modes)
- [ ] Tests validate `review-suite/output-schema.json` is valid JSON
- [ ] Tests validate `implement/milestone-template.md` exists
- [ ] Tests validate skill directory count equals 13
- [ ] Tests validate no underscore timestamps in review-suite/SKILL.md
- [ ] `bash tests/test_skills.sh` passes with zero failures
- [ ] `bash tests/test_hooks.sh` still passes (regression check)
- [ ] `bash tests/test_toolkit_cli.sh` still passes (regression check)
- [ ] `python3 -m pytest tests/ -v` still passes (regression check)
- [ ] CHANGELOG.md has `[1.13.0]` entry with Fixed, Added, and Improved subsections

## Testing Strategy

### Unit Tests

- `tests/test_skills.sh` — ~50-60 assertions validating frontmatter, sections, companion files, timestamp consistency, skill count, and genericness

### Integration Tests

- Existing `test_hooks.sh`, `test_toolkit_cli.sh`, `test_manifest.sh` — verify no regressions
- Existing `python3 -m pytest tests/ -v` — verify no Python test regressions

### Manual Verification

- Read each modified SKILL.md to confirm changes are generic (no project-specific content)
- Verify all SKILL.md changes preserve valid YAML frontmatter
- Shellcheck `hooks/verify-completion.sh` if modified

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| Skill changes break existing invocations | Changes are additive documentation — no behavioral changes to skill execution |
| Auto-flow Task agents lack context | By design — clean context is the goal; skill files provide all needed instructions |
| toolkit.toml.example changes break config cache | All new sections are commented out (documentation only), no runtime impact |
| Test count assertion (13 skills) becomes stale | Test uses dynamic directory count, not hardcoded number — self-updating |

## Open Questions

- None — all questions resolved during planning phase

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **No P0 bugs remain**: Zero timestamp mismatches, zero contradictions in solve/implement skills
2. **All 13 skills documented**: README, CLAUDE.md, and reference.md all list 13 skills including verify
3. **All skill improvements applied**: Each finding from the evaluation is addressed in the corresponding SKILL.md
4. **Version check exists**: implement skill has explicit version file check before final summary

### Code Quality

1. **All tests pass**: `test_skills.sh` + `test_hooks.sh` + `test_toolkit_cli.sh` + `pytest` all green
2. **Shellcheck clean**: Any modified `.sh` files pass `shellcheck -x -S warning`
3. **Generic content**: No project-specific content in any SKILL.md or agent prompt

### User Experience

1. **Workflow discoverable**: README workflow map shows the complete skill pipeline at a glance
2. **Defaults discoverable**: `toolkit.toml.example` documents all tunable skill parameters
3. **Pipeline continuity**: `--auto-plan` and `--auto-implement` flags reduce manual handoffs

---

## Feedback Log

Planning phase — no codex/agent feedback yet.
