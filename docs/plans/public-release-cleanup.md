# Public Release Cleanup — Implementation Plan

> **Status**: In Review
>
> **Last Updated**: 2026-02-18
>
> **Codex Iterations**: 2 of 10 (SOLID)

## Summary

Prepare the claude-toolkit repository for public release on GitHub by fixing stale metadata, removing internal planning artifacts, expanding CI coverage, and adding README badges. All findings come from the [idea doc](../ideas/public-release-cleanup.md) audit.

## North Star

A public visitor cloning the repo sees accurate version numbers, clean documentation, full CI passing, and professional badges — no internal artifacts or stale counts.

## Principles

1. **Accuracy over speed** — every count and version reference must match reality
2. **Delete, don't archive** — internal artifacts live in git history, not the tree
3. **CI parity** — every test suite that runs locally should run in CI
4. **Minimal diff** — change only what the audit identified; no scope creep

## Research Findings

### Current State (verified 2026-02-18)

| Metric | Stale Value | Actual Value |
| ------ | ----------- | ------------ |
| VERSION file | 1.10.0 | should be 1.14.0 |
| CLAUDE.md pytest count (line 26) | 290 | 314 |
| CLAUDE.md pytest count (line 124) | 290 | 314 |
| CLAUDE.md pytest count (line 205) | 126 | 314 |
| Skills count | correct (15) | 15 |
| Agents count | correct (10) | 10 |

### Files to Delete

- `docs/plans/setup-toolkit-update-contribute.md`
- `docs/plans/skill-improvements.md`
- `docs/plans/streamline-bootstrap-setup.md`
- `docs/plans/superpowers-enhancements.md`
- `docs/plans/toolkit-hardening.md`
- `docs/plans/toolkit-vs-superpowers.md`
- `docs/ideas/toolkit-vs-superpowers.md`

### CI Gaps

- `tests/test_hooks.sh` (50 assertions) — not in CI
- `tests/test_skills.sh` (89 tests) — not in CI

## Architecture

No architectural changes. This is a metadata and CI cleanup.

### Key Files

| File | Change |
| ---- | ------ |
| `VERSION` | Bump to 1.14.0 |
| `CHANGELOG.md` | Move Unreleased → [1.14.0] section |
| `CLAUDE.md` | Fix 3 stale pytest counts |
| `.github/workflows/ci.yml` | Add test_hooks.sh and test_skills.sh |
| `README.md` | Add CI, license, and version badges |
| `docs/plans/*` | Delete 6 internal plan files |
| `docs/ideas/toolkit-vs-superpowers.md` | Delete internal brainstorm |

## Implementation Milestones

### M0: Fix Version and Changelog

Bump the VERSION file and cut the Unreleased section into a proper release entry.

**Files to modify**:

- `VERSION` — change `1.10.0` to `1.14.0`
- `CHANGELOG.md` — rename `[Unreleased]` header to `[1.14.0] - 2026-02-18`, add a new empty `[Unreleased]` section above it

**Exit Criteria**:

- [x] `VERSION` contains exactly `1.14.0`
- [x] `CHANGELOG.md` has `[1.14.0] - 2026-02-18` section with M0-M9 items
- [x] `CHANGELOG.md` has an empty `[Unreleased]` section at the top
- [x] No other version references are stale

### M1: Fix Stale Counts in CLAUDE.md

Update all stale test counts to match current actuals.

**Files to modify**:

- `CLAUDE.md` line 26 — change `290 tests` to `314 tests`
- `CLAUDE.md` line 124 — change `290 pytest` to `314 pytest`
- `CLAUDE.md` line 205 — change `126 tests` to `314 tests`

**Exit Criteria**:

- [x] All three pytest count references in CLAUDE.md say `314`
- [x] No other stale counts remain in CLAUDE.md
- [x] `grep -c '290\|126' CLAUDE.md` returns 0

### M2: Delete Internal Planning Artifacts

Remove internal plan files and the competitive brainstorm from the tree.

**Files to delete**:

- `docs/plans/setup-toolkit-update-contribute.md`
- `docs/plans/skill-improvements.md`
- `docs/plans/streamline-bootstrap-setup.md`
- `docs/plans/superpowers-enhancements.md`
- `docs/plans/toolkit-hardening.md`
- `docs/plans/toolkit-vs-superpowers.md`
- `docs/ideas/toolkit-vs-superpowers.md`

**Files to keep** (do NOT delete):

- `docs/plans/public-release-cleanup.md` — this plan (active)
- `docs/ideas/public-release-cleanup.md` — the audit idea doc for this work

**Exit Criteria**:

- [x] Only `public-release-cleanup.md` remains in `docs/plans/`
- [x] Only `public-release-cleanup.md` remains in `docs/ideas/`
- [x] `git status` shows the 7 files as deleted

### M3: Expand CI Coverage

Add the two missing test suites to the GitHub Actions workflow. No dependency on prior milestones.

**Files to modify**:

- `.github/workflows/ci.yml` — add `bash tests/test_hooks.sh` and `bash tests/test_skills.sh` steps

**Exit Criteria**:

- [x] `ci.yml` includes a step running `bash tests/test_hooks.sh`
- [x] `ci.yml` includes a step running `bash tests/test_skills.sh`
- [x] YAML is valid (no syntax errors)
- [x] `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh` still passes locally

### M4: Add README Badges

Add CI status, license, and version badges to the top of README.md. **Depends on M0** (version number must be finalized first).

**Files to modify**:

- `README.md` — add badge line after the `# claude-toolkit` title

**Badges to add**:

- CI status: `![CI](https://github.com/donygeorge/claude-toolkit/actions/workflows/ci.yml/badge.svg)`
- License: `![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)`
- Version: `![Version](https://img.shields.io/badge/version-1.14.0-green.svg)`

**Exit Criteria**:

- [x] README.md has 3 badges on the line after the title
- [x] Badge URLs are correct and use the right repo path
- [x] Markdown renders correctly (no broken syntax)

### M5: Final Verification

Run the full test suite and validate everything is consistent.

**Commands to run** (each must exit 0):

1. `python3 -m pytest tests/ -v` — expect 314+ tests pass
2. `bash tests/test_hooks.sh` — expect 50 assertions pass
3. `bash tests/test_toolkit_cli.sh` — expect 67+ tests pass
4. `bash tests/test_manifest.sh` — expect 27+ tests pass
5. `bash tests/test_skills.sh` — expect 89+ tests pass
6. `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh` — expect 0 warnings

**Cross-check commands**:

- `cat VERSION` — must output `1.14.0`
- `grep 'version-1.14.0' README.md` — must match (badge version matches VERSION file)
- `head -10 CHANGELOG.md` — must show `[Unreleased]` then `[1.14.0] - 2026-02-18`
- `ls docs/plans/` — must show only `public-release-cleanup.md`
- `ls docs/ideas/` — must show only `public-release-cleanup.md`

**Exit Criteria**:

- [x] All 6 test/lint commands exit with code 0
- [x] All 5 cross-check commands produce expected output
- [x] No regressions introduced by any milestone

## Testing Strategy

### Automated Tests

- Full pytest suite (314 tests)
- Hook integration tests (50 assertions)
- CLI integration tests (67 tests)
- Manifest integration tests (27 tests)
- Skill integration tests (89 tests)
- Shellcheck on all .sh files

### Manual Verification

- Visually check README badges render correctly
- Confirm CHANGELOG formatting looks right
- Verify no internal artifacts remain in docs/

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| Stale counts already changed by other work | Verify actual counts at implementation time with `pytest --co -q` |
| CI workflow YAML syntax error | Validate YAML before committing |
| Badge URLs wrong after repo rename | Use current repo URL; easy to update later |
| Deleting plan files breaks something | Plans are documentation only — no code depends on them |
| Skill tests reference deleted plan files | Skill tests validate skills/, not docs/ — no risk |

## Post-Plan Steps (Out of Scope)

After this plan is implemented and committed, the user should:

1. Create a git tag: `git tag v1.14.0`
2. Push the tag: `git push origin v1.14.0`
3. Optionally create a GitHub release from the tag

These are NOT part of this plan — they happen after the cleanup commit.

## Open Questions

None — all decisions resolved in Phase 0.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **VERSION accuracy**: `cat VERSION` outputs `1.14.0`
2. **CHANGELOG consistency**: `[1.14.0]` section exists with correct date and M0-M9 items
3. **Count accuracy**: All pytest references in CLAUDE.md match the actual test count
4. **CI completeness**: All 5 test suites appear in ci.yml
5. **Clean tree**: No internal planning artifacts in docs/plans/ or docs/ideas/ (except this plan and its idea doc)

### Code Quality

1. **Shellcheck clean**: Zero warnings on all .sh files
2. **All tests pass**: 500+ tests across all suites
3. **Valid YAML**: ci.yml parses without errors

### User Experience

1. **README badges**: Three badges visible and correctly linked
2. **Professional first impression**: A visitor sees accurate metadata, clean docs, and passing CI

---

## Feedback Log

### Iteration 1 (Codex)

**Issues raised**: (1) M2 keep/delete file list ambiguous, (2) M5 exit criteria not specific enough, (3) M4 dependency on M0 not stated, (4) Missing post-release tagging step.

**Actions taken**: Clarified M2 with explicit "files to keep" list, added numbered commands with expected outputs to M5, added M0 dependency note to M4, added post-plan steps section for tagging.

### Iteration 2 (Codex)

**Result**: SOLID — "All prior feedback is incorporated and the milestones are specific, sequenced, and verifiable for a docs-only release."
