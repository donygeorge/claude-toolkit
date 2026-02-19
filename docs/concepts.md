# Toolkit Concepts

A 2-minute overview of how claude-toolkit works and what each component does.

## The Big Picture

claude-toolkit is a collection of scripts and prompts that plug into Claude Code's `.claude/` directory. It makes AI-assisted development safer and more productive by:

- **Blocking dangerous commands** before they run (guards)
- **Auto-approving safe operations** so you are not interrupted for every file read (automation)
- **Running quality checks** after edits and before task completion (quality gates)
- **Providing specialized AI agents** for code review, security, testing, and more
- **Offering reusable workflows** (skills) for common tasks like planning, implementing, and bug fixing

Everything is configured through one file (`toolkit.toml`) and integrated via git subtree so updates are easy.

## Components

### Hooks

Hooks are scripts (mostly shell, one Python) that Claude Code runs automatically at specific lifecycle events. You do not invoke them manually -- they fire in response to events like "a tool is about to run" or "the session is ending."

There are five categories:

- **Guards** block dangerous operations (destructive git commands, writes to secrets files)
- **Automation** auto-approves safe operations (reading files, running linters)
- **Quality gates** run checks after edits or before task completion (lint, tests)
- **Lifecycle** manage session state (environment validation, context preservation, cleanup)
- **Subagent** inject context into and validate output from spawned sub-agents

All hooks are configurable via `toolkit.toml`. They read their settings from a shared config layer (`_config.sh`) so you never need to edit hook scripts directly.

### Agents

Agents are markdown prompt files that define specialized AI personas. When Claude Code spawns a sub-agent (e.g., during a multi-agent code review), it loads the appropriate agent prompt to give that agent its instructions and personality.

Available agents include Reviewer (adversarial code review), QA (test execution), Security (vulnerability scanning), UX (accessibility), PM (product perspective), Docs (documentation accuracy), Architect (deep architecture analysis), Commit Check (post-commit sanity), and Plan (feature planning).

Agent prompts are generic by design -- they contain no project-specific paths, tools, or conventions. Project context is injected at runtime by the subagent-context hook.

### Skills

Skills are workflow templates triggered by slash commands in Claude Code (e.g., `/implement`, `/review-suite`, `/fix-github`). Each skill is a markdown file (SKILL.md) that describes a multi-step procedure for Claude to follow.

Unlike agents (which are symlinked and shared), skills are copied into your project during `init`. This means you can customize them for your project's specific needs.

### Rules

Rules are coding convention documents that Claude Code loads as context. They tell Claude how to write code for your project -- style guides, testing patterns, framework conventions.

Some rules are generic (like `git-protocol.md`, which is always included). Others are stack-specific templates (like `python.md` for Python conventions or `testing-pytest.md` for pytest patterns) that are applied based on your configured stacks.

### Stacks

Stacks represent the technology profiles of your project (e.g., `python`, `ios`, `typescript`). When you set `project.stacks` in `toolkit.toml`, two things happen:

1. **Settings overlays** are merged in -- each stack adds its own hook matchers, deny patterns, and tool configurations to your `settings.json`
2. **Rule templates** are applied -- stack-specific coding conventions are copied into your `.claude/rules/` directory

### Manifest

The manifest (`toolkit-manifest.json`) tracks whether each file installed by the toolkit is **managed** (controlled by the toolkit, updated automatically) or **customized** (taken over by your project, skipped during updates).

Use `toolkit.sh customize <file>` to convert a managed file to a customized one. This copies the file locally and marks it in the manifest so future `toolkit.sh update` commands leave it alone.

### Config System

Configuration flows through three layers:

1. **`toolkit.toml`** -- Your project's configuration file. Controls hook behavior, quality gates, linter commands, notification settings, and more.
2. **Config cache** (`toolkit-cache.env`) -- Generated bash environment variables from your TOML config. Hooks source this for fast access without parsing TOML at runtime.
3. **Three-tier settings merge** -- Base defaults + stack overlays + project overrides produce the final `settings.json` that Claude Code reads. When you first run `init` on a project that already has a `settings.json`, the toolkit automatically preserves it as `settings-project.json` so your existing configuration flows through the merge.

## How It All Fits Together

```text
toolkit.toml (your config)
    |
    v
generate-config-cache.py --> toolkit-cache.env (hooks read this)
    |
    v
generate-settings.py --> settings.json (Claude Code reads this)
                     --> .mcp.json (MCP server config)

Hooks fire automatically:
  SessionStart  --> setup.sh, session-start.sh
  PreToolUse    --> guard-destructive.sh, guard-sensitive-writes.sh
  PermissionRequest --> auto-approve-safe.sh
  PostToolUse   --> post-edit-lint.sh
  TaskCompleted --> task-completed-gate.sh
  SessionEnd    --> session-end-cleanup.sh
  ...
```

## Customization Tiers

1. **Configure** -- Edit `toolkit.toml` to change behavior without touching code
2. **Override** -- Create `settings-project.json` for project-specific Claude Code settings
3. **Extend** -- Use `toolkit.sh customize` to take ownership of any managed file
