---
name: setup-toolkit
description: Use when setting up, updating, diagnosing, or contributing back to the toolkit.
argument-hint: "[--reconfigure] [--update [version]] [--doctor] [--contribute]"
user-invocable: true
---

# Setup Skill

Orchestrate post-bootstrap project configuration. Auto-detect stacks and commands, validate them, generate `toolkit.toml` and `CLAUDE.md`, and verify everything works end-to-end.

**Prerequisite**: The toolkit subtree must already be installed at `.claude/toolkit/`. If it is not, direct the user to follow the bootstrap instructions in the toolkit README.

## Usage

```bash
/setup-toolkit                     # Configure toolkit for current project state
/setup-toolkit --reconfigure       # Full re-detection, ignoring cached state
/setup-toolkit --update            # Update toolkit to latest release
/setup-toolkit --update v1.3.0     # Update toolkit to a specific version
/setup-toolkit --doctor            # Deep health evaluation and optimization
/setup-toolkit --contribute        # Upstream generic improvements back to toolkit
```

## When to Use

- **After bootstrap**: First-time configuration after the toolkit subtree is installed
- **After updating toolkit**: To pick up new skills, agents, or config options
- **After stack changes**: When the project adds or removes a technology stack
- **Reconfigure**: To re-detect everything from scratch, overriding previous detections

## Flags

| Flag | Effect |
| ---- | ------ |
| `--reconfigure` | Skip state checks, run full re-detection from scratch. Useful when the project's tech stack or commands have changed. Existing `toolkit.toml` customizations are preserved (you will be asked about conflicts). |
| `--update [version]` | Run the Update Flow instead of the setup flow. Performs pre-flight checks, fetches the latest (or specified) toolkit version, executes the update with conflict resolution, validates the result, resolves drift in customized files, and commits. If `version` is provided (e.g., `v1.3.0`), updates to that specific tag; otherwise updates to the latest release. |
| `--doctor` | Run the Doctor Flow instead of the setup flow. Performs a baseline infrastructure check (via `toolkit.sh doctor`), then deep analysis of configuration coherence, live command validation, dependency and API key audits, CLAUDE.md content analysis, optimization opportunities, and hook health testing. Presents findings by severity and offers interactive fixes. |
| `--contribute` | Run the Contribute Flow instead of the setup flow. Identifies customized files with generic improvements, evaluates them against a 10-point generalizability checklist, prepares clean changes for the toolkit repo, validates with the full test suite, and generates submission instructions (patch or PR). |

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Never modify project source code** | This skill configures toolkit files only; it must never edit the consuming project's application code. |
| **2. Detect before assuming** | Always run `detect-project.py` and validate commands before writing config; never guess stacks or commands. |
| **3. Verify before committing** | Run `toolkit.sh validate` and confirm all generated files are correct before creating any commit. |
| **4. Preserve existing customizations** | When reconfiguring, keep user edits to `toolkit.toml` and customized files; ask about conflicts. |
| **5. One mode at a time** | If multiple mode flags are passed (`--update`, `--doctor`, `--contribute`), reject immediately with an error. |

---

## Execution Flow

> **Routing**: If more than one of `--update`, `--doctor`, `--contribute`, or `--reconfigure` are passed together, stop immediately and inform the user: "Only one mode flag can be used at a time. Please run `/setup-toolkit` with a single flag." If `--update` was passed, skip the setup phases below and jump directly to the [Update Flow](#update-flow) section. If `--doctor` was passed, skip the setup phases below and jump directly to the [Doctor Flow](#doctor-flow) section. If `--contribute` was passed, skip the setup phases below and jump directly to the [Contribute Flow](#contribute-flow) section.

Execute these phases in order. Do NOT skip phases.

### Phase 0: State Detection

Check the current toolkit installation state and resolve any issues before proceeding.

#### Step 0.1: Check toolkit subtree

```bash
ls .claude/toolkit/toolkit.sh
```

If the file does not exist, the toolkit is not installed. Tell the user:

> The toolkit subtree is not installed. Please follow the bootstrap instructions in the toolkit README to install it first, then re-run `/setup-toolkit`.

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

#### Step 0.5: Handle --reconfigure flag

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

Write a new `.claude/toolkit.toml` using the confirmed detection results. Map detected values to TOML sections:

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

Write the updated `.claude/toolkit.toml` preserving the TOML structure and comments.

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

Write the result to `CLAUDE.md` at the project root.

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

If validation reports issues, attempt to fix them:

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
git add .claude/toolkit-cache.env
git add .claude/settings.json
git add .mcp.json
git add CLAUDE.md
git add .gitignore
```

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

---

## Update Flow

This flow is executed when `--update` is passed. It replaces the setup phases above.

> **User Interaction Principle**: When in doubt, ask. Never make assumptions about which version to pull, how to resolve conflicts, or what to do with drift. Present options and let the user decide.

### Phase U0: Pre-flight

Verify the project is in a healthy state before attempting an update.

#### Step U0.1: Check toolkit status

```bash
bash .claude/toolkit/toolkit.sh status
```

Review the output. Note the current toolkit version and any reported issues.

#### Step U0.2: Validate current installation

```bash
bash .claude/toolkit/toolkit.sh validate
```

If validation reports issues, inform the user:

> Validation found issues with the current installation. These should be resolved before updating.

List each issue. Attempt to fix automatically (e.g., broken symlinks via `toolkit.sh init --force`, stale cache via regeneration). Re-run validation after fixes. If issues persist, **ask the user** whether to proceed with the update anyway or abort.

#### Step U0.3: Check for uncommitted changes

```bash
git status --porcelain
git diff --stat
```

If there are uncommitted changes, warn the user:

> There are uncommitted changes in your working tree. Updating the toolkit may cause conflicts with these changes.

List the changed files. If any uncommitted changes are inside `.claude/toolkit/`, **strongly recommend** committing or stashing before proceeding -- subtree pull requires a clean subtree directory and will fail or produce corrupt merges if the subtree has local modifications.

**Ask the user**: commit or stash changes first, or proceed anyway?

**Do NOT proceed until the user confirms.**

#### Step U0.4: Check toolkit remote

```bash
git remote get-url claude-toolkit 2>/dev/null
```

If the remote does not exist, inform the user:

> The git remote `claude-toolkit` is not configured. This is required for updates.
>
> Please provide the toolkit repository URL so I can add it.

If the user provides a URL:

```bash
git remote add claude-toolkit <url>
```

**Do NOT proceed until the remote is configured.**

---

### Phase U1: Fetch & Preview

Fetch available versions and let the user choose which version to update to.

#### Step U1.1: Fetch tags from remote

```bash
git fetch claude-toolkit --tags
```

If the fetch fails, see the [Update Error Handling](#update-error-handling) table.

#### Step U1.2: Show available versions

```bash
git tag -l 'v*' --sort=-version:refname | head -10
```

Read the current toolkit version:

```bash
cat .claude/toolkit/VERSION
```

If the VERSION file does not exist or is empty, display the current version as "unknown" and note this to the user.

Display a version comparison to the user:

> **Current version**: [current_version]
> **Available versions**: [list of tags, newest first]
> **Latest release**: [newest tag]

If no tags are found (the tag list is empty), inform the user:

> No release tags found in the toolkit remote. Options:
>
> 1. Update to the latest `main` branch (may include unreleased changes)
> 2. Abort the update

If the user chooses main, use `claude-toolkit/main` as the target ref instead of a version tag.

If `--update` was called with a specific version (e.g., `--update v1.3.0`), confirm that the requested version exists in the tag list. If the requested version is not found:

> Version `[requested_version]` was not found. Available versions are: [list]. Would you like to choose from these, update to the latest release, or abort?

**Do NOT proceed with a non-existent version.**

#### Step U1.3: Show CHANGELOG entries

Display the CHANGELOG entries between the current version and the target version:

```bash
cat .claude/toolkit/CHANGELOG.md
```

Extract and display only the entries between the current and target versions. Summarize key changes (new features, bug fixes, breaking changes).

If CHANGELOG.md does not exist, inform the user and continue without change summaries.

#### Step U1.4: Preview drift for customized files

```bash
bash .claude/toolkit/toolkit.sh status
```

If the status output shows customized files, note them. These files will need drift resolution after the update (Phase U4).

> **Customized files that may be affected by this update**:
>
> - [list of customized files from status output]

#### Step U1.5: Ask user to confirm

Present the update plan to the user:

> **Update plan**:
>
> - From: [current_version]
> - To: [target_version]
> - New features: [brief summary from CHANGELOG]
> - Customized files to review after update: [count]
>
> Which version would you like to update to? [present options: latest, specific version, or abort]

**Wait for the user to confirm before proceeding.**

---

### Phase U2: Execute Update

Run the toolkit update and handle any conflicts.

#### Step U2.1: Run the update command

```bash
bash .claude/toolkit/toolkit.sh update [version]
```

Replace `[version]` with the user's chosen version (e.g., `v1.3.0`), or omit for the latest release.

#### Step U2.2: Check if already up to date

After the update command completes, check whether anything actually changed:

```bash
git diff HEAD~1 --stat
```

If the update command output says "Already up to date" or if no files changed (empty diff):

> The toolkit is already at the target version. No changes were made.

**Skip phases U3-U5 and end the update flow.**

#### Step U2.3: Check for conflicts

If the update command fails, check for merge conflicts:

```bash
git diff --diff-filter=U --name-only
```

If there are conflicted files, present them to the user:

> **Merge conflicts detected** in the following files:
>
> - [list of conflicted files]

**Ask the user**: Would you like me to resolve these conflicts automatically, or would you prefer to abort the update?

If the user chooses automatic resolution:

1. For each conflicted file, check if it is a binary file (`file <path>`). Binary files cannot be merged textually -- offer "keep ours" (`git checkout --ours`) or "take theirs" (`git checkout --theirs`) and **ask the user** which to keep. For text files, read the file and analyze the conflict markers
2. Show the proposed resolution (which side to keep, or how to merge)
3. **Ask the user to confirm** the resolution for each file before applying
4. After resolving, mark the file as resolved: `git add [resolved_file]`
5. Once all conflicts are resolved, complete the subtree merge: `git commit --no-edit`

Note: This commit completes the subtree merge only. The Phase U5 commit will capture additional post-update changes (settings regeneration, drift resolution, manifest updates).

If the user chooses to abort:

```bash
git merge --abort
```

After aborting, verify the working tree is clean:

```bash
git status --porcelain
```

If files remain modified after the abort, inform the user and help resolve the leftover state. Otherwise, confirm the update was aborted and no changes were made.

---

### Phase U3: Post-Update Validation

Run all 10 validation checks to ensure the update did not break anything. For each failing check, attempt up to 3 automatic fix attempts before escalating to the user.

#### Check 1: Shellcheck

```bash
shellcheck -x -S warning .claude/toolkit/hooks/*.sh .claude/toolkit/lib/*.sh .claude/toolkit/toolkit.sh
```

If issues are found: these are in toolkit code and should not be modified locally. Note them and report to the user.

#### Check 2: Toolkit validate (includes symlink health)

```bash
bash .claude/toolkit/toolkit.sh validate
```

Review the full output, paying special attention to the symlink section. If broken symlinks exist, run `bash .claude/toolkit/toolkit.sh init --force`. If other issues are found, attempt auto-fix (init --force, chmod +x). Retry up to 3 times.

#### Check 3: Generate settings

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

If this fails: check toolkit.toml for compatibility with the new toolkit version. **Ask the user** if the error is unclear.

#### Check 4: JSON validity

```bash
python3 -c "import json; json.load(open('.claude/settings.json'))"
python3 -c "import json; json.load(open('.mcp.json'))"
```

If invalid: regenerate settings (Check 3). If still invalid, **ask the user**.

#### Check 5: Symlink health

Verify symlinks point to valid targets (this is a quick direct check, complementing the broader Check 2):

```bash
ls -la .claude/agents/ .claude/rules/
```

For each symlink, verify it resolves to a file that exists. If any symlink is broken:

```bash
bash .claude/toolkit/toolkit.sh init --force
```

Retry up to 3 times.

#### Check 6: Manifest integrity

Check that the manifest file exists and is valid:

```bash
python3 -c "import json; json.load(open('.claude/toolkit-manifest.json'))"
```

If missing or invalid, re-initialize. **Warning**: `init --force` resets the manifest, which clears customization tracking. If the user has customized files, note which files were customized (from Phase U0 or U4) so they can be re-customized after re-initialization.

```bash
bash .claude/toolkit/toolkit.sh init --force
```

#### Check 7: Hook executability

```bash
ls -la .claude/toolkit/hooks/*.sh
```

Verify all hook scripts are executable. If any are not:

```bash
chmod +x .claude/toolkit/hooks/*.sh
```

#### Check 8: Config cache freshness

```bash
python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env
```

Regenerate the config cache to ensure it reflects any new config options from the update.

#### Check 9: Project test suite

Run the project's configured test command (from toolkit.toml):

```bash
# Run the project's test command as configured in toolkit.toml
```

If tests fail: determine whether the failure is related to the toolkit update or a pre-existing issue. **Ask the user** if the failure is unclear or requires a judgment call.

#### Check 10: Project lint

Run the project's configured lint command (from toolkit.toml):

```bash
# Run the project's lint command as configured in toolkit.toml
```

If lint fails: determine whether the failure is related to the toolkit update or a pre-existing issue. **Ask the user** if the failure is unclear.

#### Validation summary

After all 10 checks, present the results in a table:

| Check | Result | Notes |
| ----- | ------ | ----- |
| Shellcheck | pass/fail | [details] |
| Toolkit validate | pass/fail | [details] |
| Generate settings | pass/fail | [details] |
| JSON validity | pass/fail | [details] |
| Symlink health | pass/fail | [details] |
| Manifest integrity | pass/fail | [details] |
| Hook executability | pass/fail | [details] |
| Config cache freshness | pass/fail | [details] |
| Project test suite | pass/fail/skipped | [details] |
| Project lint | pass/fail/skipped | [details] |

If any checks failed after fix attempts, **ask the user** how to proceed.

---

### Phase U4: Drift Resolution

For each customized file that has upstream changes (drift), help the user decide how to handle it.

#### Step U4.1: Detect drift

First, check for customized files:

```bash
bash .claude/toolkit/toolkit.sh status
```

Then, for each customized file reported by status, manually check for drift by comparing the manifest's recorded `toolkit_hash` against the current toolkit source hash:

```bash
shasum -a 256 .claude/toolkit/<source_path>
```

If the hash differs from what the manifest records, there is drift -- the toolkit source changed since the file was customized.

Note: For skills, compare each file in the skill directory individually, as the drift checker may not cover skills automatically.

If no drift is detected for any customized file, skip to Phase U5.

#### Step U4.2: Analyze each drifted file

For each customized file with drift:

1. Read the user's customized version (in `.claude/agents/`, `.claude/rules/`, or `.claude/skills/`)
2. Read the updated toolkit source version (in `.claude/toolkit/agents/`, `.claude/toolkit/rules/`, or `.claude/toolkit/skills/`)
3. Compare the two versions and analyze the nature of the changes:
   - What did the user customize? (their local changes)
   - What changed upstream? (toolkit updates)
   - Are the changes in the same sections (potential conflict) or different sections (clean merge)?

Present the analysis to the user:

> **Drift detected**: [file_path]
>
> **Your customizations**:
> [summary of user's changes]
>
> **Upstream changes**:
> [summary of toolkit changes]
>
> **Conflict risk**: [low/medium/high -- based on whether changes overlap]

#### Step U4.3: Ask user for resolution

For each drifted file, **ask the user**:

> How would you like to handle this file?
>
> 1. **Keep customization** -- preserve your version, ignore upstream changes
> 2. **Merge upstream changes** -- intelligently merge both sets of changes
> 3. **Revert to managed** -- discard your customizations and use the new toolkit version

**Wait for the user's choice.**

#### Step U4.4: Apply resolution

Based on the user's choice:

**Keep customization**: No file changes needed. Update the manifest to record the new toolkit hash (so drift is no longer reported for the current version):

```bash
NEW_HASH=$(shasum -a 256 .claude/toolkit/<source_path> | cut -d' ' -f1)
# Use jq to update the toolkit_hash for this file's entry in .claude/toolkit-manifest.json
```

**Merge upstream changes**: Perform an intelligent merge of the user's customizations with the upstream changes. Show the merged result to the user and **ask for confirmation** before writing the file. If the merge is ambiguous, present options and let the user decide.

**Revert to managed**: Replace the customized file with the toolkit source. First, verify the toolkit source still exists (the update may have removed the file upstream). If the source was deleted upstream, inform the user and skip this file.

If the source exists, restore it:

```bash
# For agents/rules: restore symlink
ln -sf ../toolkit/agents/[file] .claude/agents/[file]
# For skills: copy ALL files in the skill directory (skills can contain multiple files)
cp .claude/toolkit/skills/[skill]/* .claude/skills/[skill]/
```

After applying the resolution, update the manifest hashes to reflect the current state.

---

### Phase U5: Summary & Commit

Present a comprehensive summary and commit the update.

#### Step U5.1: Generate summary

Compile the following mandatory structured summary. The summary must include all of these sections:

- **Version transition**: [old_version] -> [new_version]
- **Files changed**: [count] files modified by the update, with list from `git diff --stat`
- **Customizations preserved**: [count], with list of customized files that were kept
- **Drift resolved**: [count], with list of drifted files and their resolution (kept/merged/reverted)
- **Validation results**: a table with all 10 checks (shellcheck, toolkit validate, generate settings, JSON validity, symlink health, manifest integrity, hook executability, config cache freshness, project test suite, project lint) and their pass/fail/skipped status
- **New features from CHANGELOG**: notable new features or changes between the old and new version
- **Action required**: remind user to restart Claude Code to pick up the updated settings and hooks

#### Step U5.2: Ask user to review

Present the summary to the user:

> Please review this update summary. Does everything look correct? Reply with "yes" to commit, or note any concerns.

**Wait for the user to confirm before committing.**

#### Step U5.3: Stage and commit

Before staging, check if there are actually changes to commit:

```bash
git status --porcelain
```

If there are no changes (output is empty), all update changes were captured in the subtree merge commit. No additional commit is needed -- skip to the summary output and inform the user.

If there are changes, stage all changed files individually. Do NOT use `git add .` or `git add -A`.

```bash
git add .claude/toolkit/
git add .claude/settings.json
git add .mcp.json
git add .claude/toolkit-manifest.json
```

Note: `toolkit-cache.env` is typically in `.gitignore` and should NOT be staged.

Also stage any files that were modified during drift resolution (agents, rules, skills).

Write a descriptive commit message and commit:

```bash
git commit -F /tmp/update-commit-msg.txt
```

Example commit message:

```text
Update claude-toolkit from [old_version] to [new_version]

- [count] files updated via subtree pull
- [count] customizations preserved
- [count] drift resolutions applied
- All validation checks passed
```

---

## Update Rollback

If the update causes problems after completion, use these recovery steps.

### Rollback a Completed Update

```text
1. Find the merge commit from the update:
   git log --oneline -5
   # Look for "Update claude-toolkit to <version>" commit(s)

2. Revert the update commit(s) in reverse order (newest first):
   git revert <post-update-commit> --no-edit   # if Phase U5 created one
   git revert <subtree-merge-commit> --no-edit  # the subtree pull commit

3. Regenerate settings from the reverted toolkit source:
   bash .claude/toolkit/toolkit.sh generate-settings

4. Refresh symlinks:
   bash .claude/toolkit/toolkit.sh init --force

5. Verify the rollback:
   bash .claude/toolkit/toolkit.sh validate
```

### Rollback During Update (Before Commit)

If validation fails in Phase U3 and the user wants to abort after the subtree pull:

```text
1. If the subtree merge commit was created:
   git revert HEAD --no-edit

2. Regenerate settings:
   bash .claude/toolkit/toolkit.sh generate-settings

3. Verify:
   bash .claude/toolkit/toolkit.sh validate
```

**NEVER use `git reset --hard`** — always use `git revert` to preserve history. Only the user can authorize destructive git operations.

---

## Update Error Handling

| Error | Recovery |
| ----- | -------- |
| `git fetch claude-toolkit` fails | Check that the `claude-toolkit` remote exists: `git remote -v`. If missing, ask the user for the remote URL and add it: `git remote add claude-toolkit <url>`. Retry the fetch. |
| Subtree pull conflict | Detect conflicted files with `git diff --diff-filter=U --name-only`. Present conflicts to user. Offer automatic resolution or abort (`git merge --abort`). See Phase U2 for details. |
| Validation failure (any of 10 checks) | Attempt auto-fix up to 3 times per check. If still failing, present the error details to the user and ask how to proceed. Do not silently ignore validation failures. |
| Drift merge failure | If an intelligent merge fails or produces ambiguous results, show both versions to the user and ask them to choose or manually edit. Do not apply an uncertain merge automatically. |

---

## Contribute Flow

This flow is executed when `--contribute` is passed. It replaces the setup phases above.

> **User Interaction Principle**: The contribute flow is collaborative. At every decision point -- which files to contribute, how to extract generic parts, how to handle divergence, which submission workflow -- ask the user. Never auto-proceed past a judgment call.

### Phase C0: Identify Candidates

Find all customized and modified files that could potentially be contributed upstream.

#### Step C0.1: Check toolkit status

```bash
bash .claude/toolkit/toolkit.sh status
```

If `toolkit.sh status` reports that the manifest is missing, inform the user and offer to initialize it with `bash .claude/toolkit/toolkit.sh init --force`. Note that after initializing, all files will be marked as "managed" with no customizations recorded -- the user would need to re-customize files first.

Review the output. Identify two categories of candidate files:

1. **Customized files**: Files marked as "customized" in the manifest (the user explicitly took ownership via `toolkit.sh customize`)
2. **Modified managed files**: Files that differ from the toolkit source but are still marked as "managed" (local edits without formal customization)

If no customized or modified files are found, inform the user:

> No customized or modified files were found. There is nothing to contribute upstream. If you have improvements to suggest, first customize a file with `toolkit.sh customize <path>`, make your changes, and then re-run `/setup-toolkit --contribute`.

**Stop here** if no candidates are found.

#### Step C0.2: Diff each candidate against toolkit source

For each candidate file, generate a detailed diff against the toolkit source:

```bash
diff -u .claude/toolkit/<source_path> .claude/<installed_path>
```

For agents and rules, the toolkit source is in `.claude/toolkit/agents/` or `.claude/toolkit/rules/`. For skills, the toolkit source is in `.claude/toolkit/skills/<skill_name>/`.

Before diffing, verify the installed file actually exists on disk. If a customized file was deleted, skip it and inform the user it needs to be restored.

If the diff is empty (the customized file is identical to the toolkit source), skip it:

> `[file_path]` is marked as customized but is identical to the toolkit source. No changes to contribute.

Remove empty-diff files from the candidate list.

#### Step C0.3: Analyze and present candidates

For each candidate, provide a structured analysis:

> **Candidate**: [file_path]
>
> **Change summary**: [brief description of what changed]
>
> **Generic vs project-specific assessment**:
>
> - Generic changes: [list of changes that are reusable across projects]
> - Project-specific changes: [list of changes that reference project-specific tools, paths, or conventions]
> - Mixed changes: [list of changes where generic and project-specific parts are interleaved]
>
> **Recommendation**: [contribute as-is / extract generic parts / skip]

After presenting all candidates, **ask the user**:

> Which changes do you want to propose contributing? You can select or deselect individual candidates. Reply with the file names you want to include, or "all" / "none".

**Wait for the user to select candidates before proceeding.**

---

### Phase C1: Generalizability Gate

Evaluate each selected candidate against a strict 10-point generalizability checklist. All 7 hard requirements must pass. Quality requirements are advisory but strongly recommended.

#### Hard Requirements (all must pass)

| # | Requirement | Check |
| - | ----------- | ----- |
| H1 | No project paths | The change must not contain absolute paths or project-specific directory structures (e.g., `src/myapp/`, `/opt/myproject/`) |
| H2 | No project tool references | The change must not reference project-specific tools by name (e.g., a specific CI system, a proprietary CLI tool, a project-internal script) |
| H3 | No project conventions | The change must not encode project-specific coding conventions, naming patterns, or workflow rules that are not universally applicable |
| H4 | No project defaults | The change must not hardcode project-specific default values (e.g., a specific port number, a specific database name, a project-specific URL) |
| H5 | Config-driven variability | Any behavior that could vary between projects must be driven by `toolkit.toml` configuration or `_config.sh` variables, not hardcoded |
| H6 | Agent/skill genericness | If the change is to an agent prompt or skill, the content must be universally applicable -- no references to specific frameworks, libraries, or tools unless they are configurable |
| H7 | Hook uses `_config.sh` | If the change is to a hook script, all project-variable values must come from `_config.sh` variables, not hardcoded in the hook |

#### Quality Requirements (strongly recommended)

| # | Requirement | Check |
| - | ----------- | ----- |
| Q1 | Backward compatible | The change must not break existing configurations or workflows -- existing toolkit.toml files must continue to work without modification |
| Q2 | Follows existing patterns | The change must follow the coding style, structure, and conventions already established in the toolkit (e.g., hook structure, agent prompt format, skill phase style) |
| Q3 | Clear purpose | The change must have a clear, documented purpose -- what problem does it solve, and why is it useful across projects? |

#### Step C1.1: Evaluate each candidate

For each selected candidate, evaluate all 10 points. Present the results:

> **Generalizability check**: [file_path]
>
> | # | Requirement | Result | Notes |
> | - | ----------- | ------ | ----- |
> | H1 | No project paths | pass/FAIL | [details] |
> | H2 | No project tool refs | pass/FAIL | [details] |
> | H3 | No project conventions | pass/FAIL | [details] |
> | H4 | No project defaults | pass/FAIL | [details] |
> | H5 | Config-driven variability | pass/FAIL | [details] |
> | H6 | Agent/skill genericness | pass/FAIL | [details] |
> | H7 | Hook uses _config.sh | pass/FAIL | [details] |
> | Q1 | Backward compatible | pass/FAIL | [details] |
> | Q2 | Follows patterns | pass/FAIL | [details] |
> | Q3 | Clear purpose | pass/FAIL | [details] |

#### Step C1.2: Handle mixed changes

If a candidate contains both generic and project-specific changes (mixed), show what would be kept vs removed:

> **Extracting generic parts from**: [file_path]
>
> **Will keep** (generic):
>
> ```diff
> [diff of generic changes only]
> ```
>
> **Will remove** (project-specific):
>
> ```diff
> [diff of project-specific changes]
> ```
>
> Does this extraction look correct? Would you like to adjust what is kept vs removed?

**Ask the user to confirm** the extraction before proceeding.

#### Step C1.3: Handle gate failures

If any hard requirement fails, inform the user with specific guidance:

> **Generalizability gate FAILED** for [file_path]:
>
> - [H#]: [specific issue and what needs to change]
>
> Options:
>
> 1. **Revise** the change to make it more generic (I can suggest specific modifications)
> 2. **Skip** this file and continue with other candidates

**Ask the user** which option they prefer. If they choose to revise, suggest specific modifications that would make the change pass the gate, then re-evaluate.

#### Step C1.4: Check for remaining candidates

After evaluating all candidates, if every file was skipped or failed the gate (none passed), inform the user:

> All selected candidates failed the generalizability gate. There are no generic changes to contribute at this time. Consider making changes more config-driven and trying again.

**Stop the contribute flow here.** Do not proceed to C2.

---

### Phase C2: Prepare Clean Changes

Apply only the approved, gate-passing changes to the toolkit source files. Handle divergence intelligently.

#### Step C2.1: Check for toolkit source divergence

For each approved candidate, compare the toolkit source that the user's customization was originally based on against the current toolkit source:

```bash
# Read the toolkit_hash from the manifest for this file
# Compare against the current toolkit source hash
```

If the toolkit source has changed since the user customized the file (i.e., the manifest `toolkit_hash` differs from the current file hash), there is divergence.

#### Step C2.2: Handle divergence

If divergence is detected for a file, show the situation to the user:

> **Toolkit source has diverged**: [file_path]
>
> The toolkit source for this file has changed since you customized it. Your changes were based on an older version.
>
> **Your changes** (what you want to contribute):
>
> ```diff
> [user's changes relative to their base version]
> ```
>
> **Upstream changes** (what changed in toolkit since your customization):
>
> ```diff
> [toolkit changes since the user's base version]
> ```
>
> **Conflict assessment**: [describe whether the changes overlap or are in separate sections]

If the changes are in separate sections (no conflict):

> The changes appear to be in separate sections. I can merge them cleanly. Here is the proposed merged result:
>
> ```diff
> [merged diff]
> ```
>
> Does this merge look correct?

If the changes overlap (potential conflict):

> The changes overlap in the same sections. I need your guidance:
>
> 1. **Adapt changes** -- I will attempt to integrate your changes into the current toolkit source, preserving both sets of changes
> 2. **Skip** this file -- exclude it from the contribution
> 3. **Abort** -- stop the contribute flow entirely
>
> Which would you prefer?

If the user chooses to adapt, show the proposed adaptation and **ask the user to confirm** before applying.

**Wait for the user's decision on each diverged file.**

#### Step C2.3: Preview and apply changes to toolkit source

**IMPORTANT**: Show the user what will change BEFORE modifying any files.

For each approved file (with divergence resolved), generate a preview diff showing what would change in the toolkit source:

```bash
# For each file, generate a preview diff WITHOUT applying yet
diff -u .claude/toolkit/<source_path> .claude/<installed_path>
```

Present the combined preview to the user:

> **Proposed changes to toolkit source** (not yet applied):
>
> ```diff
> [preview diff of all changes that will be applied]
> ```
>
> Does this look correct? Reply "yes" to apply these changes, or note any adjustments.

**Wait for user confirmation before applying.**

After the user confirms, apply the changes to the toolkit source files:

```bash
# Copy the approved changes to .claude/toolkit/<source_path>
```

Verify the changes were applied correctly. Note: `.claude/toolkit` is a subtree, not a separate repository -- always run git commands from the project root:

```bash
git diff -- .claude/toolkit/
```

If the diff is empty after applying, the changes may not have been applied correctly. Investigate before proceeding.

---

### Phase C3: Validate Contribution

Run the FULL toolkit test suite against the modified toolkit source. ALL checks must pass -- no exceptions.

#### Step C3.1: Shellcheck

```bash
shellcheck -x -S warning .claude/toolkit/hooks/*.sh .claude/toolkit/lib/*.sh .claude/toolkit/toolkit.sh
```

Note: Run all tests from the project root using paths to the toolkit directory. Do NOT `cd` into the subtree, as bash tests use git operations that need the project-level `.git`.

#### Step C3.2: Python tests

```bash
python3 -m pytest .claude/toolkit/tests/ -v
```

#### Step C3.3: CLI integration tests

```bash
bash .claude/toolkit/tests/test_toolkit_cli.sh
```

#### Step C3.4: Manifest integration tests

```bash
bash .claude/toolkit/tests/test_manifest.sh
```

#### Step C3.5: Hook tests

```bash
bash .claude/toolkit/tests/test_hooks.sh
```

#### Step C3.6: Settings determinism

```bash
python3 -m pytest .claude/toolkit/tests/test_generate_settings.py -v
```

#### Step C3.7: Edge case verification

If the contribution modifies hooks, verify that `_config.sh` still sources correctly. If the contribution modifies agent prompts or skills, verify they contain no project-specific references by re-running the generalizability checks (H1-H7) on the final files.

#### Validation summary

Present all results in a table:

| Check | Result | Notes |
| ----- | ------ | ----- |
| Shellcheck | pass/fail | [details] |
| Python tests | pass/fail | [details] |
| CLI integration tests | pass/fail | [details] |
| Manifest integration tests | pass/fail | [details] |
| Hook tests | pass/fail | [details] |
| Settings determinism | pass/fail | [details] |
| Edge case verification | pass/fail | [details] |

If ANY check fails, inform the user:

> **Validation failed**: [list of failed checks with details]
>
> Options:
>
> 1. **Investigate** the failure and attempt to fix it
> 2. **Adjust** the contribution to avoid the failing test
> 3. **Abort** the contribution

**Ask the user** which option they prefer. Do not proceed past validation failures without the user's explicit decision.

---

### Phase C4: Prepare Submission

Generate the contribution artifacts and guide the user through the submission workflow.

#### Step C4.1: Generate patch

Create a patch file from the validated changes. The patch must have paths relative to the toolkit root (not the project root), so strip the `.claude/toolkit/` prefix:

```bash
git diff -- .claude/toolkit/ | sed 's|a/.claude/toolkit/|a/|g; s|b/.claude/toolkit/|b/|g' > /tmp/toolkit-contribution.patch
```

If a previous patch exists at that path, inform the user and offer to save to an alternative path (e.g., `/tmp/toolkit-contribution-<timestamp>.patch`).

#### Step C4.2: Write contribution description

Draft a contribution description based on the changes:

> **Contribution: [brief title]**
>
> **Summary**
>
> [1-3 sentence description of what this contribution adds or improves]
>
> **Changes**
>
> [bulleted list of specific changes, one per file]
>
> **Generalizability**
>
> All changes pass the 10-point generalizability checklist:
>
> - No project-specific paths, tool references, conventions, or defaults
> - Config-driven variability where needed
> - Backward compatible with existing configurations
> - Follows established toolkit patterns
>
> **Testing**
>
> All toolkit tests pass:
>
> - [list each test suite and result]

#### Step C4.3: Ask user for submission workflow

Present the submission options:

> How would you like to submit this contribution?
>
> 1. **Fork workflow** (recommended for external contributors): Fork the toolkit repo, push changes to a branch, and open a PR
> 2. **Direct push** (for maintainers with write access): Push changes directly to a branch on the toolkit repo
>
> Which workflow would you prefer?

**Wait for the user's choice.**

#### Step C4.4: Provide submission commands

Based on the user's choice, provide copy-pasteable commands:

**Fork workflow**:

```bash
# 1. Fork the toolkit repo on GitHub (if not already done)
# 2. Clone your fork
git clone <your-fork-url> /tmp/toolkit-contribution
cd /tmp/toolkit-contribution

# 3. Create a branch
git checkout -b contribute/<brief-description>

# 4. Apply the patch
git apply /tmp/toolkit-contribution.patch

# 5. Commit
git add -A
git commit -m "<contribution title>"

# 6. Push and open PR
git push origin contribute/<brief-description>
# Then open a PR from your fork to the upstream repo
```

**Direct push workflow** (uses `git subtree push` to extract and push):

```bash
# Option A: Use git subtree push (pushes ALL subtree changes, not just the contribution)
git subtree push --prefix=.claude/toolkit claude-toolkit contribute/<brief-description>
# Then open a PR on the toolkit repo
# Note: This creates a branch containing the full subtree history, not just your changes

# Option B: Clone the toolkit repo and apply the patch
TOOLKIT_URL=$(git remote get-url claude-toolkit)
git clone "$TOOLKIT_URL" /tmp/toolkit-direct-push
cd /tmp/toolkit-direct-push
git checkout -b contribute/<brief-description>
git apply /tmp/toolkit-contribution.patch
git add -A
git commit -m "<contribution title>"
git push origin contribute/<brief-description>
# Then open a PR on the toolkit repo
```

Note: Do NOT `cd .claude/toolkit && git checkout -b` -- the subtree is not a standalone repository and git branch operations would affect the project repo.

#### Step C4.5: Ask user to review

Present the PR title and summary:

> **Proposed PR title**: [title]
>
> **Proposed PR body**:
> [the contribution description from Step C4.2]
>
> Would you like to adjust the title or description before finalizing?

**Wait for the user to confirm or adjust before providing final commands.**

#### Step C4.6: Clean up local toolkit changes

The changes applied to `.claude/toolkit/` in Step C2.3 were needed for validation and patch generation. Now that the patch has been created, revert these local changes to avoid divergence from the upstream subtree.

**IMPORTANT**: Only revert the specific files that were part of the contribution, not ALL `.claude/toolkit/` changes (the user may have other in-progress work):

```bash
# Revert ONLY the contributed files
git checkout -- .claude/toolkit/<source_path_1>
git checkout -- .claude/toolkit/<source_path_2>
# ... one per contributed file
```

Do NOT use `git checkout -- .claude/toolkit/` as this discards ALL local changes, including unrelated work.

**Ask the user first** before reverting — they may want to keep the local changes (e.g., while waiting for the PR to be merged).

---

### Phase C5: Summary

Present a mandatory structured summary of the entire contribute flow.

The summary must include ALL of the following sections:

- **Changes proposed**: [count] files, with a brief description of each change
- **Generalizability results**: table showing all 10 checks (H1-H7, Q1-Q3) for each file with pass/fail status
- **Validation results**: table showing all 7 test suite checks and their pass/fail status
- **Submission method**: fork workflow or direct push
- **Submission instructions**: the copy-pasteable commands from Phase C4
- **Patch location**: path to the generated patch file
- **Next steps**: what the user needs to do after this flow completes (e.g., open the PR, respond to review feedback)

Example summary format:

> ## Contribution Summary
>
> ### Changes Proposed
>
> | File | Change |
> | ---- | ------ |
> | [file1] | [description] |
> | [file2] | [description] |
>
> ### Generalizability Results
>
> | File | H1 | H2 | H3 | H4 | H5 | H6 | H7 | Q1 | Q2 | Q3 |
> | ---- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- |
> | [file1] | pass | pass | pass | pass | pass | pass | pass | pass | pass | pass |
>
> ### Validation Results
>
> | Check | Result |
> | ----- | ------ |
> | Shellcheck | pass |
> | Python tests | pass |
> | CLI integration tests | pass |
> | Manifest integration tests | pass |
> | Hook tests | pass |
> | Settings determinism | pass |
> | Edge case verification | pass |
>
> ### Submission
>
> - **Method**: [fork / direct push]
> - **Patch**: `/tmp/toolkit-contribution.patch`
> - **Branch**: `contribute/<description>`
>
> ### Next Steps
>
> 1. [Execute the submission commands above]
> 2. [Open PR with the provided title and description]
> 3. [Respond to any review feedback]
> 4. Local toolkit source changes have been reverted (Step C4.6)

---

## Contribute Error Handling

| Error | Recovery |
| ----- | -------- |
| No customized files found | Inform the user that there are no candidates to contribute. Suggest using `toolkit.sh customize <path>` to take ownership of a file first, then making changes and re-running `/setup-toolkit --contribute`. |
| Generalizability gate failure | Show which specific checks failed (H1-H7) with detailed guidance on what needs to change. Offer to help revise the change to make it generic, or let the user skip the file. Do not proceed with a file that fails any hard requirement. |
| Test failures after applying changes | Present the test output and determine whether the failure is caused by the contribution or is pre-existing. **Ask the user** whether to investigate, adjust the contribution, or abort. Do not ignore test failures. |
| Toolkit source divergence | Show both the user's base version and the current toolkit source. Assess whether the changes conflict or can be merged cleanly. If ambiguous, present options (adapt, skip, abort) and **ask the user** to decide. Do not auto-merge when the result is uncertain. |

---

## Doctor Flow

This flow is executed when `--doctor` is passed. It replaces the setup phases above.

The Doctor Flow performs a deep health evaluation of the toolkit installation. It goes beyond the CLI `toolkit.sh doctor` (which checks infrastructure basics) by analyzing configuration coherence, live-testing commands, auditing dependencies and API keys, checking CLAUDE.md content, identifying optimization opportunities, and testing hook behavior in depth.

> **Relationship to `toolkit.sh doctor`**: The CLI command remains available for quick terminal/CI checks. This skill flow includes everything the CLI checks as Phase H0, then goes much deeper with AI-assisted analysis and interactive fixes.

> **User Interaction Principle**: Present all findings before applying fixes. Categorize by severity so the user can prioritize. Never auto-fix without confirmation.

### Severity System

All findings across all phases use this four-tier severity system:

| Severity | Symbol | Meaning | Action |
| -------- | ------ | ------- | ------ |
| Error | `[ERROR]` | Something is broken or misconfigured and will cause failures | Must fix (auto-fix offered where possible) |
| Warning | `[WARN]` | Potential problem that may cause unexpected behavior | Should fix (auto-fix offered where possible) |
| Optimization | `[OPT]` | Working but could be improved for better experience | Optional (auto-fix offered where possible) |
| Info | `[INFO]` | Informational observation, no action needed | No action |

Accumulate findings throughout all phases. Each finding records: severity, phase, description, and whether an auto-fix is available.

---

### Phase H0: Baseline Infrastructure

Run the existing CLI doctor command as a foundation. No point doing deep analysis if the basics are broken.

#### Step H0.1: Run CLI doctor

```bash
bash .claude/toolkit/toolkit.sh doctor
```

Capture the full output. Parse the summary line for pass/fail/warning counts.

#### Step H0.2: Handle failures

If doctor reports failures:

1. Present the failures to the user
2. Offer to auto-fix with user confirmation:

| Doctor Failure | Auto-Fix |
| -------------- | -------- |
| Missing config cache | `python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env` |
| Stale config cache | Same as above |
| Broken symlinks | `bash .claude/toolkit/toolkit.sh init --force` |
| Non-executable hooks | `chmod +x .claude/toolkit/hooks/*.sh` |
| Stale settings.json | `bash .claude/toolkit/toolkit.sh generate-settings` |
| Manifest corrupted | `bash .claude/toolkit/toolkit.sh init` |

3. After applying fixes, re-run doctor to verify resolution

#### Step H0.3: Proceed or abort

If critical failures persist after fix attempts (e.g., required tools missing, toolkit directory not found), **ask the user** whether to continue with deeper analysis or abort.

Map doctor results to the severity system: doctor failures become `[ERROR]`, doctor warnings become `[WARN]`, doctor info items become `[INFO]`.

---

### Phase H1: Configuration Coherence

Detect contradictions, staleness, and drift between the various configuration sources.

#### H1.1: Stack detection vs toolkit.toml

Run the detection script and compare detected stacks against configured stacks:

```bash
python3 .claude/toolkit/detect-project.py --project-dir .
```

Parse the JSON output. Read the configured stacks from `.claude/toolkit.toml` (`[project] stacks`).

- **Stale stack**: toolkit.toml lists a stack that detection no longer finds → `[WARN]` ("Stack '[name]' configured in toolkit.toml but not detected in project")
- **Missing stack**: Detection finds a stack not listed in toolkit.toml → `[OPT]` ("Stack '[name]' detected but not configured — add to toolkit.toml for stack-specific tooling")
- **Auto-fix available**: Offer to update `[project] stacks` in toolkit.toml to match detection

#### H1.2: Settings.json freshness

Generate what `settings.json` should contain by running the merge logic in-memory, then compare against the actual file. If they differ, identify which sections diverge (hooks, deny patterns, env vars, etc.) and report:

- Different content → `[WARN]` ("settings.json is stale — [section] differs from what generate-settings would produce")
- **Auto-fix available**: `bash .claude/toolkit/toolkit.sh generate-settings`

#### H1.3: Config cache freshness

Compare toolkit.toml mtime against toolkit-cache.env mtime. Additionally, regenerate the cache in-memory and compare content against the current file. This catches cases where the file was touched but content is wrong.

- Stale or content mismatch → `[WARN]` ("Config cache is stale or has incorrect content")
- **Auto-fix available**: `python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env`

#### H1.4: toolkit.toml commands vs detected commands

Compare the commands configured in toolkit.toml against what `detect-project.py` would produce:

| toolkit.toml key | Detection field |
| ----------------- | --------------- |
| `[hooks.post-edit-lint.linters.<ext>] cmd` | `lint.<stack>.cmd` |
| `[hooks.task-completed.gates.tests] cmd` | `test.cmd` |
| `[hooks.task-completed.gates.lint] cmd` | `lint.<stack>.cmd` |

- If toolkit.toml differs from detection AND differs from the example default → `[INFO]` (likely intentional customization)
- If toolkit.toml matches the example default but detection finds a working alternative → `[OPT]` ("Detected '[cmd]' as lint command, but toolkit.toml still uses example default '[default_cmd]'")

#### H1.5: TOML schema validation

```bash
python3 .claude/toolkit/generate-config-cache.py --validate-only --toml .claude/toolkit.toml
```

If the `--validate-only` flag is not supported, attempt cache generation and check for errors:

```bash
python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output /dev/null
```

- Validation errors → `[ERROR]` with the specific schema error message

---

### Phase H2: Command Validation (Live Testing)

Test that configured commands actually work — not just "is the binary available" but "does the command succeed when invoked."

#### H2.1: Lint command

1. Read the configured lint gate command (from `toolkit-cache.env` or by parsing `toolkit.toml`: `[hooks.task-completed.gates.lint] cmd`)
2. Extract the executable (first word of the command)
3. Check if executable exists:
   - If it is a path (contains `/`), check with `test -x <path>` — if the path references a virtual environment (e.g., `.venv/bin/ruff`) that does not exist, report `[ERROR]` ("Lint command references '.venv/bin/ruff' but '.venv/' does not exist")
   - If it is a bare command, check with `command -v <exe>`
4. If found, run `<exe> --version` to verify it works
5. Find a source file matching the gate glob pattern and run the full lint command on it
6. Classify the result:
   - Command not found → `[ERROR]` with install guidance
   - Command crashes (non-lint failure) → `[ERROR]`
   - Command finds lint issues (exit code from lint violations) → `[INFO]` ("Lint command works — found lint issues in sample file, which is expected")
   - Command passes clean → `[INFO]` ("Lint command works correctly")
7. **Auto-fix for missing venv tool**: Offer to update the command to use the system-installed version instead

#### H2.2: Test command

1. Read the configured test gate command (`[hooks.task-completed.gates.tests] cmd`)
2. If it references a Makefile target (e.g., `make test-changed`), verify the Makefile has that target:

```bash
grep -q '^test-changed:' Makefile 2>/dev/null
```

3. Run the test command with a short timeout (30s) to verify it at least starts:

```bash
timeout 30 <test-command> 2>&1 || true
```

4. Classify:
   - Command not found → `[ERROR]`
   - Makefile target missing → `[ERROR]` ("Test command 'make test-changed' references missing Makefile target")
   - Command starts but tests fail → `[INFO]` ("Test command works — some tests fail, which may be expected")
   - Command works → `[INFO]`

#### H2.3: Format commands

For each extension configured in `[hooks.post-edit-lint.linters.<ext>]`:

1. Read the `fmt` command
2. Extract the executable and check availability
3. If a `fallback` is configured, check if the fallback is available too
4. Missing formatter → `[WARN]` ("Format command for .[ext] files references '[exe]' which is not found")
5. Missing fallback when primary is missing → `[WARN]`

#### H2.4: Post-edit lint commands

Same pattern as H2.3 but for the `cmd` field in each linter extension section.

---

### Phase H3: Dependency & API Key Audit

Check that external dependencies and credentials referenced across the configuration are available.

#### H3.1: MCP server dependencies

Read `.mcp.json` and check each configured MCP server:

| Server | Dependency Check | API Key Check | If Missing |
| ------ | ---------------- | ------------- | ---------- |
| context7 | `command -v npx` | None required | `[WARN]` npx not found — context7 MCP will not work |
| playwright | `command -v npx` | None required | `[WARN]` npx not found — playwright MCP will not work |
| codex | Check codex server config | `OPENAI_API_KEY` env var set? | `[WARN]` OPENAI_API_KEY not set — codex MCP may not authenticate |

For any additional MCP servers found in `.mcp.json` that are not in the table above, check that the configured `command` is available.

- **Manual fix guidance**: Provide install commands (e.g., "Install Node.js: `brew install node`", "Set OPENAI_API_KEY: `export OPENAI_API_KEY=...`")

#### H3.2: Required, optional, and security tools

Read from the toolkit config:

- `[hooks.setup] required_tools` — each missing tool → `[ERROR]` with install guidance
- `[hooks.setup] optional_tools` — each missing tool → `[INFO]`
- `[hooks.setup] security_tools` — each missing tool → `[OPT]` with install guidance

For each missing tool, provide platform-appropriate install commands where possible:

| Tool | macOS | Linux |
| ---- | ----- | ----- |
| ruff | `pip install ruff` | `pip install ruff` |
| jq | `brew install jq` | `apt install jq` |
| gitleaks | `brew install gitleaks` | `brew install gitleaks` |
| semgrep | `pip install semgrep` | `pip install semgrep` |
| shellcheck | `brew install shellcheck` | `apt install shellcheck` |

#### H3.3: Stack-specific tool expectations

Based on the configured stacks in toolkit.toml, check for expected tools:

| Stack | Expected Tools |
| ----- | -------------- |
| python | python3, pip or pip3 |
| typescript | node, npm or npx |
| ios | xcrun, swift |

Each missing expected tool for a configured stack → `[WARN]` ("Stack 'python' is configured but 'pip3' is not found")

---

### Phase H4: CLAUDE.md Content Analysis

Check that the project's `CLAUDE.md` (at the project root) is consistent and complete. Skip this phase entirely if no project `CLAUDE.md` exists — report `[INFO]` ("No project CLAUDE.md found — consider creating one with `/setup-toolkit`") and proceed.

**Important**: Analyze the project's root `CLAUDE.md`, NOT the toolkit's own `CLAUDE.md` at `.claude/toolkit/CLAUDE.md`.

#### H4.1: Template marker detection

Read the project's `CLAUDE.md` and search for:

- Unfilled template placeholders: patterns matching `{{...}}`
- HTML comment markers from the template: `<!-- ... -->` (indicates sections not yet customized)
- Empty placeholder sections (e.g., a heading followed immediately by another heading with no content)

Each unfilled placeholder → `[OPT]` ("CLAUDE.md has unfilled placeholder: '{{PLACEHOLDER_NAME}}'")
Each template comment → `[OPT]` ("CLAUDE.md has template comment that should be replaced with project content")

#### H4.2: Command consistency with toolkit.toml

Extract command references from CLAUDE.md — look for lines inside code blocks (`` ``` `` sections) that appear to be shell commands (lines starting with common command prefixes or containing tool names).

Cross-reference extracted commands with toolkit.toml configuration:

- CLAUDE.md says `make test` but toolkit.toml test gate uses `pytest` → `[WARN]` ("CLAUDE.md references 'make test' but toolkit.toml test gate uses 'pytest' — these should be consistent")
- CLAUDE.md says `ruff check` but toolkit.toml uses `.venv/bin/ruff check` → `[INFO]` (minor path difference)

This check is heuristic. Report only clear contradictions, not stylistic differences.

#### H4.3: Dead command detection

For each command found in CLAUDE.md code blocks, do a quick availability check:

1. Extract the executable (first word)
2. If it is `make <target>`, check if the Makefile has that target
3. Otherwise, check `command -v <exe>`

Each unreachable command → `[WARN]` ("CLAUDE.md references '[command]' but it is not available")

Do not flag commands that are clearly examples or placeholders (e.g., lines with `<placeholder>` syntax).

#### H4.4: Missing toolkit section

If CLAUDE.md exists but does not mention "toolkit" anywhere (case-insensitive search), report:

- `[OPT]` ("CLAUDE.md does not mention the toolkit — consider adding a section. Run `/setup-toolkit` to add one automatically.")

---

### Phase H5: Optimization Opportunities

Identify configuration that works but could be improved.

#### H5.1: Default values that should be customized

Read `.claude/toolkit.toml` and compare key fields against the example template defaults (`templates/toolkit.toml.example`):

| Field | Example Default | Finding if Unchanged |
| ----- | --------------- | -------------------- |
| `[project] name` | `"my-project"` | `[OPT]` "Project name is still the example default 'my-project'" |
| `[hooks.subagent-context] critical_rules` | `[]` | `[OPT]` "No critical rules configured — subagents will not receive project-specific rules" |
| `[hooks.subagent-context] available_tools` | `[]` | `[OPT]` "No available tools configured for subagent context" |
| `[hooks.subagent-context] stack_info` | `""` | `[OPT]` "No stack info configured — subagents will not know the project's tech stack" |
| `[toolkit] remote_url` | `"git@github.com:user/claude-toolkit.git"` | `[OPT]` "Toolkit remote URL is still the example placeholder" |

**Auto-fix available**: For `[project] name`, offer to set it to the detected project name (from `detect-project.py`). For `stack_info`, offer to auto-generate from configured stacks.

#### H5.2: Auto-approve path relevance

Read the configured auto-approve write paths and check each glob pattern against the actual project structure:

```bash
# For each pattern like "*/app/*", check if the directory exists
ls -d app/ 2>/dev/null
```

Patterns that do not match any existing directory → `[INFO]` ("Auto-approve path pattern '*/app/*' does not match any directory in this project — it will have no effect until an 'app/' directory is created")

This is informational only — the paths might be created later.

#### H5.3: Missing stack overlays

For each stack detected by `detect-project.py`, check if a corresponding stack overlay JSON exists at `.claude/toolkit/templates/stacks/<stack>.json`:

- Stack detected but no overlay file → `[INFO]` ("No stack overlay found for detected stack '[name]' — the toolkit does not yet have built-in support for this stack")
- Stack configured in toolkit.toml but overlay file missing → `[WARN]` ("Stack '[name]' configured in toolkit.toml but no overlay file exists at templates/stacks/[name].json")

#### H5.4: Customized file drift

Read the manifest at `.claude/toolkit-manifest.json`. For each file marked as customized, compare the manifest's recorded `toolkit_hash` against the current toolkit source hash:

```bash
shasum -a 256 .claude/toolkit/<source_path> | cut -d' ' -f1
```

If the hash differs from the manifest's `toolkit_hash`, the toolkit source has changed since customization (drift):

- `[OPT]` ("Customized file '[path]' has upstream drift — the toolkit source was updated since you customized it. Review upstream changes with `/setup-toolkit --update` or re-customize from the new source.")

If the manifest does not exist, skip this check and report `[WARN]` ("Manifest not found — cannot check for customization drift. Run `toolkit.sh init` to create a manifest.")

---

### Phase H6: Deep Hook Health

Test hooks more thoroughly than the CLI doctor's 2-sample test, and check for potential conflicts between hooks.

#### H6.1: Extended guard hook testing

Test `guard-destructive.sh` with multiple sample inputs:

| Input | Expected | Category |
| ----- | -------- | -------- |
| `{"tool_name":"Bash","tool_input":{"command":"ls -la"}}` | exit 0 (allow) | Safe command |
| `{"tool_name":"Bash","tool_input":{"command":"git push origin main --force"}}` | deny JSON | Destructive git |
| `{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}` | deny JSON | Destructive git |
| `{"tool_name":"Bash","tool_input":{"command":"rm -rf src/"}}` | deny JSON | Destructive rm |

Test `guard-sensitive-writes.sh` with:

| Input | Expected | Category |
| ----- | -------- | -------- |
| `{"tool_name":"Write","tool_input":{"file_path":"src/main.py"}}` | exit 0 (allow) | Safe write |
| `{"tool_name":"Write","tool_input":{"file_path":".env"}}` | deny JSON | Secret file |
| `{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json"}}` | deny JSON | Toolkit config |

Test `auto-approve-safe.sh` with:

| Input | Expected | Category |
| ----- | -------- | -------- |
| `{"tool_name":"Read","tool_input":{"file_path":"README.md"}}` | approve JSON | Safe read |
| `{"tool_name":"Bash","tool_input":{"command":"git status"}}` | approve JSON | Safe bash |

For each test, pipe the sample input to the hook via stdin with `CLAUDE_PROJECT_DIR` set:

```bash
echo '<input_json>' | CLAUDE_PROJECT_DIR="$(pwd)" bash .claude/toolkit/hooks/<hook>.sh
```

Check the exit code and stdout. Each unexpected result → `[ERROR]` ("Hook '[hook]' returned unexpected result for '[category]' input: expected [expected], got exit code [actual]")

#### H6.2: Hook conflict detection

Analyze the logical relationship between guard hooks and auto-approve:

1. Read the auto-approve write paths from the toolkit config
2. Read the sensitive-write guard's deny patterns (from the hook source code — look for patterns like `.env`, `credentials`, `.ssh`, `settings.json`)
3. Check if any auto-approve pattern would match a file that the guard would deny

For example, if auto-approve includes `*/.claude/*` and guard-sensitive-writes denies `.claude/settings.json`, that is a potential conflict where the auto-approve would approve a write that the guard would subsequently deny.

Each conflict found → `[WARN]` ("Potential conflict: auto-approve pattern '[pattern]' overlaps with guard-sensitive-writes deny pattern for '[file]' — the guard takes precedence, but the auto-approve entry is misleading")

#### H6.3: Hook timeout appropriateness

Read hook timeouts from `.claude/settings.json` (the `hooks` array, where each hook entry may have a `timeout` field):

- Guard hooks (names starting with `guard-`) with timeout > 30000ms → `[INFO]` ("Guard hook '[name]' has a [N]s timeout — guards should respond quickly")
- Task-completed gates with timeout < 60000ms → `[INFO]` ("Task-completed gate has a [N]s timeout — tests may need more time")
- Any hook with timeout > 300000ms → `[INFO]` ("Hook '[name]' has a [N]s timeout — this is unusually long")

---

### Phase H7: Summary & Fix

Present all accumulated findings and offer fixes.

#### Step H7.1: Findings summary table

Present all findings grouped by severity:

> ## Doctor Report
>
> ### Errors ([count])
>
> | # | Phase | Finding | Fix Available |
> | - | ----- | ------- | ------------- |
> | 1 | H2 | Lint command '.venv/bin/ruff' not found — .venv/ does not exist | Yes |
> | 2 | H3 | Required tool 'jq' not found | Manual: `brew install jq` |
>
> ### Warnings ([count])
>
> | # | Phase | Finding | Fix Available |
> | - | ----- | ------- | ------------- |
> | 1 | H1 | settings.json is stale — hooks section differs | Yes |
> | 2 | H4 | CLAUDE.md references 'make test' but toolkit.toml uses 'pytest' | Manual |
>
> ### Optimizations ([count])
>
> | # | Phase | Finding | Fix Available |
> | - | ----- | ------- | ------------- |
> | 1 | H5 | Project name still 'my-project' | Yes |
> | 2 | H5 | No critical rules configured for subagent context | Manual |
>
> ### Info ([count])
>
> | # | Phase | Finding |
> | - | ----- | ------- |
> | 1 | H3 | Gemini CLI not installed (optional) |
> | 2 | H5 | Auto-approve path '*/app/*' matches no directory |
>
> **Total**: [N] errors, [N] warnings, [N] optimizations, [N] info

If there are zero findings across all categories, report:

> ## Doctor Report
>
> **All clear.** No issues, warnings, or optimization opportunities found. The toolkit installation is healthy.

#### Step H7.2: Batch fix offer

Categorize all fixable findings into three groups:

**Auto-fixable** (can be applied safely with a single command):

- Regenerate config cache
- Regenerate settings.json
- Fix broken symlinks
- Fix hook permissions
- Update stacks list in toolkit.toml

**Interactive** (need user input to determine the correct fix):

- Update project name (from example default to detected name)
- Resolve command contradictions between CLAUDE.md and toolkit.toml
- Update lint/test commands to match detected alternatives
- Generate stack_info from configured stacks

**Manual** (require user action outside the session):

- Install missing tools (provide install commands)
- Set API keys (provide export commands)
- Fill in CLAUDE.md placeholders (point to specific sections)
- Review customized files with upstream drift

Present the auto-fixable items first:

> **Auto-fix available for [N] issues:**
>
> 1. Regenerate config cache (toolkit-cache.env stale)
> 2. Regenerate settings.json (out of date)
> 3. Fix 2 broken symlinks
>
> Apply all auto-fixes? [yes / no / select individually]

If the user chooses "select individually", present each fix one at a time.

Then step through interactive fixes one by one, presenting the choice and waiting for user input.

Finally, list manual fixes:

> **Manual action needed:**
>
> - Install gitleaks: `brew install gitleaks`
> - Set OPENAI_API_KEY environment variable for codex MCP
> - Fill in CLAUDE.md placeholder: {{PROJECT_DESCRIPTION}}

#### Step H7.3: Post-fix verification

After applying any fixes:

1. Re-run `bash .claude/toolkit/toolkit.sh validate` to confirm fixes worked
2. If any fixes modified `toolkit.toml`, regenerate the config cache
3. Report the post-fix results:

> **Post-fix verification**: [N]/[N] fixes applied successfully. Validation: [passed/failed].

If validation still reports issues after fixes, present the remaining issues.

#### Step H7.4: No-commit policy

Unlike the Setup and Update flows, the Doctor flow does NOT commit changes automatically. Config file modifications should be reviewed by the user first.

List all modified files at the end:

> **Modified files** (not committed):
>
> - `.claude/toolkit.toml` (updated stacks, project name)
> - `.claude/toolkit-cache.env` (regenerated)
> - `.claude/settings.json` (regenerated)
>
> Review the changes and commit when ready.

---

## Doctor Error Handling

| Error | Recovery |
| ----- | -------- |
| `toolkit.sh doctor` fails entirely | Report `[ERROR]` with the error output. Ask user whether to continue with deeper analysis or abort. |
| `detect-project.py` fails | Skip H1.1 and H1.4 (stack and command comparison). Report `[WARN]` ("Detection script failed — some coherence checks were skipped"). Continue with remaining phases. |
| toolkit.toml parse error | Report `[ERROR]` in H1.5. Skip H1.4 and H5.1 (these require parsed TOML). Continue with remaining phases. |
| CLAUDE.md does not exist | Skip Phase H4 entirely. Report `[INFO]` ("No project CLAUDE.md found"). |
| `.mcp.json` does not exist | Skip H3.1. Report `[INFO]` ("No .mcp.json found — run `toolkit.sh generate-settings` to create one"). |
| Hook sample input test crashes | Report `[ERROR]` for the specific hook. Continue testing remaining hooks. |
| Manifest not found | Skip H5.4 (drift check). Report `[WARN]` ("Manifest not found — cannot check for customization drift"). |
| settings.json does not exist | Skip H1.2 and H6.3 (settings freshness and timeout checks). Report `[WARN]`. |
