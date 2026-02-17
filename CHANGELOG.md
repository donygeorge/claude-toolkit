# Changelog

All notable changes to this project will be documented in this file.

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
