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

## Flags

| Flag | Effect |
| ---- | ------ |
| `[version]` | Specific version tag to update to (e.g., `v1.3.0`). Must start with `v`. |
| `--latest` | Pull from the `main` branch instead of the latest semver release tag. Use for unreleased changes. |
| `--force` | Skip the uncommitted-changes check for `.claude/toolkit/`. Use when you know local subtree changes can be overwritten. |

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

#### Step U0.0: Prerequisite tool checks

Verify required tools are available:

```bash
git --version
jq --version
python3 --version
```

If `git` is not found, inform the user:

> `git` is required for fetch, subtree pull, and commit operations. Install it:
>
> - macOS: `xcode-select --install`
> - Ubuntu/Debian: `sudo apt-get install git`

**Stop here** if git is missing.

If `jq` is not found, inform the user:

> `jq` is required for manifest and settings operations during post-update steps. Install it:
>
> - macOS: `brew install jq`
> - Ubuntu/Debian: `sudo apt-get install jq`

**Stop here** if jq is missing.

If `python3` is not found, inform the user:

> `python3 3.11+` is required for settings generation and config cache refresh. Install it from [python.org](https://python.org) or via your package manager.

**Stop here** if python3 is missing.

If `python3` is found, verify the version is 3.11+ (required for `tomllib`):

```bash
python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
```

If the version is below 3.11, inform the user:

> Python [version] is installed but the toolkit requires 3.11+ for `tomllib` support. Please upgrade Python.

**Stop here** if Python is below 3.11.

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

Note: If multiple Claude Code sessions are open for this project, close them before updating to avoid file conflicts during the subtree pull and settings regeneration.

```bash
git status --porcelain
git diff --stat
```

If there are uncommitted changes, warn the user:

> There are uncommitted changes in your working tree. Updating the toolkit may cause conflicts with these changes.

List the changed files. If any uncommitted changes are inside `.claude/toolkit/`, **strongly recommend** committing or stashing before proceeding -- subtree pull requires a clean subtree directory and will fail or produce corrupt merges if the subtree has local modifications.

Note: The CLI's `toolkit.sh update` command checks for uncommitted `.claude/toolkit/` changes and refuses to proceed unless `--force` is passed. If the user explicitly wants to discard local subtree changes, they can use `--force`.

**Ask the user**: commit or stash changes first, use `--force` to bypass, or abort?

If the user chooses `--force`, remember this choice and pass the `--force` flag to the `toolkit.sh update` command in Phase U2 Step U2.1.

**Do NOT proceed until the user confirms.**

#### Step U0.5: Check toolkit remote

```bash
git remote get-url claude-toolkit 2>/dev/null
```

If the remote does not exist, inform the user:

> The git remote `claude-toolkit` is not configured. This is required for updates.
>
> Please provide the toolkit repository URL so I can add it. For example:
>
> ```bash
> git remote add claude-toolkit git@github.com:<org>/claude-toolkit.git
> ```
>
> Or for HTTPS: `git remote add claude-toolkit https://github.com/<org>/claude-toolkit.git`

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

Read the current toolkit version using the Read tool on `.claude/toolkit/VERSION`.

If the VERSION file does not exist or is empty, display the current version as "unknown" and note this to the user.

Display a version comparison to the user:

> **Current version**: [current_version]
> **Available versions**: [list of tags, newest first]
> **Latest release**: [newest tag]

If the user has requested a specific version AND the current version is known, compare them. If the target version is older than the current version, warn:

> The target version `[target]` is older than the current version `[current]`. This is a **downgrade**. Downgrades may remove features or reintroduce fixed bugs. Proceed anyway?

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

Read the CHANGELOG using the Read tool on `.claude/toolkit/CHANGELOG.md`. Extract and display only the entries between the current and target versions. Summarize key changes (new features, bug fixes, breaking changes).

If the current version is "unknown" (VERSION file missing or empty), show only the entries for the target version rather than attempting a range extraction. Inform the user that the current version could not be determined.

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

Replace `[version]` with the user's chosen version tag (e.g., `v1.3.0`). The CLI parser recognizes version arguments by matching the `v*` pattern — arguments starting with `v` are treated as version tags, while arguments without the `v` prefix are treated as unknown options and rejected. Omit the version to update to the latest semver release tag. Use `--latest` to pull from the `main` branch instead of a release tag.

If the user provides a version without the `v` prefix, prepend it automatically (e.g., `1.3.0` becomes `v1.3.0`) so the CLI recognizes it as a version argument.

#### Step U2.2: Check if already up to date

After the update command completes, check whether anything actually changed. The primary signal is the **command output** from Step U2.1, not a diff:

1. **Check the subtree pull output**: If it contains "Already up to date" (or "Already up-to-date" on older git versions), no merge commit was created and `HEAD` is unchanged.
2. **Locale fallback**: If git is configured for a non-English locale, the "Already up to date" message may appear in another language. As a secondary check, compare `HEAD` before and after the pull — if they are the same commit hash, no update occurred regardless of the output language.
3. **If the output does NOT indicate "already up to date" AND `HEAD` changed**, a merge commit was created. Verify changes:

```bash
git diff HEAD~1 --stat -- .claude/toolkit/
```

If the update command output says "Already up to date" or if no toolkit files changed (empty diff):

> The toolkit is already at the target version. No changes were made.

**Skip phases U3-U5 and end the update flow.**

**Important**: Only use `git diff HEAD~1` if the subtree pull actually created a new merge commit. If the pull said "Already up to date", no merge commit exists and `HEAD~1` would compare against an unrelated previous commit, producing misleading results. Always check the command output first.

Note: Use `-- .claude/toolkit/` to scope the diff to toolkit files only. The subtree pull creates a merge commit, so `HEAD~1` compares against the first parent (pre-merge state). If you are retrying after a failed update attempt that was resolved (e.g., conflicts were merged and committed), `HEAD~1` may not point to the pre-update state. In that case, use `git log --oneline -5` to find the correct base commit for comparison.

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
- **Settings protection section**: If validate warns about "project-specific settings but no settings-project.json", this means the project had custom settings that aren't in the project overlay. The update command auto-preserves these for **legacy installs without settings-project.json only**. If settings-project.json already existed before the update, the preservation step is skipped — but first verify it is valid JSON (`python3 -c "import json; json.load(open('.claude/settings-project.json'))"`) since a corrupt file would silently lose project settings. If the warning appears, fix it immediately:

  ```bash
  cp .claude/settings.json.pre-toolkit .claude/settings-project.json
  bash .claude/toolkit/toolkit.sh generate-settings
  ```

If other issues are found, attempt auto-fix (init --force, chmod +x). Retry up to 3 times.

#### Check 3: Generate settings

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

Note: The `generate-settings` command internally regenerates the config cache (`toolkit-cache.env`) before producing `settings.json` and `.mcp.json`. Check 8 (explicit config cache regeneration) serves as a secondary verification — if it fails there, the TOML may have schema issues that `generate-settings` masked.

If this fails: check toolkit.toml for compatibility with the new toolkit version. The update may have introduced new config keys or changed schema validation. Read the error output carefully. **Ask the user** if the error is unclear.

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

Check for broken symlinks specifically — `ls -la` shows the link targets, but to programmatically detect broken links, check each symlink:

```bash
for link in .claude/agents/*.md .claude/rules/*.md; do
  [ -L "$link" ] && [ ! -e "$link" ] && echo "Broken: $link"
done
```

If any symlink is broken:

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

Note: Check 3 (generate-settings) already regenerates the cache internally. This explicit regeneration serves as a verification step — if it fails here, the TOML may have schema issues that Check 3 masked. It also ensures the cache file timestamp is fresh for subsequent mtime-based staleness checks by hooks.

#### Check 9: Project test suite

Read the test command from `.claude/toolkit.toml` at `[hooks.task-completed.gates.tests] cmd`. If no test command is configured (key absent or empty), skip this check.

Run the configured test command with the Bash tool's `timeout` parameter set to 60000 (60 seconds) to avoid blocking the update on slow test suites. If the command times out after producing output, treat it as "starts correctly." If tests fail: determine whether the failure is related to the toolkit update or a pre-existing issue. **Ask the user** if the failure is unclear or requires a judgment call.

#### Check 10: Project lint

Read the lint command from `.claude/toolkit.toml` at `[hooks.task-completed.gates.lint] cmd`. If no lint command is configured (key absent or empty), skip this check.

Run the configured lint command. If lint fails: determine whether the failure is related to the toolkit update or a pre-existing issue. **Ask the user** if the failure is unclear.

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

Then, for each customized file reported by status, check for drift:

**For agents and rules**: Compare the manifest's recorded `toolkit_hash` against the current toolkit source hash:

```bash
shasum -a 256 .claude/toolkit/<source_path>
```

If the hash differs from what the manifest records, there is drift — the toolkit source changed since the file was customized.

**For skills**: The manifest now stores `toolkit_hash` for skills (hash of SKILL.md). Compare it the same way as agents/rules. If the manifest lacks a `toolkit_hash` for a skill (legacy manifest), fall back to direct file comparison. **First check if the toolkit source directory AND SKILL.md still exist** — if the entire directory was deleted upstream, or SKILL.md is missing, the skill was removed from the toolkit.

```bash
# Check directory and SKILL.md existence
ls -d .claude/toolkit/skills/<name>/ 2>/dev/null
ls .claude/toolkit/skills/<name>/SKILL.md 2>/dev/null
```

If the toolkit source directory or SKILL.md does NOT exist, the skill was removed upstream in this update. Inform the user:

> Skill `[name]` was removed from the toolkit in this update. Your customized version in `.claude/skills/[name]/` is preserved but will no longer receive upstream updates. You may keep it as a standalone custom skill or delete it.

Skip drift checking for this skill and move to the next one.

If the toolkit source file exists, compare it against the customized version:

```bash
diff .claude/skills/<name>/SKILL.md .claude/toolkit/skills/<name>/SKILL.md
```

If the files differ, drift exists. Check all files in the skill directory, not just `SKILL.md` (some skills have companion files like `output-schema.json`).

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

If there are **3 or more drifted files**, first offer bulk options:

> **[N] files have upstream changes.** How would you like to proceed?
>
> 1. **Revert all to managed** -- discard all customizations, use new toolkit versions (most common)
> 2. **Keep all customizations** -- preserve all your versions, ignore upstream changes
> 3. **Review individually** -- choose per file (keep, merge, or revert)

If the user chooses option 1 (revert all), run:

```bash
bash .claude/toolkit/toolkit.sh update --revert-all
```

If the user chooses option 2 (keep all), update `toolkit_hash` for each drifted file to the current toolkit source hash so drift is no longer reported.

If the user chooses option 3, or if there are fewer than 3 drifted files, ask **per file**:

> How would you like to handle this file?
>
> 1. **Keep customization** -- preserve your version, ignore upstream changes
> 2. **Merge upstream changes** -- intelligently merge both sets of changes
> 3. **Revert to managed** -- discard your customizations and use the new toolkit version

**Wait for the user's choice.**

#### Step U4.4: Apply resolution

Based on the user's choice:

**Keep customization**: No file changes needed. For agents and rules, update the manifest to record the new toolkit hash (so drift is no longer reported for the current version):

```bash
NEW_HASH=$(shasum -a 256 .claude/toolkit/<source_path> | cut -d' ' -f1)
```

Then update the manifest. Read `.claude/toolkit-manifest.json`, update the `toolkit_hash` field for the relevant entry, and write back using the Edit tool (preferred) or Write tool. The jq logic for reference:

For agents: set `.agents["<agent_file>.md"].toolkit_hash` to `$NEW_HASH`
For rules: set `.rules["<rule_file>.md"].toolkit_hash` to `$NEW_HASH`

For skills: set `.skills["<skill_name>"].toolkit_hash` to the hash of `.claude/toolkit/skills/<skill_name>/SKILL.md`.

**Merge upstream changes**: Perform an intelligent merge of the user's customizations with the upstream changes. Show the merged result to the user and **ask for confirmation** before writing the file. If the merge is ambiguous, present options and let the user decide.

**Revert to managed**: Replace the customized file with the toolkit source. First, verify the toolkit source still exists (the update may have removed the file upstream). If the source was deleted upstream, inform the user and skip this file.

If the source exists, restore it. First remove the customized copy, then recreate the symlink or copy:

```bash
# For agents/rules: remove customized copy and restore symlink
rm -f .claude/agents/[file]
ln -sf ../toolkit/agents/[file] .claude/agents/[file]
# For skills: copy ALL files in the skill directory (skills can contain multiple files)
mkdir -p .claude/skills/[skill]
cp .claude/toolkit/skills/[skill]/* .claude/skills/[skill]/
```

Note: The `ln -sf` path is relative — `../toolkit/agents/[file]` resolves from the `.claude/agents/` directory to `.claude/toolkit/agents/[file]`. This matches the pattern used by `toolkit.sh init`.

After applying the resolution, update the manifest to reflect the current state:

- **Keep customization**: Update `toolkit_hash` to the new toolkit source hash. Status stays `"customized"`.
- **Merge upstream**: Update `toolkit_hash` to the new toolkit source hash. Status stays `"customized"`.
- **Revert to managed**: Change `status` back to `"managed"` and update `toolkit_hash`.

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

If there are no changes (output is empty), verify the subtree merge commit exists by checking `git log --oneline -1 --grep='Update claude-toolkit'`. If found, all update changes were captured in that commit — no additional commit is needed. If NOT found (e.g., the update was rolled back or aborted mid-flow), warn the user that changes may be lost. Skip to the summary output.

If there are changes, stage all changed files individually. Do NOT use `git add .` or `git add -A`.

```bash
git add .claude/settings.json
git add .mcp.json
git add .claude/toolkit-manifest.json
```

If the update added new skills or updated managed skills (check the update output for "Added new skill" or "Updated" messages), also stage them:

```bash
git add .claude/skills/*/* 2>/dev/null
```

If the update refreshed symlinks or created new agents/rules, stage those too:

```bash
git add .claude/agents/*.md 2>/dev/null
git add .claude/rules/*.md 2>/dev/null
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
1. Find the update commits:
   git log --oneline --grep='toolkit' -5
   # Look for: "Update claude-toolkit from X to Y" (post-update commit)
   # and: "Update claude-toolkit to <ref>" or "Merge commit" (subtree pull)
   # Typically there are 2 commits: the subtree merge + the post-update commit.

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
| `git` not installed | Inform user and stop. Git is required for all update operations (fetch, subtree pull, commit). |
| `jq` not installed | Inform user and stop. jq is required for manifest and settings operations during post-update steps. |
| `python3` not found or < 3.11 | Inform user and stop. python3 3.11+ is required for settings generation and config cache refresh. |
| `git fetch claude-toolkit` fails | 1) Check that the `claude-toolkit` remote exists: `git remote -v`. If missing, ask the user for the remote URL and add it. 2) If remote exists but fetch fails with "Could not resolve host" or connection timeout: network may be down. Suggest: check connectivity, retry later. 3) If "Permission denied" or "Authentication failed": check SSH keys (`ssh -T git@github.com`) or HTTPS credentials. |
| Version not found | If the user-requested version tag does not exist in the tag list, show available versions and ask the user to choose one. Do not proceed with a non-existent tag. |
| Version missing `v` prefix | The CLI requires version tags to start with `v` (e.g., `v1.3.0`). If the user provides a bare version like `1.3.0`, prepend `v` automatically. |
| Uncommitted changes in `.claude/toolkit/` | The CLI refuses to update with local subtree modifications. Options: commit/stash changes first, or pass `--force` to bypass (discards local changes). |
| Subtree pull conflict | Detect conflicted files with `git diff --diff-filter=U --name-only`. Present conflicts to user. Offer automatic resolution or abort (`git merge --abort`). See Phase U2 for details. |
| Subtree pull fails (not conflict) | May occur if the subtree prefix is wrong or the history is rewritten. Check `git log --oneline -5 -- .claude/toolkit/` to verify the subtree exists. If the subtree was added with a different prefix, the pull will fail — ask the user for the correct prefix. |
| Validation failure (any of 10 checks) | Attempt auto-fix up to 3 times per check. If still failing, present the error details to the user and ask how to proceed. Do not silently ignore validation failures. |
| Drift merge failure | If an intelligent merge fails or produces ambiguous results, show both versions to the user and ask them to choose or manually edit. Do not apply an uncertain merge automatically. |
