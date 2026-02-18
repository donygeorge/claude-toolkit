# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

- M0: Fix Description Trap violations in commit and conventions skill descriptions (trigger-condition format)
- M1: Standardize Critical Rules sections across all 12 skills
- M2: Add rationalization prevention tables to solve, refine, review-suite, implement, plan
- M3: Remove hardcoded years from brainstorm, add model portability notes
- M4: Add TDD enforcement config (strict/guided/off) for implement skill
- M5: Add spec-first review preset (reviewer + docs + pm in thorough mode)
- M6: Split setup-toolkit into 4 focused skills (toolkit-setup, toolkit-update, toolkit-doctor, toolkit-contribute)

## [1.13.0] - 2026-02-17

### Fixed

- **Review-suite timestamp format**: Fix run_id timestamp format in review-suite to match output-schema.json (dash format instead of underscore)
- **Implement allowed-tools wording**: Fix "removed from" wording in implement skill (now "intentionally not listed")
- **Solve visual tools contradiction**: Fix "MUST use visual tools" contradiction in solve skill (now "SHOULD attempt")

### Added

- **Verify skill documentation**: Document /verify skill in README, CLAUDE.md, and reference docs (13 skills total)
- **Skill workflow map**: Add skill workflow map to README showing brainstorm -> plan -> implement -> verify pipeline
- **Brainstorm auto-plan flag**: Add `--auto-plan` flag to brainstorm skill for pipeline continuity
- **Plan auto-implement flag**: Add `--auto-implement` flag to plan skill for pipeline continuity
- **Implement version check**: Add version file check (Step 2e) to implement skill
- **Skill defaults in toolkit.toml**: Add skill defaults documentation to toolkit.toml.example with commented `[skills.*]` sections
- **Skill defaults reference**: Add Skill Defaults subsection to docs/reference.md
- **Skill test infrastructure**: Add `tests/test_skills.sh` with 75 assertions validating frontmatter, structural sections, companion files, skill count, and timestamp consistency
- **Gemini agent**: Move Gemini from standalone skill to reusable agent prompt (`agents/gemini.md`); brainstorm `--gemini` flag now references the agent
- **Doctor MCP checks**: Add npm/npx, Gemini CLI, and Codex MCP availability checks to `toolkit.sh doctor`

### Improved

- **Brainstorm skill**: Improve persona prompt template, gemini timing, team shutdown, ad-hoc threshold
- **Implement skill**: Improve state schema with phase tracking, enhanced resume logic
- **Refine skill**: Improve convergence threshold clarification, scope evolution, clean-room termination
- **Plan skill**: Improve idea doc detection, agent launch spec, unified codex stop condition
- **Fix skill**: Improve scan scope limits, test addition decision tree
- **Commit skill**: Improve session file detection strategy
- **Skill customization notes**: Add customization notes to 7 major skills referencing `toolkit.sh customize`

## [1.12.0] - 2026-02-17

### Added

- **Hook debug mode**: Set `TOOLKIT_HOOK_DEBUG=true` to enable verbose debug logging in hooks. Shows tool name, command, file path, and decision points in guard and auto-approve hooks via new `hook_debug()` function in `lib/hook-utils.sh`
- **Gate bypass**: Set `TOOLKIT_SKIP_GATES=all` to bypass all quality gates, or `TOOLKIT_SKIP_GATES=lint,tests` to skip specific gates. Useful for debugging false positives without editing `toolkit.toml`
- **Review packet schema**: `review-suite` skill now defines the full JSON schema for `review_packet.json` with required fields, evidence downgrade rules, and examples
- **Rollback guidance**: Both `implement` and `setup-toolkit --update` skills now include step-by-step rollback instructions using `git revert` (never destructive `git reset --hard`)
- **Commit-check integration**: The orphaned `commit-check` agent is now fully integrated into `review-suite` as a `quick` preset (`/review commit-check` or `/review quick`), with keyword mapping and execution details

### Fixed

- **Implement graceful degradation**: Build failures now correctly block the milestone and ask user for guidance instead of incorrectly skipping the test phase
- **Contribute flow safety**: Phase C2.3 now shows a preview diff BEFORE applying changes to toolkit source (previously applied first, then showed diff)
- **Contribute flow cleanup**: Phase C4.6 now reverts only contributed files instead of all `.claude/toolkit/` changes, preventing data loss of unrelated in-progress work

## [1.11.0] - 2026-02-17

### Added

- **Brainstorm skill**: `/brainstorm` (alias `/explore`, `/ideate`) provides structured idea exploration with dynamic persona-based agent teams, deep internet research on latest trends (2025-2026), multi-approach evaluation with comparative matrix, and documented recommendations in `docs/ideas/` compatible with `/plan` input. First skill to use Claude Code's experimental agent team feature (TeamCreate/SendMessage). Features six distinct research personas (the-pragmatist, the-innovator, the-critic, the-user-advocate, the-architect, the-researcher) that create productive tension through different thinking styles. Supports three depth modes (shallow/normal/deep), up to 7 user questions per checkpoint via two-round AskUserQuestion pattern, optional Gemini second opinion, and Codex feedback loop. Includes persona disagreement tracking to surface real trade-offs.

## [1.10.0] - 2026-02-17

### Added

- **Setup skill `--update` mode**: `/setup-toolkit --update [version]` provides an LLM-guided toolkit update workflow with pre-flight checks (status, validate, uncommitted changes), version preview with CHANGELOG entries, intelligent conflict resolution with user confirmation, 10-point post-update validation (shellcheck, validate, generate-settings, JSON validity, symlink health, manifest integrity, hook executability, config cache freshness, project tests, project lint), drift resolution for customized files (keep/merge/revert per file), and a structured summary with commit
- **Setup skill `--contribute` mode**: `/setup-toolkit --contribute` provides an LLM-guided contribution workflow for upstreaming generic improvements from consuming projects back to the toolkit, featuring candidate identification via status and diff, a 10-point generalizability gate (7 hard requirements + 3 quality requirements), full toolkit test suite validation, and PR submission workflow with generated patch and description
- **Contributing guide**: New "Contributing from a Consuming Project" section in `CONTRIBUTING.md` documenting both the `/setup-toolkit --contribute` workflow and a manual workflow for users without the skill, with the full 10-point generalizability checklist
- **Public release prep**: Added `LICENSE` (MIT), `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` (vulnerability reporting policy), GitHub issue templates (bug report, feature request), and PR template with testing checklist
- **Version sync**: `VERSION` file now tracks the current release version

### Fixed

- **Security**: Fix sed metacharacter injection in `cmd-init.sh` — replaced `sed` template substitution with `awk` to prevent `{{PROJECT_NAME}}` values containing sed metacharacters from corrupting output
- **Security**: Fix incomplete JSON escaping in `subagent-context-inject.sh` fallback path — add backslash escaping before quote escaping when jq is unavailable
- **Security**: Harden command execution in `task-completed-gate.sh` — use `read -ra` array parsing instead of bare word splitting for lint/test commands, preventing glob expansion of config values
- **Security**: Add tool type guard to `guard-sensitive-writes.sh` — now only runs for Write/Edit operations instead of all PreToolUse events
- **Security**: Fix `_atomic_write` in `hook-utils.sh` to preserve trailing newlines (use `printf '%s\n'` matching other implementations)
- **Security**: Use lambda replacement in `bootstrap.sh` regex TOML patching to prevent backreference injection
- **Bug**: Remove nonexistent `subagent-quality-gate.sh` from `cmd-explain.sh` hook listing
- **Bug**: Fix `task-completed-gate.sh` `git diff HEAD` failure on initial commits — fall back to `git diff --cached`
- **Bug**: Fix truncation constant in `session-end-cleanup.sh` — was 55 (leaving negative tail lines for small configs), now 8 (head-5 + 3 separator lines)
- **Bug**: Fix `post-edit-lint.sh` directory traversal check — `*..*` matched legitimate filenames like `foo..bar.py`, now uses `*/../*|*/..*` for actual traversal patterns only
- **Bug**: Consolidate `_atomic_write` in `session-end-cleanup.sh` — source `hook-utils.sh` instead of inline duplicate
- **Bug**: Replace hardcoded `make test`/`make lint` in `skills/solve/SKILL.md` and `skills/fix/SKILL.md` with generic `<project-test-command>`/`<project-lint-command>` placeholders
- **Docs**: Update metrics across CLAUDE.md and README.md — fix skill count (10 → 11), pytest count (126 → 290), add missing entries (bootstrap.sh, detect-project.py, commit skill, setup-toolkit/ directory name, test_detect_project.py, test_hooks.sh)

## [1.9.0] - 2026-02-16

### Added

- **Commit skill**: `/commit` skill creates a local commit with only files touched in the current session that are uncommitted; uses haiku model for fast, cheap execution; auto-generates commit message from diff; does nothing if there are no uncommitted session files

## [1.8.0] - 2026-02-16

### Added

- **Self-describing stacks**: Stack JSON files now include `_meta` key with `name`, `description`, and `required_tools`; `_meta` is stripped during settings merge so it never appears in generated `settings.json`; `toolkit.sh status` auto-discovers and displays available stacks with descriptions
- **Custom hook directory**: Projects can now place custom hooks in `.claude/hooks-custom/`; `TOOLKIT_CUSTOM_HOOKS_DIR` variable exported by `_config.sh` for reference in project settings
- **Config caching optimization**: `_config.sh` now tracks cache file mtime via `_TOOLKIT_CONFIG_LOADED` env var; subsequent hook invocations skip re-sourcing if the cache file hasn't changed
- **Agent version metadata**: All 9 agent prompts now include `version` and `toolkit_min_version` in YAML frontmatter for version tracking
- **Smart-context CLI**: `smart-context/framework.py` now supports `--help`, `--version`, and CLI arguments (`--context-dir`, `--context-suffix`, `--max-dynamic-size`, `--max-always-size`, `--project-name`) for standalone usage without `_config.sh` dependency
- **6 new tests**: `_meta` stripping tests (strip_meta unit tests, merge integration, real stack validation)

### Changed

- **CONTRIBUTING.md**: Updated with self-describing stack file format documentation and custom hooks directory guide
- **TOML staleness warning**: Now runs even when config is cached (previously skipped when `_TOOLKIT_CONFIG_LOADED` matched)

## [1.7.0] - 2026-02-16

### Added

- **Documentation split**: Trimmed `README.md` from 403 to 138 lines with quick-start focus; moved detailed content to `docs/reference.md` (full configuration reference for all CLI commands, toolkit.toml options, hooks, agents, skills, stacks) and `docs/concepts.md` (2-minute mental model explainer covering hooks, agents, skills, rules, stacks, manifest, config system)
- **CONTRIBUTING.md**: Contributor guide covering how to add new hooks, agents, skills, and stacks, plus testing requirements, shellcheck requirements, and the generic-by-default philosophy
- **Explain command**: `toolkit.sh explain [topic]` provides plain-language explanations of toolkit concepts; topics: overview, hooks, agents, skills, rules, config, stacks
- **10 new CLI tests**: explain command tests covering all 7 topics, unknown topic handling, and help output integration

### Changed

- **Help output**: Updated to show `explain` command with examples
- **CLAUDE.md**: Updated project structure (added docs/, cmd-explain.sh), documentation table, and CLI command reference

## [1.6.0] - 2026-02-16

### Added

- **Settings schema validation**: `validate_settings_schema()` in `generate-settings.py` warns on unknown top-level keys, unknown hook event types, unknown hook entry fields, and structural issues (e.g., `permissions.allow` not being a list). Warnings are printed to stderr but do not block generation.
- **Manifest corruption recovery**: `_validate_manifest()` in `lib/manifest.sh` detects corrupted (non-JSON) manifests, backs them up, and triggers automatic regeneration via `manifest_init`. Called at the start of every manifest operation (`manifest_customize`, `manifest_update_skill`, `manifest_check_drift`).
- **Dry-run mode**: `--dry-run` flag for `init` and `generate-settings` commands shows what would be created/modified without mutating any files. Works both as a subcommand flag (`init --dry-run`) and global flag (`--dry-run init`).
- **Doctor command**: `toolkit.sh doctor` provides comprehensive health checks beyond `validate` — checks tool versions (bash, jq, python3, git), Python 3.11+ for tomllib, config cache freshness, settings.json parity (compares against what `generate-settings` would produce), symlink health, manifest integrity, hook executability, hook health (runs sample inputs through guard-destructive and auto-approve), and optional tools.
- **Update integrity verification**: `cmd-update.sh` now runs `shellcheck` on pulled code after `git subtree pull` and shows a `git diff --stat` of changes.
- **26 new tests**: 16 schema validation tests, 11 array merge edge case tests, 8 manifest corruption recovery tests, 9 CLI tests (dry-run, doctor)

### Changed

- **Help output**: Updated to show `doctor` command and `--dry-run` global flag

## [1.5.0] - 2026-02-16

### Changed

- **CLI modularization**: Split monolithic `toolkit.sh` (1050 lines) into a thin dispatcher (137 lines) plus 7 modular subcommand files in `lib/cmd-*.sh`: `cmd-init.sh`, `cmd-update.sh`, `cmd-customize.sh`, `cmd-status.sh`, `cmd-validate.sh`, `cmd-generate-settings.sh`, `cmd-help.sh`
- **Init helper decomposition**: Broke `cmd_init` (280 lines) into 9 focused helper functions: `_init_toml`, `_init_agents`, `_init_skills`, `_init_rules`, `_init_rule_templates`, `_init_agent_memory`, `_init_git_remote`, `_init_config`, `_init_manifest`
- **Moved `_refresh_symlinks`**: Relocated from `toolkit.sh` to `lib/cmd-update.sh` where it belongs (only used by the update flow)

## [1.4.0] - 2026-02-16

### Added

- **Shared hook utilities**: `lib/hook-utils.sh` extracts common patterns (input parsing, deny/approve responses, audit logging, atomic writes, standardized logging) into a shared library, reducing code duplication across hooks
- **Standardized logging**: `hook_warn()`, `hook_error()`, `hook_info()` helpers output `[toolkit:hook-name]` prefixed messages to stderr; all hooks updated to use this format
- **Bash 3.2 compatibility check**: `hooks/_config.sh` now warns at load time if bash version is older than 3.2 (macOS default)
- **`.editorconfig`**: Project-wide editor settings for consistent formatting (LF line endings, UTF-8, per-language indent styles)

### Changed

- **Hook migration**: `guard-destructive.sh`, `guard-sensitive-writes.sh`, and `auto-approve-safe.sh` now source `lib/hook-utils.sh` for shared `hook_read_input`, `hook_deny`, `hook_approve`, `hook_approve_and_persist`, and `_audit_log` functions instead of inline implementations
- **Shebang standardization**: All `.sh` files now use `#!/usr/bin/env bash` consistently (was `#!/bin/bash` in 13 hook files)
- **Error message format**: Hook error/warning messages in `setup.sh`, `task-completed-gate.sh`, and `subagent-quality-gate.sh` now use `[toolkit:hook-name]` prefix pattern

## [1.3.0] - 2026-02-16

### Added

- **Audit logging**: Guard hooks (`guard-destructive.sh`, `guard-sensitive-writes.sh`) now log all DENY decisions to `.claude/guard-audit.log` with timestamp, hook name, and reason
- **Config file protection**: `guard-sensitive-writes.sh` blocks direct AI writes to `.claude/settings.json`, `.claude/toolkit.toml`, and `.claude/toolkit-cache.env` (both absolute and relative paths)
- **TOML type validation**: `validate_schema()` now enforces type checks for `str`, `int`, `list`, and `dict` fields instead of silently accepting mismatches
- **Env var name validation**: Config cache generation validates that all generated bash variable names match `^[A-Z_][A-Z0-9_]*$`, rejecting keys that could produce unsafe or injectable variable names
- **Control character rejection**: TOML values containing control characters (except `\n` and `\t`) are now rejected, including CR (0x0d) which can enable log injection attacks
- **46 new security tests**: env key validation (12), control char rejection (12), key injection (11), type validation (9), file permissions (1), plus shift-out test

### Fixed

- **Security**: All shared file writes (manifest, config cache, session state) now use atomic write pattern (temp file + `mv`) to prevent corruption from concurrent access
- **Security**: Generated files (`toolkit-cache.env`, `settings.json`) now have 0600 permissions via `umask 077` and `os.chmod()`
- **Security**: `mktemp` in `pre-compact.sh` now fails cleanly instead of falling back to predictable `/tmp/toolkit_*_$$` paths

## [1.2.0] - 2026-02-16

### Added

- **Hook test framework**: `tests/test_hooks.sh` with 50 integration tests covering guard-destructive (14 tests), auto-approve-safe (12 tests), guard-sensitive-writes (8 tests), edge cases (8 tests), subagent network blocking (2 tests), database file protection (3 tests), and error classification (3 tests)

### Fixed

- **Security**: Add `set -u` (undefined variable check) to all 15 hook scripts to catch silent undefined variable bugs; each hook includes a rationale comment explaining why `set -e`/`set -o pipefail` are intentionally omitted
- **Security**: Escape JSON output in `deny()` fallback paths (when jq unavailable) in `guard-destructive.sh` and `guard-sensitive-writes.sh`
- **Security**: Add path validation in `post-edit-lint.sh` to reject absolute paths outside the project directory
- **Security**: Add `${VAR:-}` defaults for environment variables that may be unset (`CLAUDE_SUBAGENT_TYPE`, `CI`, `GITHUB_ACTIONS`, `JENKINS_HOME`, `DISPLAY`, `WAYLAND_DISPLAY`)
- **Security**: Add `--` to `grep -qE` calls that use config-sourced patterns to prevent option injection
- **Bug**: Fix `CRITICAL_PATHS` default in `guard-destructive.sh` — literal single quotes in regex prevented matching (e.g., `rm -rf src/` was not blocked)
- **Bug**: Fix `DB_PATTERN` default in `guard-sensitive-writes.sh` — same literal single quotes bug
- Document intentional word splitting in `task-completed-gate.sh` lint/test command execution

## [1.1.0] - 2026-02-16

### Added

- **Streamlined setup flow**: single copy-paste bootstrap prompt takes a project from zero to fully configured toolkit — no manual terminal steps required
- `detect-project.py`: auto-detects project stacks, lint/test/format commands, source directories, version files, and toolkit installation state; outputs JSON for use by `/setup-toolkit` and `bootstrap.sh`
- `BOOTSTRAP_PROMPT.md`: self-contained prompt users paste into Claude Code to install and configure the toolkit from scratch, solving the chicken-and-egg problem where `/setup-toolkit` can't exist before the toolkit is installed

### Changed

- `bootstrap.sh`: simplified to git subtree operations + `toolkit.sh init`; `--name` and `--stacks` flags now optional; removed ~200 lines of TOML generation; added `--repair` flag for partial installs
- `/setup-toolkit` skill: rewritten as comprehensive 9-phase orchestrator (state detection, project discovery, command validation, user confirmation, config generation, CLAUDE.md creation, settings generation, end-to-end verification, commit)
- `templates/CLAUDE.md.template`: replaced hardcoded `make` commands with `{{LINT_COMMAND}}`, `{{TEST_COMMAND}}`, `{{FORMAT_COMMAND}}`, `{{RUN_COMMAND}}` placeholders for project-specific customization

## [1.0.1] - 2026-02-16

### Fixed

- **Security**: Fix command injection in `toolkit.sh` `_read_toml_value` — use `sys.argv` instead of string interpolation
- **Security**: Replace `eval` with safe array-based `find` in `pre-compact.sh`
- **Bug**: Fix `auto-approve-safe.sh` subshell exit bug — `approve()` in piped `while` loop only exited subshell, not script. Use process substitution instead
- **Bug**: Fix incomplete JSON escaping in `classify-error.sh` fallback path (escape backslashes, tabs)
- Remove project-specific scripts from `ios.json` stack (was leaking personal project paths)
- Remove bare `Bash(npx:*)` from `typescript.json` stack (conflicted with auto-approve npx block)
- Pin MCP server versions in `base.mcp.json` instead of using `@latest`
- Switch manifest file hashing from MD5 to SHA-256
- Fix inconsistent `encoding="utf-8"` in `smart-context/framework.py`
- Make security agent generic — remove specific tool install commands
- Fix `reviewer.md` referencing non-existent output-schema.json path
- Fix CLAUDE.md project structure to accurately reflect rules/ vs templates/rules/
- Fix temp file cleanup in `pre-compact.sh` — use `mktemp` with cleanup trap

## [1.0.0] - 2026-02-16

### Added

- 16 configurable hooks (14 extracted from production use + `_config.sh` + `notify.sh`)
- Config system: `toolkit.toml` with TOML-to-bash cache (`toolkit-cache.env`)
- Settings generation: three-tier merge (base + stack overlays + project overrides)
- 9 generic agent prompts (reviewer, qa, security, ux, pm, docs, architect, commit-check, plan)
- 9 skill templates (review-suite, implement, plan, solve, fix, refine, conventions, scope-resolver, gemini)
- Smart-context framework for keyword-based domain context loading
- MCP configuration templates (context7, playwright)
- Rule templates for Python, Swift, TypeScript, pytest, Jest, SQLite, FastAPI
- CLI with 7 subcommands: init, update, customize, validate, status, generate-settings, help
- Manifest system for tracking managed vs customized files
- Platform-aware notifications (macOS/Linux/CI)
- Stack overlays: Python, iOS, TypeScript
- Git subtree update workflow with customization preservation
- GitHub Actions CI (shellcheck + pytest + bash integration tests)
- 190+ tests (126 pytest + bash integration tests)

## [0.1.0] - 2026-02-15

### Added

- Initial extraction of 14 Claude Code hooks from Jarvin project
- Guard hooks: `guard-destructive.sh`, `guard-sensitive-writes.sh`
- Session lifecycle hooks: `setup.sh`, `session-start.sh`, `session-end-cleanup.sh`, `pre-compact.sh`, `post-compact-reinject.sh`
- Quality gate hooks: `classify-error.sh`, `task-completed-gate.sh`, `subagent-context-inject.sh`, `subagent-quality-gate.sh`
- Automation hooks: `auto-approve-safe.sh`, `post-edit-lint.sh`, `verify-completion.sh`
- Shared configuration helper: `hooks/_config.sh`
- Platform-aware notification helper: `hooks/notify.sh`
