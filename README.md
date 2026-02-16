# claude-toolkit

A shareable collection of Claude Code hooks for safe, autonomous AI-assisted development.

## What is this?

Claude Code supports [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that run at various lifecycle events (pre-tool-use, post-tool-use, session start/end, etc.). This toolkit provides a battle-tested set of hooks extracted from a production project, covering:

- **Guard hooks** -- Block destructive commands (git push, rm -rf, DROP TABLE, etc.) and sensitive file writes (.env, credentials, certificates)
- **Session lifecycle hooks** -- Environment validation on startup, context injection, state preservation across compaction, cleanup on session end
- **Quality gate hooks** -- Lint/test enforcement on task completion, error classification with recovery suggestions, subagent output validation
- **Automation hooks** -- Auto-approve known-safe operations, async post-edit linting, uncommitted change warnings

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `guard-destructive.sh` | PreToolUse | Block destructive git, rm, SQL, eval, pipe-to-shell |
| `guard-sensitive-writes.sh` | PreToolUse | Block writes to .env, credentials, keys, .git internals |
| `auto-approve-safe.sh` | PermissionRequest | Auto-approve read-only and known-safe operations |
| `classify-error.sh` | PostToolUseFailure | Classify errors and suggest recovery strategies |
| `post-edit-lint.sh` | PostToolUse | Async lint after Python file edits |
| `task-completed-gate.sh` | TaskCompleted | Block task completion if lint/tests fail |
| `setup.sh` | SessionStart (once) | Validate development environment |
| `session-start.sh` | SessionStart | Load project state |
| `session-end-cleanup.sh` | SessionEnd | Clean temp files, truncate logs |
| `pre-compact.sh` | PreCompact | Save working state before context compaction |
| `post-compact-reinject.sh` | SessionStart (compact) | Re-inject context after compaction |
| `subagent-context-inject.sh` | SubagentStart | Inject project context into subagents |
| `subagent-quality-gate.sh` | SubagentStop | Validate subagent output quality |
| `verify-completion.sh` | Stop | Advisory warning about uncommitted changes |
| `notify.sh` | (helper) | Platform-aware notifications (macOS/Linux/CI) |
| `_config.sh` | (helper) | Shared configuration sourced by all hooks |

## Quick Start

1. Copy the `hooks/` directory into your project's `.claude/hooks/`
2. Configure hooks in your `.claude/settings.json`
3. Customize project-specific values marked with `# TODO: read from config`

## Status

This is an early extraction (v0.1.0). Hooks contain `# TODO: read from config` markers where project-specific values need to be replaced with configuration-driven behavior. Future versions will add a `toolkit.toml` configuration file and a generator script.

## License

MIT
