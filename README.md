# claude-toolkit

A shareable, configurable collection of Claude Code hooks, agents, skills, and rules for safe, autonomous AI-assisted development.

## What is this?

Claude Code supports [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that run at various lifecycle events. This toolkit provides a battle-tested set of hooks extracted from production use, along with agent prompts, skill templates, coding rules, and a configuration system that adapts to your project.

**Key features:**

- **16 configurable hooks** covering safety, quality, and automation
- **9 agent prompts** for code review, QA, security, architecture, and more
- **10 skill templates** for review, planning, implementation, setup, and bug fixing
- **Config-driven**: One `toolkit.toml` file controls everything
- **Three-tier settings**: Base defaults + stack overlays + project overrides
- **Manifest tracking**: Know which files are managed vs customized
- **Git subtree updates**: Pull toolkit updates without losing your customizations

## Quick Start

### Claude Code Prompt (Recommended)

Copy the prompt below and paste it into Claude Code in your project. Claude will install the toolkit, detect your project's stacks and commands, and configure everything.

```text
Install and configure claude-toolkit for this project. claude-toolkit provides
Claude Code hooks, agents, skills, and rules for safe, autonomous AI-assisted
development. It integrates via git subtree under .claude/toolkit/.

Toolkit repo: https://github.com/donygeorge/claude-toolkit.git

1. If .claude/toolkit/ already exists, skip to step 2. Otherwise install:
   git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git || true
   git fetch claude-toolkit
   git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
   bash .claude/toolkit/toolkit.sh init --from-example
2. Read and follow .claude/skills/setup/SKILL.md (the /setup skill) to detect
   stacks, validate commands, generate toolkit.toml, create CLAUDE.md, and commit.
```

If you use a fork, replace the GitHub URL above. See [BOOTSTRAP_PROMPT.md](BOOTSTRAP_PROMPT.md) for the standalone version.

### Shell Bootstrap (Alternative)

If you prefer a shell script, run from your project root:

```bash
bash /path/to/claude-toolkit/bootstrap.sh --name my-project --stacks python
```

Then open Claude Code and run `/setup` to auto-detect and validate your configuration.

### Manual Setup

<details>
<summary>Click to expand manual steps</summary>

#### 1. Add the toolkit as a git subtree

```bash
git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git
git fetch claude-toolkit
git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
```

#### 2. Create your configuration

```bash
bash .claude/toolkit/toolkit.sh init --from-example
# Edit .claude/toolkit.toml to match your project
```

#### 3. Run /setup in Claude Code

Open Claude Code in your project and run `/setup`. Claude will detect your stacks, validate commands, and generate the full configuration.

#### 4. Commit

```bash
git add .claude/ .mcp.json CLAUDE.md
git commit -m "Add claude-toolkit"
```

</details>

## CLI Commands

The toolkit ships with a CLI at `.claude/toolkit/toolkit.sh` providing 7 subcommands:

### `init`

Initialize the toolkit in your project. Symlinks agents and rules, copies skills, generates settings.

```bash
bash .claude/toolkit/toolkit.sh init                # Requires toolkit.toml to exist
bash .claude/toolkit/toolkit.sh init --from-example  # Create toolkit.toml from example
bash .claude/toolkit/toolkit.sh init --force         # Overwrite existing files
```

### `update`

Update the toolkit from the remote repository via git subtree pull.

```bash
bash .claude/toolkit/toolkit.sh update              # Update to latest tagged release
bash .claude/toolkit/toolkit.sh update v1.2.0       # Update to specific version
bash .claude/toolkit/toolkit.sh update --latest      # Update to latest main branch
bash .claude/toolkit/toolkit.sh update --force       # Skip uncommitted change check
```

After updating, managed files are refreshed and settings regenerated. Customized files are preserved.

### `customize`

Convert a managed file to a customized one. The file is copied locally and marked in the manifest so future updates skip it.

```bash
bash .claude/toolkit/toolkit.sh customize agents/reviewer.md
bash .claude/toolkit/toolkit.sh customize skills/implement/SKILL.md
```

### `status`

Show toolkit version, project info, config staleness, and list customized or modified files.

```bash
bash .claude/toolkit/toolkit.sh status
```

### `validate`

Check toolkit health: verify symlinks resolve, settings.json is valid, hook scripts exist and are executable, config is not stale.

```bash
bash .claude/toolkit/toolkit.sh validate
```

### `generate-settings`

Regenerate `settings.json` and `.mcp.json` from the three-tier merge of base + stacks + project settings.

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

### `help`

Show usage information for all subcommands.

```bash
bash .claude/toolkit/toolkit.sh help
```

## Configuration Reference

All configuration lives in `.claude/toolkit.toml`. The full reference:

### `[toolkit]`

| Key | Type | Description |
|-----|------|-------------|
| `remote_url` | string | Git remote URL for the toolkit repo (used by `update`) |

### `[project]`

| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Display name used in session banners and notifications |
| `version_file` | string | Path to file containing the current version |
| `stacks` | array | Technology stacks: `"python"`, `"ios"`, `"typescript"` |

### `[hooks.setup]`

| Key | Type | Description |
|-----|------|-------------|
| `python_min_version` | string | Minimum Python version (e.g., `"3.11"`) |
| `required_tools` | array | Tools that must be installed |
| `optional_tools` | array | Tools that are nice to have |
| `security_tools` | array | Security scanning tools (optional) |

### `[hooks.post-edit-lint.linters.<ext>]`

Per-extension lint configuration. `<ext>` is the file extension without dot (e.g., `py`, `ts`).

| Key | Type | Description |
|-----|------|-------------|
| `cmd` | string | Lint check command (receives file path as argument) |
| `fmt` | string | Format command (receives file path as argument) |
| `fallback` | string | Fallback command name if `cmd` is not found |

### `[hooks.task-completed.gates.<name>]`

Quality gates checked before task completion.

| Key | Type | Description |
|-----|------|-------------|
| `glob` | string | File glob pattern that triggers this gate |
| `cmd` | string | Command to run (exit 0 = pass) |
| `timeout` | integer | Max seconds before the gate is killed (default: 90) |

### `[hooks.auto-approve]`

| Key | Type | Description |
|-----|------|-------------|
| `write_paths` | array | Glob patterns for Write/Edit paths to auto-approve |
| `bash_commands` | array | Bash command prefixes to auto-approve |

### `[hooks.subagent-context]`

| Key | Type | Description |
|-----|------|-------------|
| `critical_rules` | array | Rules injected into every subagent |
| `available_tools` | array | Tools/capabilities available in this project |
| `stack_info` | string | Short tech stack description for subagents |

### `[hooks.compact]`

| Key | Type | Description |
|-----|------|-------------|
| `source_dirs` | array | Directories scanned for recently modified files |
| `source_extensions` | array | File extensions to include |
| `state_dirs` | array | Directories checked for active orchestration state |

### `[hooks.session-end]`

| Key | Type | Description |
|-----|------|-------------|
| `agent_memory_max_lines` | integer | Max lines in agent memory before truncation |
| `hook_log_max_lines` | integer | Max lines in hook log before pruning |

### `[notifications]`

| Key | Type | Description |
|-----|------|-------------|
| `app_name` | string | Application name shown in notifications |
| `permission_sound` | string | macOS sound name (`"Blow"`, `"Ping"`, `"none"`, etc.) |

## What's Included

### Hooks (16)

| Hook | Event | Purpose |
|------|-------|---------|
| `guard-destructive.sh` | PreToolUse | Block destructive git, rm, SQL, eval, pipe-to-shell |
| `guard-sensitive-writes.sh` | PreToolUse | Block writes to .env, credentials, keys, .git internals |
| `auto-approve-safe.sh` | PermissionRequest | Auto-approve read-only and known-safe operations |
| `classify-error.sh` | PostToolUseFailure | Classify errors and suggest recovery strategies |
| `post-edit-lint.sh` | PostToolUse | Async lint after file edits |
| `task-completed-gate.sh` | TaskCompleted | Block task completion if quality gates fail |
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

### Agents (9)

| Agent | Purpose |
|-------|---------|
| `reviewer.md` | Adversarial code review, bugs, missing tests |
| `qa.md` | Test execution and validation |
| `security.md` | Secrets, SAST, dependency vulnerabilities |
| `ux.md` | Accessibility (WCAG 2.1 AA), VoiceOver, dark mode |
| `pm.md` | Product perspective, user workflows |
| `docs.md` | Documentation accuracy, code-doc sync |
| `architect.md` | Deep architecture analysis, patterns, resiliency |
| `commit-check.md` | Lightweight post-commit sanity check |
| `plan.md` | Feature planning agent prompt |

### Skills (10)

| Skill | Purpose |
|-------|---------|
| `setup` | Bootstrap claude-toolkit in a new project |
| `review-suite` | Multi-agent code review orchestration |
| `implement` | Autonomous plan execution with milestone agents |
| `plan` | Feature planning with research and review |
| `solve` | GitHub issue workflow (fetch, reproduce, fix, commit) |
| `fix` | Standalone bug fix without GitHub issue |
| `refine` | Iterative evaluate-fix-validate convergence loop |
| `conventions` | View coding conventions for a domain |
| `scope-resolver` | Resolve feature scopes for review targeting |
| `gemini` | Second opinion from Google's model |

### Rule Templates (7)

Applied based on your `project.stacks` configuration:

| Template | Stack | Provides |
|----------|-------|----------|
| `python.md` | python | Python 3.11+ conventions, ruff, type hints |
| `swift.md` | ios | SwiftUI, HealthKit/HomeKit patterns |
| `typescript.md` | typescript | TypeScript/Node conventions |
| `testing-pytest.md` | python | pytest patterns and fixtures |
| `testing-jest.md` | typescript | Jest testing patterns |
| `api-routes-fastapi.md` | python | FastAPI route conventions |
| `database-sqlite.md` | python | SQLite WAL mode patterns |

Plus `git-protocol.md` (always included).

### Stack Overlays (3)

Settings overlays merged during `generate-settings`:

| Stack | Adds |
|-------|------|
| `python` | Python-specific hook matchers, deny patterns |
| `ios` | iOS/Swift-specific hook matchers |
| `typescript` | TypeScript/Node-specific hook matchers |

### Other

- **Smart-context framework**: `smart-context/` -- keyword-based domain context loading
- **MCP templates**: `mcp/base.mcp.json` -- base MCP server configuration
- **CLAUDE.md template**: `templates/CLAUDE.md.template` -- project instructions template

## Three-Tier Settings

Settings are generated by merging three layers:

1. **Base** (`templates/settings-base.json`): Default hooks, deny list, environment variables common to all projects
2. **Stack overlays** (`templates/stacks/*.json`): Stack-specific additions (Python, iOS, TypeScript)
3. **Project overrides** (`.claude/settings-project.json`): Your project-specific customizations

Run `generate-settings` to rebuild after changing any layer:

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

The result is written to `.claude/settings.json` and `.mcp.json`.

## Customization

### Tier 1: Configuration

Edit `toolkit.toml` to change hook behavior, quality gates, linter commands, notification settings, etc. No code changes needed.

### Tier 2: Override

Create `.claude/settings-project.json` to add project-specific settings that merge on top of the generated base + stack settings.

### Tier 3: Extend

Use `customize` to take ownership of any managed file:

```bash
bash .claude/toolkit/toolkit.sh customize agents/reviewer.md
```

This converts the symlink to a local copy and marks it in the manifest. Future `update` commands will skip customized files.

## Contributing

### Development Setup

```bash
git clone <repo-url>
cd claude-toolkit
python3 -m venv .venv
source .venv/bin/activate
pip install pytest
```

### Running Tests

```bash
# Python unit tests (126 tests)
python3 -m pytest tests/ -v

# Shell script linting
shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh

# CLI integration tests
bash tests/test_toolkit_cli.sh

# Manifest integration tests
bash tests/test_manifest.sh
```

### Making Changes

1. Edit hooks, agents, skills, or templates
2. Run the full test suite
3. Update CHANGELOG.md
4. Submit a pull request

## Requirements

- **bash** 4.0+ (hook scripts)
- **jq** (JSON processing in hooks and CLI)
- **git** (subtree management)
- **Python 3.11+** (init, update, generate-settings, config cache)
- **shellcheck** (development/CI only)

## License

MIT
