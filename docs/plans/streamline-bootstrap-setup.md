# Streamline Bootstrap/Setup — Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-16
>
> **Codex Iterations**: 0 of 10

## Summary

Simplify the new-project onboarding flow from three disconnected stages (bootstrap.sh → /setup skill → manual fixup) to a single copy-paste prompt the user gives Claude Code. This prompt handles everything: installing the toolkit subtree, running init, auto-detecting stacks and commands, validating that everything works, generating config, and committing. For projects that already have the toolkit, the `/setup` skill handles reconfiguration and repair of partial installs.

## North Star

A user copies one prompt into Claude Code and gets a fully working, validated toolkit configuration — from zero to done. For existing installs, `/setup` handles reconfiguration and repair.

## Principles

1. **One prompt from zero** — a self-contained bootstrap prompt in the README that works without any toolkit files pre-installed
2. **Detect over ask** — auto-detect stacks, commands, dirs, and installation state from the project instead of requiring flags
3. **Validate over template** — only write commands to config that were proven to work
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
- **Chicken-and-egg problem**: `/setup` skill lives inside the toolkit subtree, so it can't exist before the toolkit is installed. Users need to know to run bootstrap.sh first, but there's no guidance from within Claude Code

### Existing Patterns to Reuse

- `generate-settings.py` — Python script that outputs JSON, called by both toolkit.sh and skills
- `generate-config-cache.py` — Python script with `--validate-only` flag, schema validation
- `templates/toolkit.toml.example` — complete TOML structure reference
- `templates/CLAUDE.md.template` — CLAUDE.md with `{{PROJECT_NAME}}`, `{{PROJECT_DESCRIPTION}}`, `{{TECH_STACK}}` placeholders
- `toolkit.sh init --from-example` — copies example TOML, sets up agents/skills/rules
- `toolkit.sh init --force` — overwrites existing agents/skills/rules (preserves customized files via manifest)
- `toolkit.sh validate` — checks symlinks, settings, hook executability, config freshness

### Scenarios to Handle

| Scenario | Entry Point | What happens |
| ---- | ----------- | ------------ |
| **Brand new project** | Bootstrap prompt (copy-paste into Claude Code) | Claude runs bootstrap.sh → init → full detection → validation → config → commit |
| **Post-bootstrap (fresh)** | `/setup` | Full detection → validation → config → CLAUDE.md → commit |
| **Partial setup** | `/setup` | Detects missing skills/agents, runs `toolkit.sh init --force` to fill gaps, then full setup |
| **Configured but stale** | `/setup` | Re-detects, validates, refreshes settings, fills new skills |
| **Reconfigure** | `/setup --reconfigure` | Full re-detection and validation from scratch |

### The Chicken-and-Egg Problem

The `/setup` skill lives at `.claude/skills/setup/SKILL.md` inside the toolkit subtree. If the toolkit isn't installed, the skill doesn't exist — so `/setup` can never handle the "from zero" case.

**Solution**: A self-contained **bootstrap prompt** in the README that users copy-paste into Claude Code. This prompt contains all the instructions Claude needs to install the toolkit and configure it, without depending on any skill files. Once the toolkit is installed, `/setup` handles all subsequent scenarios.

## Architecture

### Before (3 stages, terminal-first)

```text
bootstrap.sh (--name, --stacks required, in terminal)
  → generates toolkit.toml with hardcoded templates
  → runs toolkit.sh init
  → user opens Claude Code
/setup skill (lightweight guide)
  → detects stacks, tweaks toolkit.toml
Manual review + commit
```

### After (Claude Code-first, two entry points)

```text
ENTRY POINT 1: Bootstrap prompt (new projects — no toolkit installed)
═══════════════════════════════════════════════════════════════════════
User copies prompt from README into Claude Code
  ↓
Claude runs: bash bootstrap.sh (from GitHub URL or local path)
  ↓
Claude runs: /setup (now available since toolkit is installed)
  ↓
Full detection → validation → config → CLAUDE.md → commit

ENTRY POINT 2: /setup skill (existing projects — toolkit already installed)
═══════════════════════════════════════════════════════════════════════
Phase 0: Detect installation state
  ├─ Partial install → run toolkit.sh init --force to fill gaps
  └─ Full install → proceed
  ↓
Phase 1-8: detect → validate → present → config → CLAUDE.md → settings → verify → commit
```

### Bootstrap Prompt Design

The prompt lives in the README (and as a standalone `BOOTSTRAP_PROMPT.md`). It is a **fully self-contained** instruction block — no fetching from GitHub, no external dependencies. The user copies it from the README (which they're already reading) and pastes it into Claude Code.

**Key design decisions**:

- Prompt contains the repo URL and the exact git commands inline — Claude runs them directly via Bash
- No `WebFetch`, no `curl`, no downloading scripts — just `git remote add` + `git subtree add`
- After the subtree is added, the `/setup` skill exists, so Claude reads and follows it for the detection/config flow
- Handles "already installed" by checking for `.claude/toolkit/` first

```text
Install and configure claude-toolkit for this project.

claude-toolkit is a collection of Claude Code hooks, agents, skills, and rules
for safe, autonomous AI-assisted development. It provides safety guards
(blocking destructive commands, sensitive file writes), quality gates
(auto-lint, auto-test), reusable agent prompts (reviewer, QA, security,
architect), and skill templates (code review, implementation, planning).
It integrates via git subtree under .claude/toolkit/ and is configured
through .claude/toolkit.toml.

Toolkit repo: https://github.com/donygeorge/claude-toolkit.git

Steps:
1. If .claude/toolkit/ already exists, skip to step 2.
   Otherwise, install the toolkit:
   git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git
   git fetch claude-toolkit
   git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
   bash .claude/toolkit/toolkit.sh init --from-example
2. Read .claude/skills/setup/SKILL.md and follow it to detect stacks,
   validate commands, generate toolkit.toml, create CLAUDE.md, and commit.
```

This is ~20 lines. The user copies it once from the README, pastes into Claude Code, and gets a fully configured toolkit. No terminal required.

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

- [x] `detect-project.py` exists at repo root with CLI entry point
- [x] Detects stacks from file presence: `*.py`/`pyproject.toml`/`requirements.txt` → python, `tsconfig.json`/`*.ts` → typescript, `*.xcodeproj`/`Package.swift`/`*.swift` → ios
- [x] Detects project name from `basename(git rev-parse --show-toplevel)`
- [x] Detects version file with precedence: package.json > pyproject.toml > VERSION
- [x] Detects source directories by scanning for common patterns (src/, app/, lib/, packages/)
- [x] Detects lint commands by probing executables (ruff, eslint, swiftlint) with `--version` check
- [x] Detects test commands by parsing Makefile targets and package.json scripts
- [x] Detects format commands (ruff format, prettier, swiftformat)
- [x] Outputs valid JSON to stdout with `--project-dir` flag
- [x] Has `--validate` flag that actually runs detected commands and records pass/fail
- [x] Detects toolkit installation state: subtree exists, toml exists, toml is still the unmodified example, settings.json generated, missing skills/agents, broken symlinks
- [x] Uses only Python stdlib (no external deps except pytest for tests)
- [x] All pytest tests pass: `python3 -m pytest tests/test_detect_project.py -v`
- [x] Tests cover: each stack detection, multi-stack, empty project, version file precedence, source dir detection, Makefile parsing, package.json parsing, toolkit state detection (all scenarios)

### M1: Simplify bootstrap.sh

Strip bootstrap.sh down to git operations only. Remove TOML generation, make flags optional. Bootstrap becomes the minimal "get the subtree in place" step.

**Files to modify**:

- `bootstrap.sh` (remove ~200 lines, add ~30 lines)

**Exit Criteria**:

- [x] `--name` flag is optional (defaults to directory basename)
- [x] `--stacks` flag is optional (not used for TOML generation)
- [x] Entire TOML generation section removed (old lines 165-330): no `_to_toml_array`, no stack-specific linter/gate templates
- [x] Runs `toolkit.sh init --from-example` instead of generating custom TOML
- [x] If `--name` provided, patches `project.name` in toolkit.toml after init
- [x] If `--stacks` provided, patches `project.stacks` in toolkit.toml after init
- [x] `--remote`, `--ref`, `--local`, `--commit` flags still work unchanged
- [x] New `--repair` flag: if toolkit subtree already exists, runs `toolkit.sh init --force` to fill missing skills/agents/rules
- [x] "Next steps" message tells user to run `/setup` in Claude Code with exact instructions
- [x] Passes `shellcheck -x -S warning bootstrap.sh`
- [x] Backward compatible: `bootstrap.sh --name foo --stacks python --commit` still works (just doesn't generate linter/gate config)

### M2: Rewrite /setup skill

Make the setup skill a comprehensive orchestrator for post-bootstrap scenarios: fresh config, partial installs, and reconfiguration. The "from zero" case is handled by the bootstrap prompt (M4), not this skill.

**Files to modify**:

- `skills/setup/SKILL.md` (rewrite from ~118 lines to ~350 lines)

**Exit Criteria**:

- [x] Phase 0 (State Detection): skill instructs to check toolkit state — is toolkit.toml present? Are skills/agents complete? Is config stale?
- [x] Phase 0 handles "partial install": if toolkit exists but skills/agents missing, runs `toolkit.sh init --force` to fill gaps before proceeding
- [x] Phase 0 handles "stale config": if toolkit was updated (new version), notes what's new and offers to refresh
- [x] Phase 0 handles "no toolkit.toml": if subtree exists but no toolkit.toml, runs `toolkit.sh init --from-example`
- [x] Phase 1 (Project Discovery): skill instructs to run `detect-project.py` and use output as baseline
- [x] Phase 2 (Command Validation): skill instructs to actually run each detected lint/test/format command and only keep validated ones
- [x] Phase 3 (Present Findings): skill instructs to show detected config to user and ask for confirmation before proceeding
- [x] Phase 4 (Generate toolkit.toml): for fresh setup, writes new toolkit.toml from detection results. For existing config, merges new detections while preserving user customizations (ask user about conflicts)
- [x] Phase 5 (Generate CLAUDE.md): skill instructs to use `templates/CLAUDE.md.template` to create CLAUDE.md with detected values, or add toolkit section to existing CLAUDE.md
- [x] Phase 6 (Settings & Validation): skill instructs to run `toolkit.sh generate-settings` and `toolkit.sh validate`
- [x] Phase 7 (End-to-End Verification): skill instructs to run configured lint command on a real file and configured test command, iterate if failures
- [x] Phase 8 (Commit): skill instructs to stage specific files and commit
- [x] Skill stays GENERIC — no project-specific tool references, paths, or conventions
- [x] YAML frontmatter preserved with correct metadata
- [x] `--reconfigure` flag documented for full re-detection on existing projects

### M3: Create bootstrap prompt

Create a self-contained prompt that users copy-paste into Claude Code to install and configure the toolkit from scratch. This solves the chicken-and-egg problem: the `/setup` skill can't exist before the toolkit is installed, but this prompt doesn't depend on any toolkit files.

**Files to create/modify**:

- `BOOTSTRAP_PROMPT.md` (new — the standalone prompt file)
- `README.md` (add "Quick Start" section with the prompt)

**Exit Criteria**:

- [x] `BOOTSTRAP_PROMPT.md` exists at repo root with a self-contained prompt block
- [x] Prompt contains the git commands inline (git remote add, git fetch, git subtree add) — no WebFetch, no curl, no downloading scripts
- [x] Prompt includes the toolkit GitHub URL as a parameter the user can customize
- [x] Prompt tells Claude to read and follow `.claude/skills/setup/SKILL.md` after install (not re-implement the setup logic)
- [x] Prompt handles the "already installed" case by checking for `.claude/toolkit/` and skipping to /setup
- [x] Prompt is concise (under 15 lines) — just enough for Claude to know what to do
- [x] README.md has a "Quick Start" section that shows the prompt with copy instructions
- [ ] Manual test: copy prompt into Claude Code in a fresh project, verify it installs toolkit and configures everything end-to-end

### M4: Update CLAUDE.md template + docs

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
- **Scenario D (from zero via prompt)**: Copy bootstrap prompt into Claude Code in a project with no toolkit — verify it installs, configures, and commits everything
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
| User tries /setup without toolkit installed | Skill doesn't exist; README directs them to the bootstrap prompt |

## Open Questions

- None currently — all design decisions resolved.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **New project via bootstrap prompt**: copy-paste prompt into Claude Code → toolkit installed → config detected and validated → committed. Zero manual steps.
2. **New project via bootstrap.sh**: `bootstrap.sh` (no flags) → `toolkit.sh init` succeeds → `/setup` in Claude Code produces fully working config
3. **Existing project with partial setup**: `/setup` detects missing skills/agents, fills gaps via `toolkit.sh init --force`, then completes configuration
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
