# Claude Toolkit Project Context

> **Note to AI Assistants**: This is a standalone toolkit repo, NOT a web application. It provides reusable hooks, agents, skills, and rules for Claude Code projects. See `README.md` for full details.

## What is This?

A shareable, configurable collection of Claude Code hooks, agents, skills, and rules for safe, autonomous AI-assisted development. Pure bash + Python 3.11+. No web server, no app — just tools that integrate into `.claude/` directories via git subtree.

**Key Capabilities**:

- 16 configurable hooks (guards, quality gates, lifecycle, automation)
- 10 agent prompts (reviewer, qa, security, ux, pm, docs, architect, commit-check, plan, gemini)
- 15 skill templates (review, implement, plan, brainstorm, solve, fix, refine, verify, conventions, scope-resolver, toolkit-setup, toolkit-update, toolkit-doctor, toolkit-contribute, commit)
- Three-tier settings merge (base + stacks + project)
- Manifest tracking for managed vs customized files
- Config-driven via `toolkit.toml`

## Quick Reference

**Tech Stack**: Bash 4.0+, Python 3.11+, jq, git

**Key Commands**:

```bash
# Run tests
python3 -m pytest tests/ -v              # Python unit tests (314 tests)
bash tests/test_toolkit_cli.sh           # CLI integration tests
bash tests/test_manifest.sh              # Manifest integration tests

# Lint shell scripts
shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh

# CLI (when testing locally)
bash toolkit.sh init                      # Initialize toolkit in a project
bash toolkit.sh init --dry-run            # Show what init would do without mutating
bash toolkit.sh update                    # Update from remote via git subtree
bash toolkit.sh status                    # Show version, config, customizations
bash toolkit.sh validate                  # Health check (symlinks, settings, hooks)
bash toolkit.sh doctor                    # Comprehensive health check (tools, config, hooks)
bash toolkit.sh generate-settings         # Regenerate settings.json + .mcp.json
bash toolkit.sh customize <file>          # Take ownership of managed file
bash toolkit.sh explain [topic]            # Explain toolkit concepts
bash toolkit.sh help                      # Show usage
```

## Project Structure

```text
.
├── toolkit.sh                   # CLI entry point (thin dispatcher)
├── bootstrap.sh                 # Shell bootstrap for new projects
├── detect-project.py            # Auto-detect project stacks and commands
├── generate-settings.py         # Three-tier JSON merge (base + stacks + project)
├── generate-config-cache.py     # TOML to bash env cache
├── hooks/                       # Hook scripts (16 files)
│   ├── _config.sh               # Shared config sourced by all hooks
│   ├── guard-*.sh               # Safety guards (destructive ops, sensitive writes)
│   ├── auto-approve-safe.sh     # Auto-approve safe operations
│   ├── classify-error.sh        # Error classification
│   ├── post-edit-lint.sh        # Async lint after edits
│   ├── task-completed-gate.sh   # Quality gates before task completion
│   ├── setup.sh                 # Environment validation
│   ├── session-*.sh             # Lifecycle hooks (start, end, compact)
│   ├── subagent-context-inject.sh # Subagent context injection
│   ├── verify-completion.sh     # Uncommitted change warnings
│   ├── notify.sh                # Platform-aware notifications
│   └── smart-context.py         # Keyword-based context loading
├── agents/                      # Generic agent prompts (10 files)
│   ├── reviewer.md              # Adversarial code review
│   ├── qa.md                    # Test execution and validation
│   ├── security.md              # Secrets, SAST, dependency scan
│   ├── ux.md                    # Accessibility (WCAG 2.1 AA)
│   ├── pm.md                    # Product perspective
│   ├── docs.md                  # Documentation accuracy
│   ├── architect.md             # Deep architecture analysis
│   ├── commit-check.md          # Lightweight post-commit check
│   ├── plan.md                  # Feature planning agent
│   └── gemini.md                # Gemini CLI relay for second opinions
├── skills/                      # Skill templates (15 directories, each has SKILL.md)
│   ├── review-suite/            # Multi-agent code review
│   ├── implement/               # Autonomous plan execution
│   ├── plan/                    # Feature planning
│   ├── brainstorm/              # Idea exploration with agent teams
│   ├── solve/                   # GitHub issue workflow
│   ├── fix/                     # Standalone bug fix
│   ├── refine/                  # Iterative convergence loop
│   ├── conventions/             # View coding conventions
│   ├── scope-resolver/          # Feature scope resolver
│   ├── toolkit-setup/           # Project onboarding and configuration
│   ├── toolkit-update/          # Toolkit version updates
│   ├── toolkit-doctor/          # Deep health evaluation and optimization
│   ├── toolkit-contribute/      # Upstream generic improvements
│   ├── verify/                  # Post-implementation verification (deep + quick modes)
│   └── commit/                  # Auto-commit session changes
├── rules/                       # Generic rules (symlinked to projects)
│   └── git-protocol.md          # Git staging and commit rules
├── templates/                   # Configuration templates
│   ├── settings-base.json       # Base settings for all projects
│   ├── stacks/*.json            # Stack overlays (python, ios, typescript)
│   ├── rules/*.md.template      # Stack-specific rule templates (7 files)
│   ├── toolkit.toml.example     # Example config
│   └── CLAUDE.md.template       # Project instructions template
├── smart-context/               # Keyword context framework
│   ├── framework.py             # Context loading logic
│   └── README.md                # Framework documentation
├── lib/                         # Shared libraries
│   ├── manifest.sh              # Manifest functions (sourced by toolkit.sh)
│   ├── hook-utils.sh            # Shared hook utilities (opt-in by hooks)
│   ├── cmd-init.sh              # Init subcommand + 9 helper functions
│   ├── cmd-update.sh            # Update subcommand + _refresh_symlinks
│   ├── cmd-customize.sh         # Customize subcommand
│   ├── cmd-status.sh            # Status subcommand
│   ├── cmd-validate.sh          # Validate subcommand
│   ├── cmd-doctor.sh            # Doctor subcommand (comprehensive health check)
│   ├── cmd-generate-settings.sh # Generate-settings subcommand
│   ├── cmd-explain.sh           # Explain subcommand (topic-based help)
│   └── cmd-help.sh              # Help subcommand
├── docs/                        # Documentation
│   ├── reference.md             # Full configuration reference
│   ├── concepts.md              # Mental model explainer (2-minute read)
│   └── plans/                   # Implementation plans
├── mcp/                         # MCP templates
│   └── base.mcp.json            # Base MCP server config
└── tests/                       # Test suite (314 pytest + bash integration)
    ├── test_generate_settings.py
    ├── test_generate_config_cache.py
    ├── test_detect_project.py
    ├── test_hooks.sh
    ├── test_toolkit_cli.sh
    ├── test_manifest.sh
    └── fixtures/                # Test fixtures (sample configs, etc.)
```

## Critical Rules

These rules apply to ALL work in this toolkit.

1. **Generic Agents & Skills**: Agent prompts and skills MUST stay generic. NO project-specific tool references, file paths, or conventions. These files are reused across projects.
2. **Configurable Hooks**: Hooks MUST be configurable via `toolkit.toml`. Hardcoded project values are bugs. Use `_config.sh` variables.
3. **Shellcheck Clean**: All `.sh` files MUST pass `shellcheck -x -S warning` with no errors.
4. **Python 3.11+**: Use `tomllib` (stdlib) for TOML parsing. NO external dependencies except pytest for tests.
5. **Deterministic Settings**: Settings merge MUST be deterministic (sorted keys, 2-space indent, stable output).
6. **Config Cache Sourcing**: `_config.sh` is sourced by every hook. Changes here affect all hooks.
7. **Manifest Integrity**: Managed files must match toolkit sources. Customized files are preserved on update.
8. **Test Before Commit**: Run full test suite before committing. No failing tests allowed.

## Key Files

### Core CLI & Config

- `toolkit.sh` — Thin CLI dispatcher: path resolution, helpers, sources `lib/cmd-*.sh` modules
- `lib/cmd-*.sh` — Modular subcommand files (init, update, customize, status, validate, doctor, generate-settings, explain, help)
- `generate-settings.py` — Three-tier JSON merge (base + stack overlays + project overrides)
- `generate-config-cache.py` — TOML to bash env cache (used by `_config.sh`)
- `lib/manifest.sh` — Manifest tracking functions (read, update, check customizations)
- `lib/hook-utils.sh` — Shared hook utilities (input parsing, deny/approve, audit logging)

### Configuration System

- `hooks/_config.sh` — Shared config sourced by all hooks. Reads `toolkit-cache.env`, falls back to defaults. Changes here affect ALL hooks.
- `.claude/toolkit.toml` — User config (lives in consuming project, not in toolkit repo)
- `.claude/toolkit-cache.env` — Generated bash env vars (cached from TOML for fast hook access)
- `.claude/manifest.json` — Tracks managed vs customized files

### Settings Merge

1. **Base**: `templates/settings-base.json` — Default hooks, deny list, env vars
2. **Stack overlays**: `templates/stacks/{python,ios,typescript}.json` — Stack-specific additions
3. **Project overrides**: `.claude/settings-project.json` — User customizations (consuming project)

Result written to `.claude/settings.json` and `.mcp.json`.

## Development Workflow

### Before ANY Task

1. Read the README for full context
2. Identify ALL questions upfront (ask in ONE batch)
3. Check existing patterns in hooks/agents/skills

### During Implementation

1. Run `shellcheck` after editing shell scripts
2. Run `python3 -m pytest tests/ -v` after editing Python
3. Test CLI commands manually in a scratch project
4. One logical change at a time

### Before Marking Complete

1. **Self-review checklist**:
   - [ ] Full test suite passes (`pytest` + bash integration tests)
   - [ ] `shellcheck -x -S warning` passes on all `.sh` files
   - [ ] Agent prompts and skills are GENERIC (no project-specific content)
   - [ ] Hooks use `_config.sh` variables (no hardcoded paths/values)
   - [ ] Settings merge is deterministic (test with `test_generate_settings.py`)
   - [ ] CHANGELOG.md updated

2. Re-read modified files

## Testing

### Python Tests

```bash
# Run all Python tests (314 tests)
python3 -m pytest tests/ -v

# Run specific test file
python3 -m pytest tests/test_generate_settings.py -v

# Run with coverage
python3 -m pytest tests/ -v --cov=. --cov-report=term-missing
```

Tests use fixtures in `tests/fixtures/`:

- `sample-toolkit.toml` — Example config
- `adversarial-toolkit.toml` — Edge cases
- `settings-*.json` — Base, stack, and project settings

### Bash Tests

```bash
# CLI integration tests
bash tests/test_toolkit_cli.sh

# Manifest integration tests
bash tests/test_manifest.sh
```

These tests create temporary projects, run CLI commands, and validate output.

### Shellcheck

```bash
# Lint all shell scripts
shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh

# Lint specific file
shellcheck -x -S warning hooks/guard-destructive.sh
```

## Common Patterns

### Hook Structure

All hooks follow this pattern:

```bash
#!/bin/bash
# Hook description
source "$(dirname "$0")/_config.sh"

# Hook logic using TOOLKIT_* variables from config
```

### Agent Prompts

Agent prompts MUST be generic:

```markdown
# Good (generic)
- Run project's test suite
- Check for common security issues

# Bad (project-specific)
- Run `make test-changed`
- Check OPENAI_API_KEY in .env
```

### Skills

Skills use generic placeholders:

```markdown
# Good (generic)
Run: <project-test-command>

# Bad (project-specific)
Run: make test-changed
```

## Git Protocol

- Stage specific files: `git add <file>`, not `git add .`
- Commit message format: description + Co-Authored-By line
- Use `git commit -F /tmp/msg.txt` for safety (avoids guard hook false positives)
- Update CHANGELOG.md for user-facing changes
- Never force push or hard reset without request

## Common Issues

| Issue | Solution |
| ------- | ---------- |
| Shellcheck errors | Run `shellcheck -x -S warning <file>` and fix warnings |
| Python tests fail | Check fixtures in `tests/fixtures/`, verify tomllib import |
| Settings merge wrong | Check deterministic sorting in `generate-settings.py` |
| Hook not executing | Verify hook is executable (`chmod +x`), check `_config.sh` sourcing |
| Manifest out of sync | Run `bash toolkit.sh validate` to check health |
| Config cache stale | Run `python3 generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env` |

## What NOT to Do

- Do NOT add project-specific content to agent prompts or skills
- Do NOT hardcode paths or values in hooks (use `_config.sh` variables)
- Do NOT commit failing tests
- Do NOT skip shellcheck on `.sh` files
- Do NOT add external Python dependencies (except pytest for tests)
- Do NOT make settings merge non-deterministic
- Do NOT modify consuming project files from toolkit code

## Environment Variables

Hooks and scripts read from:

- `CLAUDE_PROJECT_DIR` — Project root (set by Claude Code)
- `TOOLKIT_DIR` — Toolkit installation directory (set by `_config.sh`)
- `TOOLKIT_*` variables — Cached config from `toolkit-cache.env`

## Documentation

| File | Purpose |
| ------ | --------- |
| `README.md` | Quick start guide and project overview |
| `docs/reference.md` | Full configuration reference (CLI, hooks, agents, skills, stacks) |
| `docs/concepts.md` | Mental model explainer (2-minute read) |
| `CONTRIBUTING.md` | Development guide and contribution guidelines |
| `CHANGELOG.md` | Version history and release notes |
| `CLAUDE.md` (this file) | AI assistant context and development guide |
| `smart-context/README.md` | Smart-context framework documentation |

## Version Management

- Version stored in `VERSION` file (semver format)
- Git tags for releases: `v1.0.0`, `v1.1.0`, etc.
- CHANGELOG.md updated for each release

---

**Remember**: This is a toolkit repo, not a project repo. All content must be generic and reusable across projects. When in doubt, add configuration to `toolkit.toml` instead of hardcoding.
