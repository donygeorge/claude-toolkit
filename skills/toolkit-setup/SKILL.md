---
name: toolkit-setup
description: Use when setting up or reconfiguring the toolkit for a project.
argument-hint: "[--reconfigure]"
user-invocable: true
---

# Toolkit Setup Skill

Orchestrate post-bootstrap project configuration. Auto-detect stacks and commands, validate them, generate `toolkit.toml` and `CLAUDE.md`, and verify everything works end-to-end.

**Prerequisite**: The toolkit subtree must already be installed at `.claude/toolkit/`. If it is not, direct the user to follow the bootstrap instructions in the toolkit README.

## Usage

```bash
/toolkit-setup                     # Configure toolkit for current project state
/toolkit-setup --reconfigure       # Full re-detection, ignoring cached state
```

## When to Use

- **After bootstrap**: First-time configuration after the toolkit subtree is installed
- **After stack changes**: When the project adds or removes a technology stack
- **Reconfigure**: To re-detect everything from scratch, overriding previous detections

**When NOT to use** (the skill will detect these and redirect):

- To update the toolkit version → use `/toolkit-update` instead
- To diagnose issues → use `/toolkit-doctor` instead
- To regenerate settings after editing toolkit.toml → run `bash .claude/toolkit/toolkit.sh generate-settings`

## Flags

| Flag | Effect |
| ---- | ------ |
| `--reconfigure` | Skip state checks, run full re-detection from scratch. Useful when the project's tech stack or commands have changed. Existing `toolkit.toml` customizations are preserved (you will be asked about conflicts). |

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Never modify project source code** | This skill configures toolkit files only; it must never edit the consuming project's application code. |
| **2. Detect before assuming** | Always run `detect-project.py` and validate commands before writing config; never guess stacks or commands. |
| **3. Verify before committing** | Run `toolkit.sh validate` and confirm all generated files are correct before creating any commit. |
| **4. Preserve existing customizations** | When reconfiguring, keep user edits to `toolkit.toml` and customized files; ask about conflicts. |
| **5. Use Write/Edit tools for config files** | Use Claude's Write or Edit tools to create/modify `.claude/toolkit.toml` and `CLAUDE.md`. Do NOT use bash heredocs (`cat << 'EOF'`) as they may fail in sandbox environments. |
| **6. Use toolkit.sh for generated files** | Use `bash .claude/toolkit/toolkit.sh generate-settings` to regenerate `settings.json` and `.mcp.json`. These are generated files — never write them directly. |

---

## Execution Flow

Execute these phases in order. Do NOT skip phases.

### Phase 0: State Detection

Check the current toolkit installation state and resolve any issues before proceeding.

#### Step 0.1: Check toolkit subtree

```bash
ls .claude/toolkit/toolkit.sh
```

If the file does not exist, the toolkit is not installed. Tell the user:

> The toolkit subtree is not installed. Please follow the bootstrap instructions in the toolkit README to install it first, then re-run `/toolkit-setup`.

**Stop here** if the toolkit is not installed.

#### Step 0.2: Run detection script for toolkit state

```bash
python3 .claude/toolkit/detect-project.py --project-dir .
```

Parse the JSON output. Focus on the `toolkit_state` section:

```json
{
  "toolkit_state": {
    "subtree_exists": true,
    "toml_exists": true,
    "toml_is_example": false,
    "settings_generated": true,
    "missing_skills": [],
    "missing_agents": [],
    "broken_symlinks": []
  }
}
```

#### Step 0.3: Handle issues based on state

**If skills or agents are missing** (`missing_skills` or `missing_agents` non-empty):

This is a partial install. Fill the gaps:

```bash
bash .claude/toolkit/toolkit.sh init --force
```

Report to user: "Detected missing skills/agents. Ran `toolkit.sh init --force` to fill gaps."

**If `toml_exists` is false** (subtree exists but no toolkit.toml):

```bash
bash .claude/toolkit/toolkit.sh init --from-example
```

Report to user: "No toolkit.toml found. Created one from the example template."

**If `toml_is_example` is true** (toolkit.toml is still the unmodified example):

Note: "toolkit.toml is still the default example. This setup will customize it for your project."

**If broken symlinks exist** (`broken_symlinks` non-empty):

```bash
bash .claude/toolkit/toolkit.sh init --force
```

Report the broken symlinks that were found and fixed.

**If `settings_generated` is false** (settings.json does not exist):

The config is stale or was never generated. Regenerate it now:

```bash
python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env
bash .claude/toolkit/toolkit.sh generate-settings
```

Report to user: "Settings were missing or stale. Regenerated settings.json and config cache."

#### Step 0.4: Check for toolkit version changes

```bash
bash .claude/toolkit/toolkit.sh status
```

If the status output mentions a version change or shows that the toolkit was recently updated, inform the user:

> Toolkit has been updated. New features may be available. This setup will refresh your configuration.

If the user wants to see what changed, suggest they check the toolkit CHANGELOG:

```bash
cat .claude/toolkit/CHANGELOG.md
```

#### Step 0.5: Detect fully-configured toolkit (early exit)

If ALL of the following are true, the toolkit is already fully set up:

- `subtree_exists` is true
- `toml_exists` is true AND `toml_is_example` is false
- `settings_generated` is true
- `missing_skills` is empty
- `missing_agents` is empty
- `broken_symlinks` is empty
- `.claude/toolkit-manifest.json` exists

AND `--reconfigure` was NOT passed, then **stop here** and tell the user:

> The toolkit is already fully configured for this project. No setup changes needed.
>
> **If you want to:**
> - **Update to a newer toolkit version**: use `/toolkit-update`
> - **Diagnose issues or optimize config**: use `/toolkit-doctor`
> - **Re-detect stacks and commands from scratch**: use `/toolkit-setup --reconfigure`
> - **Regenerate settings after editing toolkit.toml**: run `bash .claude/toolkit/toolkit.sh generate-settings`

Then run a quick validation to confirm health:

```bash
bash .claude/toolkit/toolkit.sh validate
```

If validation passes, report the result and **stop**. Do not proceed to Phase 1.

If validation reports warnings or errors, report them and offer to fix (follow the fix steps in Phase 6.2). After fixes, **stop** — do not re-run the full setup flow.

#### Step 0.6: Handle --reconfigure flag

If `--reconfigure` was passed, skip the state-based shortcuts above and proceed directly to Phase 1 for full re-detection. Existing `toolkit.toml` values will be preserved where they differ from detected defaults (you will ask the user about conflicts in Phase 4).

---

### Phase 1: Project Discovery

Run the detection script to auto-detect project properties.

```bash
python3 .claude/toolkit/detect-project.py --project-dir .
```

Parse the full JSON output. The key fields are:

| Field | Description |
| ----- | ----------- |
| `name` | Project name (from git toplevel basename) |
| `stacks` | Detected technology stacks (e.g., `["python"]`, `["typescript", "python"]`) |
| `version_file` | Detected version file (e.g., `pyproject.toml`, `package.json`, `VERSION`) |
| `source_dirs` | Detected source directories (e.g., `["src", "app"]`) |
| `source_extensions` | File extensions for detected stacks (e.g., `["*.py"]`) |
| `lint` | Per-stack lint commands with availability status |
| `test` | Detected test command and its source (Makefile, package.json, etc.) |
| `format` | Per-stack format commands with availability status |
| `makefile_targets` | All Makefile targets found |
| `package_scripts` | All package.json scripts found |

Display a brief summary to the user:

> **Project detected**: [name]
> **Stacks**: [stacks]
> **Test command**: [test.cmd] (from [test.source])
> **Lint commands**: [list per stack]
> **Format commands**: [list per stack]
> **Source dirs**: [source_dirs]

---

### Phase 2: Command Validation

Validate that detected commands actually work by running them directly.

For each detected command (lint, test, format), run it manually:

```bash
# Example: validate lint command
ruff check --version    # Check if available
```

**For each command**:

- If the tool is available and responds to `--version`: keep the command
- If not found: note the failure

Display validation results to the user:

> **Validation results**:
>
> - Lint (python): `ruff check` -- available
> - Test: `make test` -- available
> - Format (python): `ruff format` -- not found

**If a command is not available**:

1. Check if an alternative exists (e.g., if `ruff` is not found, check if it's installed in `.venv/bin/`)
2. Ask the user: "The [type] command `[cmd]` was not found. Would you like to provide an alternative command, or skip this?"
3. If the user provides an alternative, validate it by running `<cmd> --version`
4. If skipped, leave that field empty in the config and note it in the output

---

### Phase 3: Present Findings

Before writing any configuration, present ALL detected and validated settings to the user for confirmation.

Display a summary table:

> **Setup Configuration** (please confirm or adjust):
>
> | Setting | Value |
> | ------- | ----- |
> | Project name | [name] |
> | Stacks | [stacks] |
> | Version file | [version_file] |
> | Test command | [test.cmd] |
> | Lint command(s) | [per stack, validated only] |
> | Format command(s) | [per stack, validated only] |
> | Source dirs | [source_dirs] |
> | Source extensions | [source_extensions] |
>
> Does this look correct? Reply with adjustments or "yes" to proceed.

**Wait for user confirmation before proceeding.**

If the user requests changes:

- Apply the changes to your working detection results
- Re-validate any new commands the user provided
- Re-display the updated table and ask for confirmation again

---

### Phase 4: Generate toolkit.toml

Generate or update `.claude/toolkit.toml` based on confirmed detection results.

#### Fresh setup (no existing toolkit.toml, or toolkit.toml is the unmodified example)

Read the example template for reference:

```bash
cat .claude/toolkit/templates/toolkit.toml.example
```

Use the **Write tool** (not bash heredocs) to create `.claude/toolkit.toml` with the confirmed detection results. Map detected values to TOML sections:

| Detection field | TOML location |
| --------------- | ------------- |
| `name` | `[project] name` |
| `stacks` | `[project] stacks` |
| `version_file` | `[project] version_file` |
| Lint commands | `[hooks.post-edit-lint.linters.<ext>] cmd` and `[hooks.task-completed.gates.lint] cmd` |
| Format commands | `[hooks.post-edit-lint.linters.<ext>] fmt` |
| Test command | `[hooks.task-completed.gates.tests] cmd` |
| Source dirs | `[hooks.compact] source_dirs` |
| Source extensions | `[hooks.compact] source_extensions` |

Use the example template structure. Include comments explaining each section. For lint/format commands, set the gate glob patterns based on the detected source extensions (e.g., `"*.py"` for Python lint gate).

For any detection field that was empty or skipped, use the example template defaults and add a comment noting it should be customized.

#### Existing toolkit.toml with customizations

Read the current `.claude/toolkit.toml`. Compare each detected value against the current value:

- **If current value matches detected value**: no change needed
- **If current value differs from detected value AND differs from the example default**: this is a user customization. Ask the user:

  > `[section.key]` is currently set to `[current_value]`. Detection suggests `[detected_value]`. Keep current or use detected? [keep/detected]

- **If current value matches the example default but detected value is different**: update silently (user never customized this)

Use the **Edit tool** to update `.claude/toolkit.toml` preserving the TOML structure and comments.

---

### Phase 5: Generate CLAUDE.md

Create or update the project's `CLAUDE.md` with detected values.

#### If no CLAUDE.md exists

Read the template:

```bash
cat .claude/toolkit/templates/CLAUDE.md.template
```

Replace placeholders with detected values:

| Placeholder | Value |
| ----------- | ----- |
| `{{PROJECT_NAME}}` | Confirmed project name |
| `{{PROJECT_DESCRIPTION}}` | Ask user for a brief description if not obvious from the project |
| `{{TECH_STACK}}` | Comma-separated stacks (e.g., "Python 3.11+, TypeScript") |
| `{{RUN_COMMAND}}` | The project's run/start command (ask user if not obvious) |
| `{{TEST_COMMAND}}` | Validated test command from Phase 2 |
| `{{LINT_COMMAND}}` | Validated lint command from Phase 2 |
| `{{FORMAT_COMMAND}}` | Validated format command from Phase 2 |

For any command placeholder where no command was detected or validated, comment out that line with a note to customize.

Use the **Write tool** to create `CLAUDE.md` at the project root.

Tell the user:

> Created `CLAUDE.md` from template. Please review and customize the sections marked with `<!-- ... -->` comments.

#### If CLAUDE.md already exists

Do NOT overwrite the existing file. Instead, check if it already mentions the toolkit. If not, append a toolkit section.

To get the toolkit's remote URL (for linking in the section), run:

```bash
git remote get-url claude-toolkit 2>/dev/null || echo "unknown"
```

Then append:

```markdown

## Claude Toolkit

This project uses claude-toolkit for Claude Code configuration.

- Config: `.claude/toolkit.toml`
- Status: `bash .claude/toolkit/toolkit.sh status`
- Validate: `bash .claude/toolkit/toolkit.sh validate`
- Update: `bash .claude/toolkit/toolkit.sh update`
```

If the remote URL was found, make "claude-toolkit" a markdown link to that URL.

If the CLAUDE.md already has a toolkit section, leave it unchanged.

---

### Phase 6: Settings Generation & Validation

Generate the merged settings and validate the installation.

#### Step 6.1: Generate settings

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

This merges base settings + stack overlays + project overrides into `.claude/settings.json` and `.mcp.json`.

If this fails, read the error output and fix the issue (usually a malformed toolkit.toml). Re-run after fixing.

#### Step 6.2: Validate installation

```bash
bash .claude/toolkit/toolkit.sh validate
```

This checks:

- Hook scripts are executable
- Symlinks are valid
- Settings files exist and are well-formed
- Config cache is up to date
- **Settings protection**: project-specific settings are preserved in `settings-project.json`

**Critical check**: If validate warns about "project-specific settings but no settings-project.json", this means the project had custom settings that aren't protected. Fix immediately:

```bash
cp .claude/settings.json.pre-toolkit .claude/settings-project.json
bash .claude/toolkit/toolkit.sh generate-settings
```

If no `.pre-toolkit` backup exists but settings look incomplete (missing permissions, MCP servers, sandbox config), ask the user to check git history for their original `settings.json` and restore it as `settings-project.json`.

If validation reports other issues, attempt to fix them:

- Missing executability: `chmod +x .claude/toolkit/hooks/*.sh`
- Broken symlinks: `bash .claude/toolkit/toolkit.sh init --force`
- Stale config cache: `python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env`

Re-run validation after fixes. If issues persist, report them to the user.

---

### Phase 7: End-to-End Verification

Verify that the configured commands actually work in the project context.

#### Step 7.1: Verify lint command

If a lint command was configured, run it on a real source file:

Find a source file in one of the detected source directories and run the configured lint command on it. For example, if the lint command is for Python files, find a `.py` file and run the lint check command against it.

If the lint command fails:

1. Check if the failure is a real lint issue (expected) or a configuration problem (unexpected)
2. If it is a configuration problem, adjust the command in toolkit.toml and re-run
3. Iterate up to 2 times

#### Step 7.2: Verify test command

If a test command was configured, run it:

```bash
# Run the configured test command (whatever was written to toolkit.toml)
```

If the test command fails:

1. Check if tests are genuinely failing (not a config issue) -- this is OK, report to user
2. If the command itself is broken (wrong path, missing dependency), adjust and re-run
3. Iterate up to 2 times

#### Step 7.3: Report verification results

> **Verification results**:
>
> - Lint: [passed/failed/skipped]
> - Tests: [passed/failed/skipped]
>
> [If failures] Note: some commands reported failures. This may be expected (e.g., existing lint issues or failing tests). The configuration itself is correct.

---

### Phase 8: Commit

Stage and commit all configuration changes.

#### Step 8.0: Ensure .gitignore entries

Check the project's `.gitignore` and ensure it contains the toolkit-related entries. If `.gitignore` does not exist, create it. Add any missing lines:

```text
# Claude Toolkit - implementation artifacts
artifacts/

# Claude Toolkit - generated config cache
toolkit-cache.env
```

If `.gitignore` already contains these entries, skip this step.

#### Step 8.1: Review changes

```bash
git status
git diff
```

Review the changes to ensure only expected files are modified. The typical files are:

- `.claude/toolkit.toml`
- `.claude/toolkit-cache.env`
- `.claude/settings.json`
- `.mcp.json`
- `CLAUDE.md` (new or modified)
- `.claude/skills/` (if init --force was run)
- `.claude/agents/` (if init --force was run)
- `.claude/rules/` (if init --force was run)

#### Step 8.2: Stage specific files

Stage each file individually. Do NOT use `git add .` or `git add -A`.

```bash
git add .claude/toolkit.toml
git add .claude/settings.json
git add .mcp.json
git add CLAUDE.md
git add .gitignore
```

Note: `toolkit-cache.env` is generated and gitignored — do NOT stage it.

Also stage any files created or restored by `toolkit.sh init --force` (skills, agents, rules).

#### Step 8.3: Commit

Write a descriptive commit message and commit:

```bash
git commit -F /tmp/setup-commit-msg.txt
```

Example commit message:

```text
Configure claude-toolkit for [project-name]

- Detected stacks: [stacks]
- Validated commands: lint=[cmd], test=[cmd], format=[cmd]
- Generated toolkit.toml, settings.json, CLAUDE.md
- All validation checks passed
```

---

## Error Handling

| Error | Recovery |
| ----- | -------- |
| `detect-project.py` not found | Toolkit may be outdated. Run `bash .claude/toolkit/toolkit.sh update` and retry. |
| Detection returns empty stacks | Ask user to specify stacks manually. Write them to toolkit.toml. |
| All commands fail validation | Ask user to provide working commands. Proceed with manual config. |
| `toolkit.sh generate-settings` fails | Check toolkit.toml for syntax errors. Run `python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env --validate-only` to find issues. |
| `toolkit.sh validate` reports issues | Attempt auto-fix (init --force, chmod). Report remaining issues to user. |
| User provides no confirmation in Phase 3 | Remind the user that confirmation is needed. Do not proceed without it. |

## Output

After completion, report to the user:

- Toolkit state before setup (fresh, partial, existing)
- Stacks detected and validated
- Commands configured (lint, test, format)
- Files created or modified
- Validation result (pass/fail)
- Any items needing manual attention
