# Streamline Bootstrap/Setup — Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-16
>
> **Codex Iterations**: 0 of 10

## Summary

Simplify the new-project onboarding flow from three disconnected stages (bootstrap.sh → /setup skill → manual fixup) to two seamless stages: a minimal `bootstrap.sh` (git subtree only) + a comprehensive `/setup` skill that auto-detects everything, validates commands actually work, and commits a fully working configuration.

## North Star

A user runs one shell command + one Claude Code slash command and gets a fully working, validated toolkit configuration — zero manual fixup needed.

## Principles

1. **Detect over ask** — auto-detect stacks, commands, and dirs from the project instead of requiring flags
2. **Validate over template** — only write commands to config that were proven to work
3. **Single orchestrator** — `/setup` is the one comprehensive tool, bootstrap.sh is just the git prerequisite
4. **Backward compatible** — old `bootstrap.sh --name foo --stacks python` still works

## Research Findings

### Current Pain Points

- `bootstrap.sh` generates toolkit.toml with hardcoded templates (`.venv/bin/ruff check`, `make test-changed`) that are wrong for most projects
- `/setup` skill is a lightweight 118-line guide — it describes what to detect but doesn't enforce validation
- `templates/CLAUDE.md.template` exists with placeholders but nothing uses it during setup
- Nothing validates that lint/test commands actually execute successfully
- Three-stage flow requires context switching between terminal and Claude Code

### Existing Patterns to Reuse

- `generate-settings.py` — Python script that outputs JSON, called by both toolkit.sh and skills
- `generate-config-cache.py` — Python script with `--validate-only` flag, schema validation
- `templates/toolkit.toml.example` — complete TOML structure reference
- `templates/CLAUDE.md.template` — CLAUDE.md with `{{PROJECT_NAME}}`, `{{PROJECT_DESCRIPTION}}`, `{{TECH_STACK}}` placeholders
- `toolkit.sh init --from-example` — copies example TOML, sets up agents/skills/rules

## Architecture

### Before (3 stages)

```text
bootstrap.sh (--name, --stacks required)
  → generates toolkit.toml with hardcoded templates
  → runs toolkit.sh init
  → user opens Claude Code
/setup skill (lightweight guide)
  → detects stacks
  → tweaks toolkit.toml
Manual review + commit
```

### After (2 stages)

```text
bootstrap.sh (no flags required)
  → adds git subtree
  → runs toolkit.sh init --from-example
  → prints "run /setup in Claude Code"

/setup skill (comprehensive orchestrator)
  → runs detect-project.py for baseline detection
  → validates every command by running it
  → presents findings, asks for confirmation
  → writes validated toolkit.toml
  → generates/updates CLAUDE.md from template
  → runs generate-settings + validate
  → end-to-end verification (run lint + tests)
  → commits everything
```

### New File: detect-project.py

```text
detect-project.py --project-dir /path/to/project
  → outputs JSON:
  {
    "name": "my-project",
    "stacks": ["python"],
    "version_file": "pyproject.toml",
    "source_dirs": ["src", "tests"],
    "source_extensions": ["*.py"],
    "lint": {"py": {"cmd": "...", "fmt": "...", "validated": true}},
    "test": {"cmd": "...", "validated": true},
    "makefile_targets": [...],
    "package_scripts": [...]
  }
```

---

## Implementation Milestones

### M0: Create detect-project.py

Add a standalone Python detection script (stdlib only) that auto-detects project properties and outputs JSON. This is the foundation for both bootstrap.sh and /setup.

**Files to create**:

- `detect-project.py` (~200 lines)
- `tests/test_detect_project.py` (~250 lines)

**Exit Criteria**:

- [ ] `detect-project.py` exists at repo root with CLI entry point
- [ ] Detects stacks from file presence: `*.py`/`pyproject.toml`/`requirements.txt` → python, `tsconfig.json`/`*.ts` → typescript, `*.xcodeproj`/`Package.swift`/`*.swift` → ios
- [ ] Detects project name from `basename(git rev-parse --show-toplevel)`
- [ ] Detects version file with precedence: package.json > pyproject.toml > VERSION
- [ ] Detects source directories by scanning for common patterns (src/, app/, lib/, packages/)
- [ ] Detects lint commands by probing executables (ruff, eslint, swiftlint) with `--version` check
- [ ] Detects test commands by parsing Makefile targets and package.json scripts
- [ ] Detects format commands (ruff format, prettier, swiftformat)
- [ ] Outputs valid JSON to stdout with `--project-dir` flag
- [ ] Has `--validate` flag that actually runs detected commands and records pass/fail
- [ ] Uses only Python stdlib (no external deps except pytest for tests)
- [ ] All pytest tests pass: `python3 -m pytest tests/test_detect_project.py -v`
- [ ] Tests cover: each stack detection, multi-stack, empty project, version file precedence, source dir detection, Makefile parsing, package.json parsing

### M1: Simplify bootstrap.sh

Strip bootstrap.sh down to git operations only. Remove TOML generation, make flags optional, add auto-detection via detect-project.py.

**Files to modify**:

- `bootstrap.sh` (remove ~200 lines, add ~20 lines)

**Exit Criteria**:

- [ ] `--name` flag is optional (defaults to directory basename)
- [ ] `--stacks` flag is optional (not used for TOML generation)
- [ ] Entire TOML generation section removed (old lines 165-330): no `_to_toml_array`, no stack-specific linter/gate templates
- [ ] Runs `toolkit.sh init --from-example` instead of generating custom TOML
- [ ] If `--name` provided, writes just the `[project] name` into toolkit.toml after copying example
- [ ] If `--stacks` provided, writes just the `[project] stacks` into toolkit.toml after copying example
- [ ] `--remote`, `--ref`, `--local`, `--commit` flags still work unchanged
- [ ] "Next steps" message tells user to run `/setup` in Claude Code
- [ ] Passes `shellcheck -x -S warning bootstrap.sh`
- [ ] Backward compatible: `bootstrap.sh --name foo --stacks python --commit` still works (just doesn't generate linter/gate config)

### M2: Rewrite /setup skill

Make the setup skill a comprehensive 8-phase orchestrator that detects, validates, configures, and commits everything.

**Files to modify**:

- `skills/setup/SKILL.md` (rewrite from ~118 lines to ~300 lines)

**Exit Criteria**:

- [ ] Phase 1 (Project Discovery): skill instructs to run `detect-project.py` and use output as baseline
- [ ] Phase 2 (Command Validation): skill instructs to actually run each detected lint/test/format command and only keep validated ones
- [ ] Phase 3 (Present Findings): skill instructs to show detected config to user and ask for confirmation before proceeding
- [ ] Phase 4 (Generate toolkit.toml): skill instructs to write toolkit.toml using validated results, referencing `templates/toolkit.toml.example` for structure
- [ ] Phase 5 (Generate CLAUDE.md): skill instructs to use `templates/CLAUDE.md.template` to create CLAUDE.md with detected values, or add toolkit section to existing CLAUDE.md
- [ ] Phase 6 (Settings & Validation): skill instructs to run `toolkit.sh generate-settings` and `toolkit.sh validate`
- [ ] Phase 7 (End-to-End Verification): skill instructs to run configured lint command on a real file and configured test command, iterate if failures
- [ ] Phase 8 (Commit): skill instructs to stage specific files and commit
- [ ] Skill stays GENERIC — no project-specific tool references, paths, or conventions
- [ ] YAML frontmatter preserved with correct metadata
- [ ] `--reconfigure` flag documented for re-detection on existing projects

### M3: Update CLAUDE.md template + docs

Update the CLAUDE.md template to support detected commands and update documentation.

**Files to modify**:

- `templates/CLAUDE.md.template` (add placeholders for lint/test commands)
- `CHANGELOG.md` (add entry)

**Exit Criteria**:

- [ ] `templates/CLAUDE.md.template` has `{{LINT_COMMAND}}`, `{{TEST_COMMAND}}`, `{{FORMAT_COMMAND}}` placeholders replacing hardcoded `make lint`, `make test`, `make fmt`
- [ ] Template's "Key Commands" section uses the new placeholders
- [ ] Template's "Before Marking Complete" checklist uses the new placeholders
- [ ] Template's "During Implementation" section uses the new placeholders
- [ ] `CHANGELOG.md` has entry documenting the streamlined setup flow
- [ ] All existing tests still pass: `python3 -m pytest tests/ -v`

---

## Testing Strategy

### Unit Tests

- `tests/test_detect_project.py`: comprehensive detection logic tests using `tmp_path` fixtures
  - Stack detection (python, typescript, ios, multi-stack, none)
  - Version file precedence
  - Source directory detection
  - Makefile target parsing
  - package.json script parsing
  - Command probing with mock executables
  - JSON output format validation

### Integration Tests

- Existing `tests/test_toolkit_cli.sh` must still pass (backward compat)
- Existing `tests/test_manifest.sh` must still pass
- Manual test: create scratch project, run simplified bootstrap.sh, verify init works

### Manual Verification

- Create a fresh Python project, run `bootstrap.sh`, run `/setup` in Claude Code
- Verify: auto-detected stacks match, lint/test commands validated, CLAUDE.md generated, everything committed
- Test `bootstrap.sh --name foo --stacks python --commit` backward compatibility

### Shellcheck

- `shellcheck -x -S warning bootstrap.sh` passes

---

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| detect-project.py gives wrong results | /setup skill presents findings to user for confirmation before writing config |
| Lint/test commands fail during validation | Use fallback commands, mark unvalidated entries clearly in config comments |
| CLAUDE.md already exists with custom content | Only add toolkit section, never overwrite existing content |
| Breaking change for bootstrap.sh users | Keep all flags as optional backward-compatible args |
| detect-project.py becomes another script to maintain | Keep it simple, test thoroughly, stdlib only |

## Open Questions

- None currently — all design decisions resolved.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **New flow works end-to-end**: `bootstrap.sh` (no flags) → `toolkit.sh init` succeeds → `/setup` can run
2. **detect-project.py** correctly identifies stacks, commands, and dirs for at least: a Python project with pyproject.toml + ruff, a TypeScript project with tsconfig.json + eslint, an iOS project with .xcodeproj
3. **Validated commands only**: toolkit.toml generated by /setup contains only commands that were proven to execute successfully
4. **CLAUDE.md generation**: CLAUDE.md is created from template with correct detected values when none exists, and toolkit section is appended when one already exists

### Backward Compatibility

1. **Old bootstrap.sh flags work**: `bootstrap.sh --name foo --stacks python --commit` still runs successfully
2. **Existing tests pass**: all 126+ pytest tests and bash integration tests pass unchanged
3. **Existing toolkit.toml files**: projects with existing toolkit.toml are not broken by the changes

### Code Quality

1. **shellcheck clean**: `shellcheck -x -S warning bootstrap.sh` — zero warnings
2. **No external deps**: detect-project.py uses only Python stdlib
3. **Genericity**: /setup skill contains zero project-specific references
4. **Test coverage**: detect-project.py has tests for every detection function with edge cases

### User Experience

1. **bootstrap.sh runs in <30 seconds** with no required flags
2. **`/setup` asks for confirmation** before writing config (Phase 3 present findings)
3. **Clear error messages** when commands fail validation

---

## Feedback Log

_No feedback yet._
