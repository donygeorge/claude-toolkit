---
name: toolkit-update
description: Use when updating the toolkit to a new version.
argument-hint: "[version]"
user-invocable: true
---

# Toolkit Update Skill

Perform an LLM-guided toolkit update with pre-flight checks, version preview, conflict resolution, drift management, post-update validation, and a structured summary with commit.

> **User Interaction Principle**: When in doubt, ask. Never make assumptions about which version to pull, how to resolve conflicts, or what to do with drift. Present options and let the user decide.

## Usage

```bash
/toolkit-update            # Update toolkit to latest release
/toolkit-update v1.3.0     # Update toolkit to a specific version
```

## When to Use

- A new toolkit version has been released and you want to upgrade
- You need to pull specific fixes or features from a newer toolkit version
- The toolkit remote has updates and you want to review and apply them

**When NOT to use** (the skill will detect these and redirect):

- For first-time setup → use `/toolkit-setup` instead
- To diagnose issues without updating → use `/toolkit-doctor` instead
- To regenerate settings after editing toolkit.toml → run `bash .claude/toolkit/toolkit.sh generate-settings`

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Create rollback point before updating** | Always ensure there is a clean commit before the update so the user can revert if needed. |
| **2. Validate after update** | Run all 10 validation checks after the update; do not skip any even if the update appears clean. |
| **3. Resolve drift in customized files** | After updating, check every customized file for upstream drift and present resolution options to the user. |
| **4. Never force-overwrite customizations** | Customized files are the user's property; always ask before modifying them, even during conflict resolution. |

---

## Execution Flow

Execute these phases in order. Do NOT skip phases.

### Phase U0: Pre-flight

Verify the project is in a healthy state before attempting an update.

#### Step U0.1: Check toolkit installation

```bash
ls .claude/toolkit/toolkit.sh
```

If the file does not exist, the toolkit is not installed. Tell the user:

> The toolkit is not installed in this project. Use `/toolkit-setup` to install and configure it first.

**Stop here** if the toolkit is not installed.

Check if toolkit.toml exists:

```bash
ls .claude/toolkit.toml
```

If toolkit.toml does not exist, the toolkit was installed but never configured. Tell the user:

> The toolkit subtree exists but has not been configured yet. Use `/toolkit-setup` to complete the initial configuration before updating.

**Stop here** if toolkit.toml does not exist.

#### Step U0.2: Check toolkit status

```bash
bash .claude/toolkit/toolkit.sh status
```

Review the output. Note the current toolkit version and any reported issues.

#### Step U0.3: Validate current installation

```bash
bash .claude/toolkit/toolkit.sh validate
```

If validation reports issues, inform the user:

> Validation found issues with the current installation. These should be resolved before updating.

List each issue. Attempt to fix automatically (e.g., broken symlinks via `toolkit.sh init --force`, stale cache via regeneration). Re-run validation after fixes. If issues persist, **ask the user** whether to proceed with the update anyway or abort.

#### Step U0.4: Check for uncommitted changes

```bash
git status --porcelain
git diff --stat
```

If there are uncommitted changes, warn the user:

> There are uncommitted changes in your working tree. Updating the toolkit may cause conflicts with these changes.

List the changed files. If any uncommitted changes are inside `.claude/toolkit/`, **strongly recommend** committing or stashing before proceeding -- subtree pull requires a clean subtree directory and will fail or produce corrupt merges if the subtree has local modifications.

**Ask the user**: commit or stash changes first, or proceed anyway?

**Do NOT proceed until the user confirms.**

#### Step U0.5: Check toolkit remote

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

If the fetch fails, see the [Error Handling](#error-handling) table.

#### Step U1.2: Show available versions

```bash
git tag -l 'v*' --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -10
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

If `/toolkit-update` was called with a specific version (e.g., `/toolkit-update v1.3.0`), confirm that the requested version exists in the tag list. If the requested version is not found:

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

Replace `[version]` with the user's chosen version tag (e.g., `v1.3.0`) — the version must start with `v`. Omit the version to update to the latest semver release tag. Use `--latest` to pull from the `main` branch instead of a release tag.

#### Step U2.2: Check if already up to date

After the update command completes, check whether anything actually changed:

```bash
git diff HEAD~1 --stat -- .claude/toolkit/
```

If the update command output says "Already up to date" or if no toolkit files changed (empty diff):

> The toolkit is already at the target version. No changes were made.

**Skip phases U3-U5 and end the update flow.**

Note: Use `-- .claude/toolkit/` to scope the diff to toolkit files only. The subtree pull creates a merge commit, so `HEAD~1` compares against the first parent (pre-merge state).

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

#### Check 2: Toolkit validate (includes symlink health and settings protection)

```bash
bash .claude/toolkit/toolkit.sh validate
```

Review the full output, paying special attention to:

- **Symlink section**: If broken symlinks exist, run `bash .claude/toolkit/toolkit.sh init --force`.
- **Settings protection section**: If validate warns about "project-specific settings but no settings-project.json", this means the project had custom settings that aren't in the project overlay. The update command now auto-preserves these, but if the warning appears, fix it immediately:

  ```bash
  cp .claude/settings.json.pre-toolkit .claude/settings-project.json
  bash .claude/toolkit/toolkit.sh generate-settings
  ```

If other issues are found, attempt auto-fix (init --force, chmod +x). Retry up to 3 times.

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

Run the project's configured test command (from `[hooks.task-completed.gates.tests] cmd` in toolkit.toml):

```bash
# Run the project's test command as configured in toolkit.toml
```

If tests fail: determine whether the failure is related to the toolkit update or a pre-existing issue. **Ask the user** if the failure is unclear or requires a judgment call.

#### Check 10: Project lint

Run the project's configured lint command (from `[hooks.task-completed.gates.lint] cmd` in toolkit.toml):

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
git add .claude/settings.json
git add .mcp.json
git add .claude/toolkit-manifest.json
```

Note: Files inside `.claude/toolkit/` were already committed by the subtree pull merge commit — do NOT re-stage them. Only stage files outside the subtree that were modified during post-update steps.

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

## Rollback

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

**NEVER use `git reset --hard`** -- always use `git revert` to preserve history. Only the user can authorize destructive git operations.

---

## Error Handling

| Error | Recovery |
| ----- | -------- |
| `git fetch claude-toolkit` fails | Check that the `claude-toolkit` remote exists: `git remote -v`. If missing, ask the user for the remote URL and add it: `git remote add claude-toolkit <url>`. Retry the fetch. |
| Subtree pull conflict | Detect conflicted files with `git diff --diff-filter=U --name-only`. Present conflicts to user. Offer automatic resolution or abort (`git merge --abort`). See Phase U2 for details. |
| Validation failure (any of 10 checks) | Attempt auto-fix up to 3 times per check. If still failing, present the error details to the user and ask how to proceed. Do not silently ignore validation failures. |
| Drift merge failure | If an intelligent merge fails or produces ambiguous results, show both versions to the user and ask them to choose or manually edit. Do not apply an uncertain merge automatically. |
