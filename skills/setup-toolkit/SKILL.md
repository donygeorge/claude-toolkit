---
name: setup-toolkit
description: Detect project stacks and commands, validate config, generate toolkit.toml and CLAUDE.md. Handles fresh setup, partial installs, and reconfiguration.
argument-hint: "[--reconfigure] [--update [version]]"
user-invocable: true
disable-model-invocation: true
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

---

## Execution Flow

> **Routing**: If `--update` was passed, skip the setup phases below and jump directly to the [Update Flow](#update-flow) section.

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

If there are uncommitted changes (especially in `.claude/toolkit/`), warn the user:

> There are uncommitted changes in your working tree. Updating the toolkit may cause conflicts with these changes.

List the changed files. **Ask the user**: commit or stash changes first, or proceed anyway?

**Do NOT proceed until the user confirms.**

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

Display a version comparison to the user:

> **Current version**: [current_version]
> **Available versions**: [list of tags, newest first]
> **Latest release**: [newest tag]

If `--update` was called with a specific version (e.g., `--update v1.3.0`), confirm that the requested version exists in the tag list.

#### Step U1.3: Show CHANGELOG entries

Display the CHANGELOG entries between the current version and the target version:

```bash
cat .claude/toolkit/CHANGELOG.md
```

Extract and display only the entries between the current and target versions. Summarize key changes (new features, bug fixes, breaking changes).

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

#### Step U2.2: Check for conflicts

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

1. For each conflicted file, read the file and analyze the conflict markers
2. Show the proposed resolution (which side to keep, or how to merge)
3. **Ask the user to confirm** the resolution for each file before applying
4. After resolving, mark the file as resolved: `git add [resolved_file]`
5. Once all conflicts are resolved, complete the subtree merge: `git commit --no-edit`

Note: This commit completes the subtree merge only. The Phase U5 commit will capture additional post-update changes (settings regeneration, drift resolution, manifest updates).

If the user chooses to abort:

```bash
git merge --abort
```

Inform the user the update was aborted and no changes were made.

---

### Phase U3: Post-Update Validation

Run all 10 validation checks to ensure the update did not break anything. For each failing check, attempt up to 3 automatic fix attempts before escalating to the user.

#### Check 1: Shellcheck

```bash
shellcheck -x -S warning .claude/toolkit/hooks/*.sh .claude/toolkit/lib/*.sh .claude/toolkit/toolkit.sh
```

If issues are found: these are in toolkit code and should not be modified locally. Note them and report to the user.

#### Check 2: Toolkit validate

```bash
bash .claude/toolkit/toolkit.sh validate
```

If issues are found: attempt auto-fix (init --force, chmod +x). Retry up to 3 times.

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

```bash
bash .claude/toolkit/toolkit.sh validate
```

Specifically check the symlink section of the output. If broken symlinks exist:

```bash
bash .claude/toolkit/toolkit.sh init --force
```

Retry up to 3 times.

#### Check 6: Manifest integrity

Check that the manifest file exists and is valid:

```bash
python3 -c "import json; json.load(open('toolkit-manifest.json'))"
```

If missing or invalid, re-initialize:

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

```bash
bash .claude/toolkit/toolkit.sh status
```

Identify all customized files with drift (where the toolkit source has changed since the file was customized).

If no drift is detected, skip to Phase U5.

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
# Update manifest hash for this file to suppress future drift warnings
```

**Merge upstream changes**: Perform an intelligent merge of the user's customizations with the upstream changes. Show the merged result to the user and **ask for confirmation** before writing the file. If the merge is ambiguous, present options and let the user decide.

**Revert to managed**: Replace the customized file with the toolkit source. If the file was a broken symlink, restore the symlink. Update the manifest to mark the file as "managed" again:

```bash
# For agents/rules: restore symlink
ln -sf ../toolkit/agents/[file] .claude/agents/[file]
# For skills: copy from toolkit source
cp .claude/toolkit/skills/[skill]/[file] .claude/skills/[skill]/[file]
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

Stage all changed files individually. Do NOT use `git add .` or `git add -A`.

```bash
git add .claude/toolkit/
git add .claude/settings.json
git add .claude/toolkit-cache.env
git add .mcp.json
git add toolkit-manifest.json
```

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

## Update Error Handling

| Error | Recovery |
| ----- | -------- |
| `git fetch claude-toolkit` fails | Check that the `claude-toolkit` remote exists: `git remote -v`. If missing, ask the user for the remote URL and add it: `git remote add claude-toolkit <url>`. Retry the fetch. |
| Subtree pull conflict | Detect conflicted files with `git diff --diff-filter=U --name-only`. Present conflicts to user. Offer automatic resolution or abort (`git merge --abort`). See Phase U2 for details. |
| Validation failure (any of 10 checks) | Attempt auto-fix up to 3 times per check. If still failing, present the error details to the user and ask how to proceed. Do not silently ignore validation failures. |
| Drift merge failure | If an intelligent merge fails or produces ambiguous results, show both versions to the user and ask them to choose or manually edit. Do not apply an uncertain merge automatically. |
