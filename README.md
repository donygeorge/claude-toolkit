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

New to the toolkit? Read [Toolkit Concepts](docs/concepts.md) for a 2-minute overview of how everything fits together.

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
2. Read and follow .claude/skills/setup-toolkit/SKILL.md (the /setup-toolkit skill)
   to detect stacks, validate commands, generate toolkit.toml, create CLAUDE.md, and commit.
```

If you use a fork, replace the GitHub URL above. See [BOOTSTRAP_PROMPT.md](BOOTSTRAP_PROMPT.md) for the standalone version.

### Shell Bootstrap (Alternative)

If you prefer a shell script, run from your project root:

```bash
bash /path/to/claude-toolkit/bootstrap.sh --name my-project --stacks python
```

Then open Claude Code and run `/setup-toolkit` to auto-detect and validate your configuration.

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

#### 3. Run /setup-toolkit in Claude Code

Open Claude Code in your project and run `/setup-toolkit`. Claude will detect your stacks, validate commands, and generate the full configuration.

#### 4. Commit

```bash
git add .claude/ .mcp.json CLAUDE.md
git commit -m "Add claude-toolkit"
```

</details>

## CLI Commands

The toolkit ships with a CLI at `.claude/toolkit/toolkit.sh`:

| Command | Description |
| --------- | ------------- |
| `init [--force] [--from-example]` | Initialize toolkit in project |
| `update [version] [--latest] [--force]` | Update toolkit from remote |
| `customize <path>` | Convert managed file to customized |
| `status` | Show toolkit status |
| `validate` | Check toolkit health |
| `doctor` | Comprehensive health check |
| `generate-settings` | Regenerate settings.json and .mcp.json |
| `explain [topic]` | Explain toolkit concepts |
| `help` | Show usage |

Global flags: `--dry-run` (for `init` and `generate-settings`).

See [Configuration Reference](docs/reference.md) for full CLI details, all `toolkit.toml` options, hooks, agents, skills, and stacks.

## Customization

1. **Configure** -- Edit `toolkit.toml` to change behavior (no code changes needed)
2. **Override** -- Create `.claude/settings-project.json` for project-specific settings
3. **Extend** -- Use `toolkit.sh customize <file>` to take ownership of any managed file

## Requirements

- **bash** 4.0+ (hook scripts)
- **jq** (JSON processing in hooks and CLI)
- **git** (subtree management)
- **Python 3.11+** (settings generation, config cache)
- **shellcheck** (development/CI only)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and guidelines.

## Documentation

| Document | Description |
| ---------- | ------------- |
| [Toolkit Concepts](docs/concepts.md) | 2-minute mental model overview |
| [Configuration Reference](docs/reference.md) | Full reference for all options, hooks, agents, skills |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development guide and contribution guidelines |
| [BOOTSTRAP_PROMPT.md](BOOTSTRAP_PROMPT.md) | Standalone setup prompt for Claude Code |
| [CHANGELOG.md](CHANGELOG.md) | Version history and release notes |

## License

MIT
