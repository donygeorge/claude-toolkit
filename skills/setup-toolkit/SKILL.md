---
name: setup-toolkit
description: Detect project stacks and commands, validate config, generate toolkit.toml and CLAUDE.md. Handles fresh setup, partial installs, and reconfiguration.
argument-hint: "[--reconfigure] [--update [version]] [--contribute]"
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
| `--contribute` | Run the Contribute Flow instead of the setup flow. Identifies customized files with generic improvements, evaluates them against a 10-point generalizability checklist, prepares clean changes for the toolkit repo, validates with the full test suite, and generates submission instructions (patch or PR). |

---

## Execution Flow

> **Routing**: If `--update` was passed, skip the setup phases below and jump directly to the [Update Flow](#update-flow) section. If `--contribute` was passed, skip the setup phases below and jump directly to the [Contribute Flow](#contribute-flow) section.

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

If the update command succeeds with a message like "Already up to date" and no files changed:

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
python3 -c "import json; json.load(open('.claude/toolkit-manifest.json'))"
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

#### Step C2.3: Apply changes to toolkit source

For each approved file (with divergence resolved), apply the changes to the toolkit source files:

```bash
# Copy the approved changes to .claude/toolkit/<source_path>
```

After applying all changes, show the final prepared changes. Note: `.claude/toolkit` is a subtree, not a separate repository -- always run git commands from the project root:

```bash
git diff -- .claude/toolkit/
```

> **Prepared changes for contribution**:
>
> ```diff
> [full diff of all changes applied to toolkit source]
> ```
>
> Please review these changes. Are they ready for validation?

If the diff is empty, the changes may not have been applied correctly. Investigate before proceeding.

**Wait for user confirmation before proceeding to validation.**

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
# Option A: Use git subtree push
git subtree push --prefix=.claude/toolkit claude-toolkit contribute/<brief-description>
# Then open a PR on the toolkit repo

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

---

## Contribute Error Handling

| Error | Recovery |
| ----- | -------- |
| No customized files found | Inform the user that there are no candidates to contribute. Suggest using `toolkit.sh customize <path>` to take ownership of a file first, then making changes and re-running `/setup-toolkit --contribute`. |
| Generalizability gate failure | Show which specific checks failed (H1-H7) with detailed guidance on what needs to change. Offer to help revise the change to make it generic, or let the user skip the file. Do not proceed with a file that fails any hard requirement. |
| Test failures after applying changes | Present the test output and determine whether the failure is caused by the contribution or is pre-existing. **Ask the user** whether to investigate, adjust the contribution, or abort. Do not ignore test failures. |
| Toolkit source divergence | Show both the user's base version and the current toolkit source. Assess whether the changes conflict or can be merged cleanly. If ambiguous, present options (adapt, skip, abort) and **ask the user** to decide. Do not auto-merge when the result is uncertain. |
