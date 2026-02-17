# Changelog

All notable changes to this project will be documented in this file.

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
