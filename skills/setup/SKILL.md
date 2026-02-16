---
name: setup
description: Set up claude-toolkit in a new project. Runs bootstrap, reviews config, and customizes for the project.
argument-hint: "[--stacks python,ios] [--name project-name]"
user-invocable: true
disable-model-invocation: true
---

# Setup Skill

Set up claude-toolkit in the current project. Detects the tech stack, generates configuration, runs bootstrap, and customizes for the project.

## Usage

```bash
/setup                                    # Auto-detect everything
/setup --stacks python --name my-project  # Explicit
```

## Execution Flow

### Step 1: Detect Project

Analyze the current project to determine:

1. **Project name**: From `package.json`, `pyproject.toml`, directory name, or git remote
2. **Tech stacks**: From file presence:
   - `*.py` or `requirements.txt` or `pyproject.toml` → `python`
   - `*.swift` or `*.xcodeproj` → `ios`
   - `*.ts` or `*.tsx` or `tsconfig.json` → `typescript`
3. **Version file**: `VERSION`, `package.json`, `pyproject.toml`
4. **Test command**: `make test`, `npm test`, `pytest`, etc.
5. **Lint command**: `ruff`, `eslint`, `swiftlint`, etc.
6. **Required tools**: Scan Makefile, package.json, scripts/

Present findings to user and confirm before proceeding.

### Step 2: Check Prerequisites

```bash
# Must be in a git repo
git rev-parse --is-inside-work-tree

# Must not already have toolkit
ls .claude/toolkit/ 2>/dev/null && echo "Already set up!"

# Check tools
command -v jq
command -v python3
```

### Step 3: Run Bootstrap

If `bootstrap.sh` is available locally (e.g., at `~/projects/claude-toolkit/bootstrap.sh`), run it:

```bash
bash ~/projects/claude-toolkit/bootstrap.sh \
  --name <detected-name> \
  --stacks <detected-stacks> \
  --local ~/projects/claude-toolkit
```

If not available locally, use the git subtree approach:

```bash
git remote add claude-toolkit https://github.com/donygeorge/claude-toolkit.git
git subtree add --squash --prefix=.claude/toolkit claude-toolkit main
bash .claude/toolkit/toolkit.sh init --from-example
```

### Step 4: Customize toolkit.toml

After init, review and improve the generated `toolkit.toml`:

1. **Read the generated file**: `.claude/toolkit.toml`
2. **Customize based on project analysis**:
   - Set correct test commands in `[hooks.task-completed.gates]`
   - Set correct lint commands in `[hooks.post-edit-lint.linters]`
   - Add project-specific `critical_rules` in `[hooks.subagent-context]`
   - Set `stack_info` description
   - Add any project-specific `required_tools` or `optional_tools`
3. **Regenerate settings**: `bash .claude/toolkit/toolkit.sh generate-settings`

### Step 5: Create settings-project.json (if needed)

If the project needs custom permissions, MCP servers, or plugins beyond what the stacks provide, create `.claude/settings-project.json`.

Common additions:
- Project-specific Bash command allows
- Custom MCP servers
- Plugin enables
- Additional skill permissions

### Step 6: Create or Update CLAUDE.md

If `CLAUDE.md` doesn't exist, create a minimal one:

1. Project overview (what is this project?)
2. Quick reference (key commands, key files)
3. Critical rules (things that must never be violated)
4. Development workflow

If `CLAUDE.md` already exists, add a section about the toolkit:

```markdown
## Claude Toolkit

This project uses [claude-toolkit](https://github.com/donygeorge/claude-toolkit) for Claude Code hooks, agents, and skills.

- Config: `.claude/toolkit.toml`
- Status: `bash .claude/toolkit/toolkit.sh status`
- Validate: `bash .claude/toolkit/toolkit.sh validate`
- Update: `bash .claude/toolkit/toolkit.sh update`
```

### Step 7: Validate and Commit

```bash
# Validate everything works
bash .claude/toolkit/toolkit.sh validate

# Stage and commit
git add .claude/ .mcp.json CLAUDE.md
git commit -m "Add claude-toolkit"
```

## Output

After completion, report:

- Files created/modified
- Stacks detected and configured
- Hooks active (count)
- Agents available (count)
- Skills available (count)
- Any items needing user attention
- Next steps (customize further, push, etc.)
