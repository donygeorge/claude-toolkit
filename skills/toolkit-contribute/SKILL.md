---
name: toolkit-contribute
description: Use when contributing generic improvements back to the toolkit repo.
user-invocable: true
---

# Toolkit Contribute Skill

Identify customized files with generic improvements, evaluate them against a 10-point generalizability checklist, prepare clean changes for the toolkit repo, validate with the full test suite, and generate submission instructions (patch or PR).

> **User Interaction Principle**: The contribute flow is collaborative. At every decision point -- which files to contribute, how to extract generic parts, how to handle divergence, which submission workflow -- ask the user. Never auto-proceed past a judgment call.

## Usage

```bash
/toolkit-contribute    # Upstream generic improvements back to toolkit
```

## When to Use

- You have customized a toolkit file and the improvement is generic (useful across projects)
- You have fixed a bug in a hook, agent, or skill and want to share it upstream
- You have added a new feature to a toolkit component that other projects would benefit from

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Generic only -- reject project-specific content** | Every change must pass the 7 hard generalizability requirements; project-specific paths, tools, and conventions must be removed. |
| **2. Full test suite must pass** | All toolkit tests (shellcheck, pytest, CLI, manifest, hooks) must pass after applying the contribution; no exceptions. |
| **3. One contribution per submission** | Each contribution should be a focused, reviewable unit; do not bundle unrelated changes into a single patch. |
| **4. Preserve backward compatibility** | Existing toolkit.toml files and workflows must continue to work without modification after the contribution is applied. |

---

## Execution Flow

Execute these phases in order. Do NOT skip phases.

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

> No customized or modified files were found. There is nothing to contribute upstream. If you have improvements to suggest, first customize a file with `toolkit.sh customize <path>`, make your changes, and then re-run `/toolkit-contribute`.

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
git add <list of changed files>
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
git add <list of changed files>
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

**Ask the user first** before reverting -- they may want to keep the local changes (e.g., while waiting for the PR to be merged).

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

## Error Handling

| Error | Recovery |
| ----- | -------- |
| No customized files found | Inform the user that there are no candidates to contribute. Suggest using `toolkit.sh customize <path>` to take ownership of a file first, then making changes and re-running `/toolkit-contribute`. |
| Generalizability gate failure | Show which specific checks failed (H1-H7) with detailed guidance on what needs to change. Offer to help revise the change to make it generic, or let the user skip the file. Do not proceed with a file that fails any hard requirement. |
| Test failures after applying changes | Present the test output and determine whether the failure is caused by the contribution or is pre-existing. **Ask the user** whether to investigate, adjust the contribution, or abort. Do not ignore test failures. |
| Toolkit source divergence | Show both the user's base version and the current toolkit source. Assess whether the changes conflict or can be merged cleanly. If ambiguous, present options (adapt, skip, abort) and **ask the user** to decide. Do not auto-merge when the result is uncertain. |
