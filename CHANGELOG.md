# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-02-15

### Added

- Initial extraction of 14 Claude Code hooks from Jarvin project
- Guard hooks: `guard-destructive.sh`, `guard-sensitive-writes.sh`
- Session lifecycle hooks: `setup.sh`, `session-start.sh`, `session-end-cleanup.sh`, `pre-compact.sh`, `post-compact-reinject.sh`
- Quality gate hooks: `classify-error.sh`, `task-completed-gate.sh`, `subagent-context-inject.sh`, `subagent-quality-gate.sh`
- Automation hooks: `auto-approve-safe.sh`, `post-edit-lint.sh`, `verify-completion.sh`
- Shared configuration helper: `hooks/_config.sh`
- Platform-aware notification helper: `hooks/notify.sh`
