# Streamline Bootstrap/Setup — Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-16
>
> **Codex Iterations**: 0 of 10

## Summary

Simplify the new-project onboarding flow from three disconnected stages (bootstrap.sh → /setup skill → manual fixup) to two seamless stages: a minimal `bootstrap.sh` (git subtree only) + a comprehensive `/setup` skill that auto-detects everything, validates commands actually work, and commits a fully working configuration. Also handle existing projects with partial toolkit installations by making `/setup` detect gaps and fill them.

## North Star

A user runs `/setup` in Claude Code and gets a fully working, validated toolkit configuration — whether the project is brand new, partially set up, or being reconfigured. Claude guides the user through any manual steps (like the git subtree add) as needed.

## Principles

1. **Detect over ask** — auto-detect stacks, commands, dirs, and installation state from the project instead of requiring flags
2. **Validate over template** — only write commands to config that were proven to work
3. **Single orchestrator** — `/setup` is the one comprehensive tool for all scenarios (new, partial, reconfigure)
4. **Meet users where they are** — detect current state and do only what's needed, not a full re-install
5. **Backward compatible** — old `bootstrap.sh --name foo --stacks python` still works

## Research Findings

### Current Pain Points

- `bootstrap.sh` generates toolkit.toml with hardcoded templates (`.venv/bin/ruff check`, `make test-changed`) that are wrong for most projects
- `/setup` skill is a lightweight 118-line guide — it describes what to detect but doesn't enforce validation
- `templates/CLAUDE.md.template` exists with placeholders but nothing uses it during setup
- Nothing validates that lint/test commands actually execute successfully
- Three-stage flow requires context switching between terminal and Claude Code
- No handling for partial installations — if skills were deleted or init was interrupted, user must know to run `toolkit.sh init --force`
- `/setup` cannot guide users through initial bootstrap when toolkit isn't installed yet

### Existing Patterns to Reuse

- `generate-settings.py` — Python script that outputs JSON, called by both toolkit.sh and skills
- `generate-config-cache.py` — Python script with `--validate-only` flag, schema validation
- `templates/toolkit.toml.example` — complete TOML structure reference
- `templates/CLAUDE.md.template` — CLAUDE.md with `{{PROJECT_NAME}}`, `{{PROJECT_DESCRIPTION}}`, `{{TECH_STACK}}` placeholders
- `toolkit.sh init --from-example` — copies example TOML, sets up agents/skills/rules
- `toolkit.sh init --force` — overwrites existing agents/skills/rules (preserves customized files via manifest)
- `toolkit.sh validate` — checks symlinks, settings, hook executability, config freshness

### Scenarios to Handle

| Scenario | State | What /setup does |
| ---- | ----- | ---------------- |
| **Brand new project** | No `.claude/toolkit/` | Tells user to run bootstrap.sh, provides exact command |
| **Post-bootstrap (fresh)** | Subtree + example toolkit.toml | Full detection → validation → config → CLAUDE.md → commit |
| **Partial setup** | Subtree exists, some skills/agents missing | Runs `toolkit.sh init --force` to fill gaps, then full setup |
| **Configured but stale** | Working config, but toolkit updated | Re-detects, validates, refreshes settings, fills new skills |
| **Reconfigure** | Working config, user wants to re-detect | Full re-detection and validation from scratch |

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

### After (Claude Code-first)

```text
User opens Claude Code and runs /setup
  ↓
Phase 0: Detect installation state
  ├─ No toolkit → provide bootstrap.sh command, wait, continue
  ├─ Partial install → run toolkit.sh init --force to fill gaps
  └─ Full install → proceed to detection
  ↓
Phase 1: Auto-detect project (detect-project.py)
  ↓
Phase 2: Validate detected commands
  ↓
Phase 3: Present findings, ask for confirmation
  ↓
Phase 4-8: Generate config → CLAUDE.md → settings → verify → commit
```

For users who prefer the terminal-first approach, `bootstrap.sh` still works as a minimal git-only step.

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
    "package_scripts": [],
    "toolkit_state": {
      "subtree_exists": true,
      "toml_exists": true,
      "toml_is_example": false,
      "settings_generated": true,
      "missing_skills": [],
      "missing_agents": [],
      "broken_symlinks": []
    }
  }
```

The `toolkit_state` section lets `/setup` determine exactly what work is needed for the current project.

---

## Implementation Milestones

### M0: Create detect-project.py

Add a standalone Python detection script (stdlib only) that auto-detects project properties and toolkit installation state, outputs JSON. This is the foundation for both bootstrap.sh and /setup.

**Files to create**:

- `detect-project.py` (~250 lines)
- `tests/test_detect_project.py` (~300 lines)

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
- [ ] Detects toolkit installation state: subtree exists, toml exists, toml is still the unmodified example, settings.json generated, missing skills/agents, broken symlinks
- [ ] Uses only Python stdlib (no external deps except pytest for tests)
- [ ] All pytest tests pass: `python3 -m pytest tests/test_detect_project.py -v`
- [ ] Tests cover: each stack detection, multi-stack, empty project, version file precedence, source dir detection, Makefile parsing, package.json parsing, toolkit state detection (all scenarios)

### M1: Simplify bootstrap.sh

Strip bootstrap.sh down to git operations only. Remove TOML generation, make flags optional. Bootstrap becomes the minimal "get the subtree in place" step.

**Files to modify**:

- `bootstrap.sh` (remove ~200 lines, add ~30 lines)

**Exit Criteria**:

- [ ] `--name` flag is optional (defaults to directory basename)
- [ ] `--stacks` flag is optional (not used for TOML generation)
- [ ] Entire TOML generation section removed (old lines 165-330): no `_to_toml_array`, no stack-specific linter/gate templates
- [ ] Runs `toolkit.sh init --from-example` instead of generating custom TOML
- [ ] If `--name` provided, patches `project.name` in toolkit.toml after init
- [ ] If `--stacks` provided, patches `project.stacks` in toolkit.toml after init
- [ ] `--remote`, `--ref`, `--local`, `--commit` flags still work unchanged
- [ ] New `--repair` flag: if toolkit subtree already exists, runs `toolkit.sh init --force` to fill missing skills/agents/rules
- [ ] "Next steps" message tells user to run `/setup` in Claude Code with exact instructions
- [ ] Passes `shellcheck -x -S warning bootstrap.sh`
- [ ] Backward compatible: `bootstrap.sh --name foo --stacks python --commit` still works (just doesn't generate linter/gate config)

### M2: Rewrite /setup skill

Make the setup skill a comprehensive orchestrator that handles ALL scenarios: new project, partial setup, reconfigure. This is the primary Claude Code integration point.

**Files to modify**:

- `skills/setup/SKILL.md` (rewrite from ~118 lines to ~350 lines)

**Exit Criteria**:

- [ ] Phase 0 (State Detection): skill instructs to check toolkit installation state — is subtree present? Is toolkit.toml present? Are skills/agents complete?
- [ ] Phase 0 handles "no toolkit": if `.claude/toolkit/` doesn't exist, provides user the exact `bootstrap.sh` command to run (detecting local toolkit path or using remote URL), then waits for user to run it before continuing
- [ ] Phase 0 handles "partial install": if toolkit exists but skills/agents missing, runs `toolkit.sh init --force` to fill gaps before proceeding
- [ ] Phase 0 handles "stale config": if toolkit was updated (new version), notes what's new and offers to refresh
- [ ] Phase 1 (Project Discovery): skill instructs to run `detect-project.py` and use output as baseline
- [ ] Phase 2 (Command Validation): skill instructs to actually run each detected lint/test/format command and only keep validated ones
- [ ] Phase 3 (Present Findings): skill instructs to show detected config to user and ask for confirmation before proceeding
- [ ] Phase 4 (Generate toolkit.toml): for fresh setup, writes new toolkit.toml from detection results. For existing config, merges new detections while preserving user customizations (ask user about conflicts)
- [ ] Phase 5 (Generate CLAUDE.md): skill instructs to use `templates/CLAUDE.md.template` to create CLAUDE.md with detected values, or add toolkit section to existing CLAUDE.md
- [ ] Phase 6 (Settings & Validation): skill instructs to run `toolkit.sh generate-settings` and `toolkit.sh validate`
- [ ] Phase 7 (End-to-End Verification): skill instructs to run configured lint command on a real file and configured test command, iterate if failures
- [ ] Phase 8 (Commit): skill instructs to stage specific files and commit
- [ ] Skill stays GENERIC — no project-specific tool references, paths, or conventions
- [ ] YAML frontmatter preserved with correct metadata
- [ ] `--reconfigure` flag documented for full re-detection on existing projects

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
  - Toolkit state detection: no toolkit, partial install, full install, stale config

### Integration Tests

- Existing `tests/test_toolkit_cli.sh` must still pass (backward compat)
- Existing `tests/test_manifest.sh` must still pass
- Manual test: create scratch project, run simplified bootstrap.sh, verify init works

### Manual Verification

- **Scenario A (new project)**: Create fresh Python project, run `bootstrap.sh`, run `/setup` in Claude Code — verify full auto-detect and config
- **Scenario B (partial install)**: Delete some skills from `.claude/skills/`, run `/setup` — verify gaps detected and filled
- **Scenario C (existing config)**: On a project with working toolkit.toml, run `/setup --reconfigure` — verify re-detection preserves user customizations
- **Scenario D (no toolkit)**: Open Claude Code in project without toolkit, run `/setup` — verify it provides bootstrap instructions
- **Scenario E (backward compat)**: Run `bootstrap.sh --name foo --stacks python --commit` — verify it still works

### Shellcheck

- `shellcheck -x -S warning bootstrap.sh` passes

---

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| detect-project.py gives wrong results | /setup presents findings to user for confirmation before writing config |
| Lint/test commands fail during validation | Use fallback commands, mark unvalidated entries clearly in config comments |
| CLAUDE.md already exists with custom content | Only add toolkit section, never overwrite existing content |
| Breaking change for bootstrap.sh users | Keep all flags as optional backward-compatible args |
| detect-project.py becomes another script to maintain | Keep it simple, test thoroughly, stdlib only |
| Partial install detection misses edge cases | toolkit.sh validate already catches most issues; detect-project.py supplements |
| User runs /setup without toolkit installed | Phase 0 detects this and provides clear next steps instead of failing |

## Open Questions

- None currently — all design decisions resolved.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **New project flow works end-to-end**: `bootstrap.sh` (no flags) → `toolkit.sh init` succeeds → `/setup` in Claude Code produces fully working config
2. **Existing project with partial setup**: `/setup` detects missing skills/agents, fills gaps via `toolkit.sh init --force`, then completes configuration
3. **No-toolkit scenario**: `/setup` in a project without toolkit gives clear bootstrap instructions, doesn't crash or silently fail
4. **detect-project.py** correctly identifies stacks, commands, and dirs for at least: a Python project with pyproject.toml + ruff, a TypeScript project with tsconfig.json + eslint, an iOS project with .xcodeproj
5. **Validated commands only**: toolkit.toml generated by /setup contains only commands that were proven to execute successfully
6. **CLAUDE.md generation**: CLAUDE.md is created from template with correct detected values when none exists, and toolkit section is appended when one already exists
7. **Reconfigure preserves customizations**: `/setup --reconfigure` re-detects but asks before overwriting user's existing toolkit.toml values

### Backward Compatibility

1. **Old bootstrap.sh flags work**: `bootstrap.sh --name foo --stacks python --commit` still runs successfully
2. **Existing tests pass**: all 126+ pytest tests and bash integration tests pass unchanged
3. **Existing toolkit.toml files**: projects with existing toolkit.toml are not broken by the changes

### Code Quality

1. **shellcheck clean**: `shellcheck -x -S warning bootstrap.sh` — zero warnings
2. **No external deps**: detect-project.py uses only Python stdlib
3. **Genericity**: /setup skill contains zero project-specific references
4. **Test coverage**: detect-project.py has tests for every detection function with edge cases, including all toolkit state scenarios

### User Experience

1. **bootstrap.sh runs in <30 seconds** with no required flags
2. **`/setup` works from any starting state** — new, partial, or existing project
3. **`/setup` asks for confirmation** before writing config (Phase 3 present findings)
4. **Clear error messages** when commands fail validation
5. **No dead ends** — every scenario has a clear next step, never a cryptic error

---

## Feedback Log

_No feedback yet._
