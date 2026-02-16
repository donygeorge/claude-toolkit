# Changelog

All notable changes to this project will be documented in this file.

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
