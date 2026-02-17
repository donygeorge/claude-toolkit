# Extend `/setup-toolkit` with Update & Contribute Modes — Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-16
>
> **Codex Iterations**: 0 of 10

## Summary

Extend the existing `/setup-toolkit` skill with two new modes (`--update` and `--contribute`) to handle the complete toolkit lifecycle from a single entry point. The update mode provides LLM-guided pulling of toolkit updates with thorough pre/post validation, intelligent conflict resolution, and drift management. The contribute mode enables users to upstream generic improvements back to the toolkit repo with a very high generalizability bar. Both modes end with comprehensive change summaries.

## North Star

A user runs `/setup-toolkit --update` and gets a fully validated, conflict-free toolkit update — with every customization preserved or intelligently merged. A user runs `/setup-toolkit --contribute` and gets a contribution that is guaranteed generic, fully tested, and ready to PR.

## Principles

1. **Super-thorough validation** — run every check possible in both directions (10+ validation steps for update, 7+ for contribute)
2. **Smart conflict handling** — LLM resolves merge conflicts and drift intelligently, not generically
3. **Very high bar for contributions** — 10-point generalizability gate, no exceptions
4. **Comprehensive summaries** — both modes end with detailed, structured summaries of everything that happened

## Research Findings

### Current State

**Update workflow** (`toolkit.sh update`):
- Core CLI works: git subtree pull, manifest preservation, symlink refresh, settings regen
- **Gaps**: No conflict resolution guidance (just "You may need to resolve conflicts"), no pre-flight validation, no drift resolution tooling, no post-update project test/lint validation, no version preview, no summary
- Implementation: [lib/cmd-update.sh](lib/cmd-update.sh) (205 lines), [lib/manifest.sh](lib/manifest.sh) (383 lines)

**Upstream workflow**: Complete gap
- `toolkit.sh customize` marks files as customized and breaks symlinks ([lib/cmd-customize.sh](lib/cmd-customize.sh), 49 lines)
- `manifest_check_drift` detects when customized files have upstream changes ([lib/manifest.sh:316](lib/manifest.sh#L316))
- `cmd_status` shows customized and modified files ([lib/cmd-status.sh](lib/cmd-status.sh))
- **Missing**: No contribute command, no generalizability check, no submission workflow, no documentation for contributing from consuming projects

### Existing Patterns to Reuse

- `toolkit.sh status` — already shows customized files, drift, version info
- `toolkit.sh validate` — already checks symlinks, settings, hooks, config freshness
- `manifest_check_drift()` — already compares customized file hashes against current toolkit
- `toolkit.sh update` — already handles git subtree pull, customization preservation
- `/setup-toolkit` skill phases 0-8 — existing phased execution pattern with user confirmation

### Key Files

| File | Role |
|------|------|
| [skills/setup-toolkit/SKILL.md](skills/setup-toolkit/SKILL.md) | **Primary edit target** — add `--update` and `--contribute` flows |
| [lib/cmd-update.sh](lib/cmd-update.sh) | Existing update CLI — skill wraps this |
| [lib/cmd-customize.sh](lib/cmd-customize.sh) | Existing customize CLI — contribute flow reads from this |
| [lib/manifest.sh](lib/manifest.sh) | Manifest functions (drift check, customize, update skill) |
| [lib/cmd-status.sh](lib/cmd-status.sh) | Status command — used for pre-flight in both modes |
| [docs/reference.md](docs/reference.md) | Skills reference — needs update |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributing guide — needs upstream section |

---

## Implementation Milestones

### M0: Add `--update` mode to `/setup-toolkit`

Extend the setup-toolkit skill with a complete LLM-guided update workflow. This adds phases U0-U5 as a separate execution branch triggered by the `--update` flag.

**Files to modify**:

- `skills/setup-toolkit/SKILL.md` (~200 lines added)

**Exit Criteria**:

- [ ] Skill frontmatter `argument-hint` updated to include `[--update [version]]`
- [ ] Usage section shows `--update` and `--update v1.3.0` examples
- [ ] Flags table includes `--update [version]` with description
- [ ] Routing logic added at top of Execution Flow: if `--update` passed, jump to Update Flow
- [ ] Phase U0 (Pre-flight): instructs to run `toolkit.sh status`, `toolkit.sh validate`, check `git diff` and `git status` for uncommitted changes, resolve issues before proceeding
- [ ] Phase U1 (Fetch & Preview): instructs to fetch tags, show current vs available versions, display CHANGELOG entries for version range, preview drift for customized files. **Ask user**: which version to update to (present options). **Wait for confirmation** before proceeding.
- [ ] Phase U2 (Execute Update): instructs to run `toolkit.sh update [version]`, on conflict detect via `git diff --diff-filter=U`. **Ask user**: resolve conflicts automatically or abort? If resolving, show proposed resolution for each conflicted file and **ask user to confirm** before applying.
- [ ] Phase U3 (Post-Update Validation): includes ALL 10 checks: shellcheck, toolkit validate, generate-settings, JSON validity, symlink health, manifest integrity, hook executability, config cache freshness, project test suite, project lint. Max 3 fix attempts per issue. **Ask user** if any validation failure is unclear or requires a judgment call.
- [ ] Phase U4 (Drift Resolution): for each customized file with drift, show both versions, analyze nature of changes. **Ask user for each file**: keep customization, merge upstream changes, or revert to managed? Perform intelligent merge if chosen, show result and **ask user to confirm** before applying. Update manifest hashes after confirmation.
- [ ] Phase U5 (Summary & Commit): mandatory structured summary template with: version transition, files changed, customizations preserved, drift resolved, all 10 validation results, new features from CHANGELOG, action required (restart Claude Code). **Ask user** to review summary before committing. Stages and commits.
- [ ] User interaction principle documented: "When in doubt, ask. Never make assumptions about which version to pull, how to resolve conflicts, or what to do with drift. Present options and let the user decide."
- [ ] Error handling table covers: fetch failure, subtree pull conflict, validation failures, drift merge failure
- [ ] Skill content remains GENERIC — no project-specific paths, tools, or conventions

### M1: Add `--contribute` mode to `/setup-toolkit`

Extend the setup-toolkit skill with an LLM-guided contribution workflow featuring a very high generalizability bar. This adds phases C0-C5 as a separate execution branch triggered by the `--contribute` flag.

**Files to modify**:

- `skills/setup-toolkit/SKILL.md` (~200 lines added)

**Exit Criteria**:

- [ ] Skill frontmatter `argument-hint` updated to include `[--contribute]`
- [ ] Usage section shows `--contribute` example
- [ ] Flags table includes `--contribute` with description
- [ ] Routing logic handles `--contribute` flag alongside `--update`
- [ ] Phase C0 (Identify Candidates): instructs to run `toolkit.sh status`, diff each customized/modified file against toolkit source, present analysis with generic vs project-specific assessment. **Ask user**: which changes do you want to propose contributing? Let user select/deselect candidates.
- [ ] Phase C1 (Generalizability Gate): defines 10-point checklist — 7 hard requirements (no project paths, no project tool refs, no project conventions, no project defaults, config-driven variability, agent/skill genericness, hook uses _config.sh) and 3 quality requirements (backward compatible, follows patterns, clear purpose). For mixed changes, show what would be kept vs removed and **ask user to confirm** the extraction. Fail with specific guidance. **Ask user**: want to revise the change to make it more generic, or skip this file?
- [ ] Phase C2 (Prepare Clean Changes): instructs to apply only approved changes to toolkit source, verify clean application. If toolkit source has diverged, show the divergence and **ask user** how to proceed (adapt changes, skip, or abort). Show final prepared changes and **ask user to review** before validation.
- [ ] Phase C3 (Validate Contribution): instructs to run FULL toolkit test suite — shellcheck, pytest, CLI tests, manifest tests, hook tests, settings determinism, edge case verification. ALL must pass, no exceptions. **Ask user** if test failures need investigation or if the contribution should be adjusted.
- [ ] Phase C4 (Prepare Submission): instructs to generate patch, write contribution description. **Ask user**: fork workflow or direct push? **Ask user** to review the PR title/summary before finalizing. Provide copy-pasteable commands.
- [ ] Phase C5 (Summary): mandatory structured summary template with: changes proposed, all 10 generalizability checks, all validation results, submission instructions
- [ ] User interaction principle documented: "The contribute flow is collaborative. At every decision point — which files to contribute, how to extract generic parts, how to handle divergence, which submission workflow — ask the user. Never auto-proceed past a judgment call."
- [ ] Error handling table covers: no customized files found, generalizability gate failure, test failures, toolkit source divergence
- [ ] Skill content remains GENERIC — no project-specific paths, tools, or conventions

### M2: Documentation & CHANGELOG

Update reference docs, contributing guide, and changelog to document the new modes.

**Files to modify**:

- `docs/reference.md`
- `CONTRIBUTING.md`
- `CHANGELOG.md`

**Exit Criteria**:

- [ ] `docs/reference.md` Skills Reference table: Setup skill entry updated to show `--update` and `--contribute` flags with descriptions
- [ ] `CONTRIBUTING.md`: new section "Contributing from a Consuming Project" added after "Pull Request Process"
- [ ] CONTRIBUTING section explains `/setup-toolkit --contribute` as the primary workflow
- [ ] CONTRIBUTING section includes brief manual workflow (for users without the skill): identify changes via `toolkit.sh status` + `diff`, verify generalizability manually, clone toolkit, apply changes, run full test suite, open PR
- [ ] CONTRIBUTING section emphasizes the generalizability requirement (link to the 10-point checklist concept)
- [ ] `CHANGELOG.md`: entry documenting `--update` and `--contribute` modes added to setup-toolkit skill
- [ ] All existing tests still pass: `python3 -m pytest tests/ -v`
- [ ] All existing CLI tests pass: `bash tests/test_toolkit_cli.sh`
- [ ] All existing hook tests pass: `bash tests/test_hooks.sh`
- [ ] All shell scripts pass: `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh`

---

## Testing Strategy

### Automated Tests

All existing tests must continue to pass (no code changes, only markdown/docs):
- `python3 -m pytest tests/ -v` (292+ tests)
- `bash tests/test_toolkit_cli.sh` (67+ tests)
- `bash tests/test_manifest.sh` (27+ tests)
- `bash tests/test_hooks.sh` (50+ tests)
- `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh`

### Manual Verification

- **Update flow**: In a test project with toolkit installed, run `/setup-toolkit --update` — verify pre-flight checks, version preview, update execution, post-update validation (all 10 checks), summary output
- **Update with drift**: Customize a file, update toolkit (so upstream has changes), run `/setup-toolkit --update` — verify drift is detected and resolution options work
- **Contribute flow**: Customize a file with a generic improvement, run `/setup-toolkit --contribute` — verify candidate identification, generalizability gate, validation, submission instructions
- **Contribute gate rejection**: Customize a file with project-specific content, run `/setup-toolkit --contribute` — verify the generalizability gate catches and rejects it with specific guidance

---

## Evaluation Criteria

### Functional Correctness

1. **Update pre-flight**: `/setup-toolkit --update` detects uncommitted changes and health issues before attempting update
2. **Update conflict handling**: When subtree pull has conflicts, the skill detects them, offers resolution or abort, and handles both paths correctly
3. **Update validation thoroughness**: All 10 post-update checks run and issues are caught
4. **Update drift resolution**: Customized files with upstream changes are identified, analyzed, and user gets clear merge/keep/revert options
5. **Update summary**: Complete structured summary covering version, files, customizations, drift, validation, changelog, and action items
6. **Contribute candidate identification**: All customized and modified files are found and diffed
7. **Contribute generalizability gate**: All 10 checks are evaluated; project-specific content is caught and rejected with specific guidance
8. **Contribute validation**: Full toolkit test suite runs; failures are caught and reported
9. **Contribute submission**: Ready-to-use fork workflow commands and PR description generated

### User Interaction

1. **Update asks before proceeding**: User is asked to confirm version choice, conflict resolution approach, drift resolution per-file, and final summary before commit
2. **Contribute asks at every decision**: User selects candidates, confirms extractions, reviews prepared changes, chooses submission workflow, and reviews PR description
3. **Never auto-proceeds past judgment calls**: Both flows pause and ask when something is ambiguous or requires user preference
4. **Graceful uncertainty handling**: When the LLM is unsure about conflict resolution, generalizability, or test failure attribution, it presents options and asks rather than guessing

### Quality

1. **Skill is GENERIC**: Zero project-specific paths, tools, or conventions in the SKILL.md
2. **Follows existing patterns**: New phases match the style of existing phases 0-8
3. **Documentation complete**: Reference docs, contributing guide, and changelog all updated
4. **No regressions**: All existing tests pass unchanged

---

## Open Questions

- None currently — all design decisions resolved.

---

## Feedback Log

_No feedback yet._
