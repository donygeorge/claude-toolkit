# Configuration Reference

Complete reference for all claude-toolkit configuration options, CLI commands, hooks, agents, skills, stacks, and rules.

## CLI Commands

The toolkit CLI lives at `.claude/toolkit/toolkit.sh`.

### `init [--force] [--from-example] [--dry-run]`

Initialize the toolkit in your project. Symlinks agents and generic rules, copies skills and rule templates, generates settings.

| Flag | Description |
|------|-------------|
| `--from-example` | Create `toolkit.toml` from the bundled example |
| `--force` | Overwrite existing files (re-symlink agents, re-copy skills) |
| `--dry-run` | Show what would be created without mutating any files |

### `update [version] [--latest] [--force]`

Update the toolkit from the remote repository via git subtree pull. Managed files are refreshed; customized files are preserved.

| Flag | Description |
|------|-------------|
| `version` | Specific version tag to pull (e.g., `v1.2.0`) |
| `--latest` | Pull the latest `main` branch instead of a tagged release |
| `--force` | Skip the uncommitted-changes check |

After updating, the CLI runs `shellcheck` on pulled code and shows a diff summary.

### `customize <path>`

Convert a managed file to a customized one. The file is copied locally and marked in the manifest so future `update` commands skip it.

```bash
toolkit.sh customize agents/reviewer.md
toolkit.sh customize skills/implement/SKILL.md
```

### `status`

Show toolkit version, project name, stacks, config cache staleness, and list customized or modified files.

### `validate`

Check toolkit health: verify symlinks resolve, `settings.json` is valid, hook scripts exist and are executable, config is not stale.

### `doctor`

Comprehensive health check beyond `validate`. Checks:

- Required tools (bash, jq, python3, git)
- Bash version (4.0+ recommended, 3.2+ minimum)
- Python version (3.11+ required for `tomllib`)
- Toolkit directory and VERSION file
- `toolkit.toml` existence
- Config cache freshness (compares mtimes)
- `settings.json` validity and parity with what `generate-settings` would produce
- Symlink health (broken symlinks in agents/ and rules/)
- Manifest integrity (valid JSON)
- Hook executability
- Hook health (runs sample inputs through guard hooks)
- Optional tools (shellcheck, rsync)

### `generate-settings`

Regenerate `settings.json` and `.mcp.json` from the three-tier merge of base + stacks + project settings. Also regenerates `toolkit-cache.env`.

### `explain [topic]`

Show plain-language explanations of toolkit concepts. Topics: `overview`, `hooks`, `agents`, `skills`, `rules`, `config`, `stacks`.

### `help`

Show usage information for all subcommands.

### Global Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Available for `init` and `generate-settings`. Can be placed before the subcommand. |

---

## toolkit.toml Reference

All configuration lives in `.claude/toolkit.toml`. Below is every section and key.

### `[toolkit]`

Toolkit-level metadata.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `remote_url` | string | — | Git remote URL for the toolkit repo (used by `update`) |

### `[project]`

Project identification.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | — | Display name used in session banners and notifications |
| `version_file` | string | `"VERSION"` | Path to file containing the current version |
| `stacks` | array | `[]` | Technology stacks: `"python"`, `"ios"`, `"typescript"` |

### `[hooks.setup]`

Environment validation (runs once per session start).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `python_min_version` | string | `"3.11"` | Minimum Python version (major.minor) |
| `required_tools` | array | `[]` | Tools that must be installed (setup warns if missing) |
| `optional_tools` | array | `[]` | Tools that are nice to have (info-level if missing) |
| `security_tools` | array | `[]` | Security scanning tools (optional) |

### `[hooks.post-edit-lint.linters.<ext>]`

Per-extension lint/format commands. `<ext>` is the file extension without dot (e.g., `py`, `ts`, `swift`).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `cmd` | string | — | Lint check command (receives file path as argument) |
| `fmt` | string | — | Format command (receives file path as argument) |
| `fallback` | string | — | Fallback command name if `cmd` is not found |

Example:

```toml
[hooks.post-edit-lint.linters.py]
cmd = ".venv/bin/ruff check"
fmt = ".venv/bin/ruff format"
fallback = "ruff"
```

### `[hooks.task-completed.gates.<name>]`

Quality gates checked before task completion. Each gate runs a command; if it exits non-zero, the task is blocked.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `glob` | string | — | File glob pattern that triggers this gate |
| `cmd` | string | — | Command to run (exit 0 = pass) |
| `timeout` | integer | `90` | Max seconds before the gate is killed |

Example:

```toml
[hooks.task-completed.gates.lint]
glob = "*.py"
cmd = ".venv/bin/ruff check --quiet"

[hooks.task-completed.gates.tests]
glob = "*.py"
cmd = "make test-changed"
timeout = 90
```

### `[hooks.auto-approve]`

Paths and commands auto-approved without prompting Claude Code's permission dialog.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `write_paths` | array | `[]` | Glob patterns for Write/Edit paths to auto-approve |
| `bash_commands` | array | `[]` | Bash command prefixes to auto-approve |

### `[hooks.subagent-context]`

Context injected into subagent sessions (spawned by Claude Code for multi-agent work).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `critical_rules` | array | `[]` | Rules injected into every subagent |
| `available_tools` | array | `[]` | Tools/capabilities available in this project |
| `stack_info` | string | `""` | Short tech stack description for subagents |

### `[hooks.compact]`

Pre-compact state preservation. Controls what gets saved before Claude Code compacts context.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `source_dirs` | array | `["app", "src"]` | Directories scanned for recently modified files |
| `source_extensions` | array | `["*.py"]` | File extensions to include |
| `state_dirs` | array | `["artifacts"]` | Directories checked for active orchestration state |

### `[hooks.session-end]`

Session cleanup thresholds.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `agent_memory_max_lines` | integer | `250` | Max lines in agent memory before truncation |
| `hook_log_max_lines` | integer | `500` | Max lines in hook log before pruning |

### `[notifications]`

Platform-aware notification settings.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `app_name` | string | `"Claude Code"` | Application name shown in notifications |
| `permission_sound` | string | `"Blow"` | macOS sound for permission prompts (`"none"` for silent) |

---

## Hooks Reference

All 16 hooks, grouped by purpose.

### Safety Guards

| Hook | Event | Description |
|------|-------|-------------|
| `guard-destructive.sh` | PreToolUse | Blocks destructive git operations (`push`, `reset --hard`), dangerous `rm` patterns, SQL `DROP`/`TRUNCATE`, `eval`, and pipe-to-shell (`\| bash`) |
| `guard-sensitive-writes.sh` | PreToolUse | Blocks writes to `.env`, credentials, API keys, `.git/` internals, and toolkit config files |

### Automation

| Hook | Event | Description |
|------|-------|-------------|
| `auto-approve-safe.sh` | PermissionRequest | Auto-approves read-only tools (Read, Glob, Grep), safe bash commands (ls, cat, grep, etc.), and configured write paths |
| `post-edit-lint.sh` | PostToolUse | Runs linter/formatter asynchronously after file edits, using per-extension config from `toolkit.toml` |

### Quality Gates

| Hook | Event | Description |
|------|-------|-------------|
| `task-completed-gate.sh` | TaskCompleted | Runs configured quality gates (lint, tests) before allowing task completion |
| `classify-error.sh` | PostToolUseFailure | Classifies tool errors and suggests recovery strategies |
| `verify-completion.sh` | Stop | Advisory warning about uncommitted changes when session ends |

### Session Lifecycle

| Hook | Event | Description |
|------|-------|-------------|
| `setup.sh` | SessionStart (once) | Validates development environment (Python version, required tools) |
| `session-start.sh` | SessionStart | Loads project state and session context |
| `session-end-cleanup.sh` | SessionEnd | Cleans temp files, truncates oversized logs and agent memory |
| `pre-compact.sh` | PreCompact | Saves working state before context compaction |
| `post-compact-reinject.sh` | SessionStart (compact) | Re-injects context after compaction |

### Subagent Management

| Hook | Event | Description |
|------|-------|-------------|
| `subagent-context-inject.sh` | SubagentStart | Injects project context, critical rules, and stack info into subagent sessions |
| `subagent-quality-gate.sh` | SubagentStop | Validates subagent output quality |

### Context & Notifications

| Hook | Event | Description |
|------|-------|-------------|
| `smart-context.py` | UserPromptSubmit | Keyword-based domain context loading (Python script) |
| `notify.sh` | Notification | Platform-aware notifications for permission prompts and idle alerts (macOS `osascript`, Linux `notify-send`, CI silent) |

### Helpers (sourced, not standalone)

| File | Purpose |
|------|---------|
| `_config.sh` | Shared configuration sourced by all hooks. Reads `toolkit-cache.env`, sets `TOOLKIT_*` variables |

---

## Agents Reference

Generic agent prompts in `.claude/agents/`. These are symlinked from the toolkit.

| Agent | File | Purpose |
|-------|------|---------|
| Reviewer | `reviewer.md` | Adversarial code review: finds bugs, missing tests, security issues |
| QA | `qa.md` | Test execution, validation, coverage analysis |
| Security | `security.md` | Secrets scanning, SAST, dependency vulnerability checks |
| UX | `ux.md` | Accessibility (WCAG 2.1 AA), VoiceOver, dark mode |
| PM | `pm.md` | Product perspective, user workflows, edge cases |
| Docs | `docs.md` | Documentation accuracy, code-doc sync |
| Architect | `architect.md` | Deep architecture analysis, patterns, resiliency |
| Commit Check | `commit-check.md` | Lightweight post-commit sanity check |
| Plan | `plan.md` | Feature planning with research and scope analysis |

---

## Skills Reference

Skill templates in `.claude/skills/`. These are copied (not symlinked) so they can be customized.

| Skill | Directory | Purpose |
|-------|-----------|---------|
| Setup | `setup-toolkit/` | Bootstrap claude-toolkit in a new project (9-phase orchestrator) |
| Review Suite | `review-suite/` | Multi-agent code review orchestration |
| Implement | `implement/` | Autonomous plan execution with milestone agents |
| Plan | `plan/` | Feature planning with research and review |
| Solve | `solve/` | GitHub issue workflow (fetch, reproduce, fix, commit) |
| Fix | `fix/` | Standalone bug fix without GitHub issue |
| Refine | `refine/` | Iterative evaluate-fix-validate convergence loop |
| Conventions | `conventions/` | View coding conventions for a domain |
| Scope Resolver | `scope-resolver/` | Resolve feature scopes for review targeting |
| Gemini | `gemini/` | Second opinion from Google's model |

---

## Stacks Reference

Stack overlays add technology-specific settings. Configure via `project.stacks` in `toolkit.toml`.

| Stack | File | Adds |
|-------|------|------|
| `python` | `templates/stacks/python.json` | Python-specific hook matchers, deny patterns for virtualenvs |
| `ios` | `templates/stacks/ios.json` | iOS/Swift-specific hook matchers |
| `typescript` | `templates/stacks/typescript.json` | TypeScript/Node-specific hook matchers, npm patterns |

### Rule Templates by Stack

Applied automatically during `init` based on your stacks configuration.

| Template | Stack | Provides |
|----------|-------|----------|
| `python.md` | python | Python 3.11+ conventions, ruff, type hints |
| `swift.md` | ios | SwiftUI, HealthKit/HomeKit patterns |
| `typescript.md` | typescript | TypeScript/Node conventions |
| `testing-pytest.md` | python | pytest patterns and fixtures |
| `testing-jest.md` | typescript | Jest testing patterns |
| `api-routes-fastapi.md` | python | FastAPI route conventions |
| `database-sqlite.md` | python | SQLite WAL mode patterns |

Plus `git-protocol.md` (always included regardless of stack).

---

## Three-Tier Settings Merge

Settings are generated by merging three layers, in order:

1. **Base** (`templates/settings-base.json`) -- Default hooks, deny list, environment variables common to all projects
2. **Stack overlays** (`templates/stacks/*.json`) -- Additions specific to your configured stacks
3. **Project overrides** (`.claude/settings-project.json`) -- Your project-specific customizations

The merge is deterministic (sorted keys, 2-space indent). Arrays are deduplicated. The result is written to `.claude/settings.json` and `.mcp.json`.

Regenerate after changing any layer:

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

---

## Manifest System

The manifest (`toolkit-manifest.json`) tracks the state of every managed file:

- **managed**: File is controlled by the toolkit. Updated automatically on `toolkit.sh update`.
- **customized**: File has been taken over by the project via `toolkit.sh customize`. Skipped on update.

The manifest also records SHA-256 hashes for drift detection and timestamps for customization events.

---

## File Layout

After initialization, your project's `.claude/` directory will contain:

```
.claude/
  toolkit.toml              # Your configuration
  toolkit-cache.env         # Generated bash env vars (cached from TOML)
  toolkit-manifest.json     # Managed vs customized file tracking
  settings.json             # Generated Claude Code settings
  settings-project.json     # (optional) Project-specific overrides
  agents/                   # Symlinked agent prompts
  skills/                   # Copied skill templates
  rules/                    # Symlinked + copied rules
  agent-memory/             # Per-agent memory directories
  toolkit/                  # The toolkit itself (git subtree)
```
