---
name: setup
description: Review and customize toolkit.toml for the current project. Also handles initial bootstrap if toolkit not yet installed.
argument-hint: "[--stacks python,ios] [--name project-name]"
user-invocable: true
disable-model-invocation: true
---

# Setup Skill

Review and customize the claude-toolkit configuration for the current project. Can also handle initial bootstrap if the toolkit hasn't been installed yet.

**Note**: This skill is only available AFTER the toolkit is installed. For initial setup from scratch, run `bootstrap.sh` first (see below).

## Usage

```bash
/setup                           # Review and tune existing config
/setup --reconfigure             # Re-detect stack and regenerate config
```

## When to Use

- **After bootstrap**: To have Claude review and tune `toolkit.toml` for your project
- **After updating**: To adjust config for new toolkit features
- **Reconfigure**: When your project's tech stack changes

## Initial Bootstrap (Before This Skill Exists)

If the toolkit isn't installed yet, tell your user to run:

```bash
bash ~/projects/claude-toolkit/bootstrap.sh --name <project> --stacks <stacks>
```

Or manually:

```bash
git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git
git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
bash .claude/toolkit/toolkit.sh init --from-example
```

## Execution Flow

### Step 1: Check Current State

```bash
bash .claude/toolkit/toolkit.sh status
bash .claude/toolkit/toolkit.sh validate
```

### Step 2: Analyze Project

Scan the project to detect:

1. **Tech stacks**: From file presence:
   - `*.py` or `requirements.txt` or `pyproject.toml` → `python`
   - `*.swift` or `*.xcodeproj` → `ios`
   - `*.ts` or `*.tsx` or `tsconfig.json` → `typescript`
2. **Test command**: Scan Makefile, package.json, scripts/
3. **Lint command**: ruff, eslint, swiftlint presence
4. **Critical rules**: Read existing CLAUDE.md for rules that should be injected into subagents
5. **Available tools**: Scan Makefile for common targets

### Step 3: Customize toolkit.toml

Read `.claude/toolkit.toml` and improve it based on project analysis:

- Set correct test/lint commands in gates
- Add project-specific `critical_rules` in `[hooks.subagent-context]`
- Set `stack_info` description
- Add any project-specific `required_tools` or `optional_tools`
- Set correct `source_dirs` and `source_extensions` in `[hooks.compact]`

### Step 4: Create/Update settings-project.json

If the project needs custom permissions, MCP servers, or plugins:

- Project-specific Bash command allows
- Custom MCP servers
- Plugin enables

### Step 5: Regenerate and Validate

```bash
bash .claude/toolkit/toolkit.sh generate-settings
bash .claude/toolkit/toolkit.sh validate
```

### Step 6: Update CLAUDE.md

If `CLAUDE.md` doesn't mention the toolkit, add a section:

```markdown
## Claude Toolkit

This project uses [claude-toolkit](https://github.com/donygeorge/claude-toolkit).

- Config: `.claude/toolkit.toml`
- Status: `bash .claude/toolkit/toolkit.sh status`
- Validate: `bash .claude/toolkit/toolkit.sh validate`
- Update: `bash .claude/toolkit/toolkit.sh update`
```

### Step 7: Commit

Stage and commit all changes.

## Output

After completion, report:

- Changes made to toolkit.toml
- Changes made to settings-project.json
- Validation result
- Any items needing user attention
