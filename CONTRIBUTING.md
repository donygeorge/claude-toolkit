# Contributing to claude-toolkit

Thank you for your interest in contributing. This guide covers how to add new components, testing requirements, and the project's design philosophy.

## Development Setup

```bash
git clone <repo-url>
cd claude-toolkit
python3 -m venv .venv
source .venv/bin/activate
pip install pytest
```

Requirements: bash 4.0+, jq, Python 3.11+, git, shellcheck.

## Running Tests

All tests must pass before submitting changes.

```bash
# Python unit tests
python3 -m pytest tests/ -v

# Shell script linting
shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh

# Hook integration tests
bash tests/test_hooks.sh

# CLI integration tests
bash tests/test_toolkit_cli.sh

# Manifest integration tests
bash tests/test_manifest.sh
```

## Design Philosophy: Generic by Default

Everything in this toolkit is designed to work across any project. This is the single most important rule:

- **Agent prompts** must contain no project-specific tool references, file paths, or conventions
- **Skills** must use generic placeholders -- project-specific content is documented for customization
- **Hooks** must read config from `_config.sh` -- no hardcoded project values
- **Rules** in `rules/` are generic; stack-specific rules live in `templates/rules/` as templates

If something varies between projects, it belongs in `toolkit.toml` configuration, not hardcoded in scripts.

## Adding a New Hook

Hooks are shell scripts in `hooks/` that Claude Code runs at lifecycle events.

### Steps

1. Create `hooks/my-hook.sh` following this structure:

   ```bash
   #!/usr/bin/env bash
   # my-hook.sh -- Brief description
   #
   # Event: PreToolUse | PostToolUse | SessionStart | etc.
   #
   # Intentionally omits set -e and set -o pipefail so the hook degrades
   # gracefully (exit 0) on unexpected errors rather than blocking the user.
   set -u

   source "$(dirname "$0")/_config.sh"
   source "$(dirname "$0")/../lib/hook-utils.sh"

   # Hook logic here
   ```

2. Make it executable: `chmod +x hooks/my-hook.sh`

3. Add configuration variables to `hooks/_config.sh` if needed (with sensible defaults via `${VAR:-default}`)

4. Add the hook to `templates/settings-base.json` (or the appropriate stack overlay) so it gets included in generated settings

5. Add tests in `tests/test_hooks.sh` covering:
   - Normal operation (expected allow/deny behavior)
   - Edge cases (empty input, missing jq, malformed JSON)
   - Config-driven behavior (respects `TOOLKIT_*` variables)

6. Run `shellcheck -x -S warning hooks/my-hook.sh`

7. Update `docs/reference.md` with the new hook

### Hook Conventions

- Use `set -u` but NOT `set -e` or `set -o pipefail` (hooks must degrade gracefully)
- Read stdin for JSON input from Claude Code
- Use `hook_read_input`, `hook_deny`, `hook_approve` from `lib/hook-utils.sh`
- Log to stderr only (stdout is reserved for structured JSON responses)
- Use `hook_warn`, `hook_error`, `hook_info` for consistent message formatting
- All config values must come from `_config.sh` variables with `${VAR:-default}` fallbacks

## Adding a New Agent

Agents are markdown prompt files in `agents/` that define specialized AI personas.

### Steps

1. Create `agents/my-agent.md` with the agent prompt

2. Keep it generic -- no project-specific tools, paths, or conventions:

   ```markdown
   # Good (generic)
   - Run the project's test suite
   - Check for common security issues

   # Bad (project-specific)
   - Run `make test-changed`
   - Check OPENAI_API_KEY in .env
   ```

3. Add the agent to the `_AGENTS` list in `lib/cmd-init.sh` so it gets symlinked during `init`

4. Create an agent-memory directory entry if appropriate (in `_init_agent_memory` in `lib/cmd-init.sh`)

5. Update `docs/reference.md` with the new agent

## Adding a New Skill

Skills are workflow templates in `skills/<name>/` triggered by slash commands in Claude Code.

### Steps

1. Create `skills/my-skill/SKILL.md` with the workflow instructions

2. Use generic placeholders for project-specific values:

   ```markdown
   # Good (generic)
   Run: <project-test-command>

   # Bad (project-specific)
   Run: make test-changed
   ```

3. Add the skill directory name to the `_SKILLS` list in `lib/cmd-init.sh`

4. Skills are copied (not symlinked) during `init`, so users can customize them

5. Update `docs/reference.md` with the new skill

## Adding a New Stack

Stacks represent technology profiles (e.g., `python`, `ios`, `typescript`). The stack system is self-describing -- adding a new stack requires only dropping a JSON file.

### Stack File Format

Each stack JSON file in `templates/stacks/` has this structure:

```json
{
  "_meta": {
    "name": "my-stack",
    "description": "Short description of the stack and its tools",
    "required_tools": ["tool1", "tool2"]
  },
  "permissions": {
    "allow": [
      "Bash(tool1:*)",
      "Bash(tool2:*)"
    ]
  }
}
```

The `_meta` key is **required** for documentation but is **stripped during merge** -- it never appears in the generated `settings.json`. Fields:

- `name`: Human-readable stack name (should match the filename without `.json`)
- `description`: One-line description shown by `toolkit.sh status`
- `required_tools`: List of CLI tools the stack expects to be installed

### Steps

1. Create a settings overlay at `templates/stacks/my-stack.json` following the format above. The `permissions` and `hooks` sections are merged with the base settings when the stack is active.

2. Optionally create rule templates at `templates/rules/my-stack.md.template`:

   These are copied to `.claude/rules/` during `init` when the stack is configured.

3. No registration needed in `generate-settings.py` -- the three-tier merge handles it automatically. The `_meta` key is stripped before merging.

4. Add tests in `tests/test_generate_settings.py` to verify the merge produces correct output with the new stack.

5. Update `docs/reference.md` with the new stack and any rule templates it provides.

## Custom Hooks

Projects can add custom hooks alongside toolkit hooks by placing scripts in `.claude/hooks-custom/`. This directory is:

- **Not managed by the toolkit** -- files here are never overwritten by `toolkit.sh update`
- **Sourced by `_config.sh`** -- the `TOOLKIT_CUSTOM_HOOKS_DIR` variable points to this directory
- **Referenced in project settings** -- add custom hook entries in your `.claude/settings-project.json`

Example project settings overlay (`.claude/settings-project.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks-custom/my-guard.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

Custom hook scripts should follow the same conventions as toolkit hooks (source `_config.sh`, use `hook-utils.sh`, pass `shellcheck`).

## Testing Requirements

### Shell Scripts

- All `.sh` files must pass `shellcheck -x -S warning` with zero errors
- New hooks need integration tests in `tests/test_hooks.sh`
- CLI changes need tests in `tests/test_toolkit_cli.sh`

### Python

- Use `tomllib` (stdlib) -- no external dependencies except `pytest` for tests
- `generate-settings.py` output must be deterministic (sorted keys, 2-space indent)
- Test with `python3 -m pytest tests/ -v`
- Test fixtures live in `tests/fixtures/`

### What to Test

- Happy path (normal operation)
- Edge cases (empty input, missing tools, malformed data)
- Config-driven behavior (respects `toolkit.toml` settings)
- Backward compatibility (existing configs still work)

## Code Style

- Shell: 2-space indent, `#!/usr/bin/env bash` shebang, `shellcheck` clean
- Python: 4-space indent, Python 3.11+, no external dependencies
- Markdown: no trailing whitespace (except in code blocks)
- See `.editorconfig` for detailed formatting rules

## Commit Guidelines

- Stage specific files (`git add <file>`), not `git add .`
- Write clear commit messages describing the "why"
- Update `CHANGELOG.md` for user-facing changes
- Use `git commit -F <file>` if your message might trigger guard hooks

## Pull Request Process

1. Fork or branch from `main`
2. Make your changes
3. Run the full test suite (all five test commands above)
4. Update documentation (`docs/reference.md`, `CHANGELOG.md`)
5. Submit a pull request with a clear description

## Contributing from a Consuming Project

If you are using claude-toolkit in a project and have made improvements to hooks, agents, skills, or rules that could benefit all users, you can contribute those changes back upstream.

### Primary Workflow: `/setup-toolkit --contribute`

The easiest way to contribute is through the `/setup-toolkit --contribute` skill. It provides an LLM-guided workflow that:

1. Identifies customized and modified files in your project's toolkit installation
2. Diffs each change against the toolkit source and assesses generalizability
3. Lets you select which changes to propose
4. Applies a 10-point generalizability gate to each change (see below)
5. Runs the full toolkit test suite to validate correctness
6. Generates a patch and PR description for submission

Run it in your project:

```text
/setup-toolkit --contribute
```

### Manual Workflow

If you prefer to contribute manually (or do not have the skill available):

1. **Identify changes**: Run `toolkit.sh status` to see customized and modified files. Diff each one against the toolkit source in `.claude/toolkit/` to understand what changed.

2. **Verify generalizability**: Review each change against the 10-point checklist below. Changes that reference project-specific paths, tools, or conventions will not be accepted.

3. **Clone the toolkit repo**: Fork or clone the toolkit repository separately.

4. **Apply changes**: Copy your improvements into the cloned toolkit repo, adapting as needed to remain generic.

5. **Run the full test suite**:

   ```bash
   shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh
   python3 -m pytest tests/ -v
   bash tests/test_toolkit_cli.sh
   bash tests/test_manifest.sh
   bash tests/test_hooks.sh
   ```

6. **Open a PR**: Submit a pull request with a clear description of the changes, why they are useful across projects, and how they were tested.

### The Generalizability Requirement

Contributions from consuming projects must meet a very high bar for generalizability. Every change is evaluated against a 10-point checklist:

**Hard requirements** (all must pass):

- **No project paths** -- no references to project-specific directories or file paths
- **No project tool references** -- no references to project-specific tools or binaries
- **No project conventions** -- no project-specific coding conventions or patterns
- **No project defaults** -- no project-specific default values baked in
- **Config-driven variability** -- anything that varies between projects must be configurable via `toolkit.toml`
- **Agent/skill genericness** -- agent prompts and skills must use generic language and placeholders
- **Hook uses `_config.sh`** -- hooks must read all configuration from `_config.sh` variables

**Quality requirements** (all must pass):

- **Backward compatible** -- existing configurations and workflows must continue to work
- **Follows existing patterns** -- the change matches the style and conventions of the surrounding code
- **Clear purpose** -- the change has a well-defined, broadly useful purpose

Changes that fail any hard requirement will be rejected with specific guidance on what to fix. If a change contains a mix of generic and project-specific content, extract only the generic parts.
