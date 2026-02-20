---
name: toolkit-contribute
description: Use when contributing generic improvements back to the toolkit repo.
user-invocable: true
---

# Toolkit Contribute Skill

Identify customized files with generic improvements, evaluate them against a 10-point generalizability checklist, prepare clean changes for the toolkit repo, validate with the full test suite, and generate submission instructions (patch or PR).

> **User Interaction Principle**: The contribute flow is collaborative. At every decision point -- which files to contribute, how to extract generic parts, how to handle drift, which submission workflow -- ask the user. Never auto-proceed past a judgment call.

## Usage

```bash
/toolkit-contribute    # Upstream generic improvements back to toolkit
```

## When to Use

- You have customized a toolkit file and the improvement is generic (useful across projects)
- You have fixed a bug in a hook, agent, or skill and want to share it upstream
- You have added a new feature to a toolkit component that other projects would benefit from

**When NOT to use** (the skill will detect these and redirect):

- For first-time setup → use `/toolkit-setup` instead
- To update the toolkit version → use `/toolkit-update` instead
- To diagnose issues → use `/toolkit-doctor` instead

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

#### Step C0.0: Check prerequisites

Verify required tools:

```bash
git --version
jq --version
python3 --version
```

If `git` is not found, inform the user:

> `git` is required for diffing, patch generation, and submission. Install it:
>
> - macOS: `xcode-select --install`
> - Ubuntu/Debian: `sudo apt-get install git`

**Stop here** if git is missing.

If `jq` is not found, inform the user:

> `jq` is required for manifest operations. Install it:
>
> - macOS: `brew install jq`
> - Ubuntu/Debian: `sudo apt-get install jq`

**Stop here** if jq is missing.

If `python3` is not found, inform the user:

> `python3 3.11+` is required for test validation. Install it from [python.org](https://python.org) or via your package manager.

**Stop here** if python3 is missing.

If `python3` is found, verify the version is 3.11+ (required for `tomllib`):

```bash
python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
```

If the version is below 3.11, inform the user:

> Python [version] is installed but the toolkit requires 3.11+ for `tomllib` support. Please upgrade Python.

**Stop here** if Python is below 3.11.

If the contribution modifies `.sh` files, also check for `shellcheck`:

```bash
shellcheck --version
```

If `shellcheck` is not found, warn the user:

> `shellcheck` is not installed. Step C3.1 (shellcheck validation) will be skipped. Install it:
>
> - macOS: `brew install shellcheck`
> - Ubuntu/Debian: `sudo apt-get install shellcheck`
>
> Without shellcheck, your contribution may be rejected by toolkit CI which requires all `.sh` files to pass `shellcheck -x -S warning`.

The contribution can still proceed, but the user should run shellcheck manually before submitting.

Also verify that `pytest` is available (required for Phase C3 validation):

```bash
python3 -m pytest --version
```

If pytest is not found, inform the user:

> `pytest` is required for test validation in Phase C3. Install it: `pip install pytest` or `pipx install pytest`.

**Stop here** if pytest is missing — test validation is mandatory for contributions.

Check toolkit installation:

```bash
ls .claude/toolkit/toolkit.sh
```

If the file does not exist, the toolkit is not installed. Tell the user:

> The toolkit is not installed in this project. Use `/toolkit-setup` to install and configure it first.

**Stop here** if the toolkit is not installed.

If `.claude/toolkit.toml` does not exist, the toolkit was installed but never configured. Tell the user:

> The toolkit subtree exists but has not been configured yet. Use `/toolkit-setup` to complete the initial configuration before contributing changes.

**Stop here** if toolkit.toml does not exist.

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

For each candidate file, generate a detailed diff against the toolkit source. The paths depend on the file type:

**Agents**: `diff -u .claude/toolkit/agents/<name>.md .claude/agents/<name>.md`
**Rules**: `diff -u .claude/toolkit/rules/<name>.md .claude/rules/<name>.md`
**Skills**: `diff -u .claude/toolkit/skills/<skill_name>/SKILL.md .claude/skills/<skill_name>/SKILL.md` (also diff any companion files like `output-schema.json`)

Before diffing, verify the installed file actually exists on disk. If a customized file was deleted, skip it and inform the user how to restore it:

> File `[path]` is marked as customized in the manifest but does not exist on disk. To restore it:
>
> - From toolkit source: `cp .claude/toolkit/<source_path> .claude/<installed_path>`
> - From git history: `git checkout HEAD -- .claude/<installed_path>`

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

Apply only the approved, gate-passing changes to the toolkit source files. Handle drift intelligently.

#### Step C2.1: Check for toolkit source drift

For each approved candidate, compare the toolkit source that the user's customization was originally based on against the current toolkit source. This is the same concept as "drift" in `/toolkit-update` Phase U4, but in the contribute context it means the upstream source has changed since the user made their customizations.

**For agents and rules**: Read the `toolkit_hash` from the manifest for this file. Compare it against the current toolkit source hash (`shasum -a 256 .claude/toolkit/<source_path>`). If they differ, the toolkit source has changed since the user customized the file (drift).

**For skills**: The manifest does NOT store `toolkit_hash` for skills. To detect drift, compare each file in the customized skill directory against the toolkit source using `diff`. If they differ (beyond the user's intended changes), drift exists.

#### Step C2.2: Handle drift

If drift is detected for a file, show the situation to the user:

> **Toolkit source has drifted**: [file_path]
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

For each approved file (with drift resolved), generate a preview diff showing what would change in the toolkit source:

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

Verify the changes were applied correctly. Note: `.claude/toolkit` is a subtree, not a separate repository -- always run git commands from the project root. Scope the diff to only the contributed files to avoid noise from unrelated toolkit changes:

```bash
git diff -- .claude/toolkit/<source_path_1> .claude/toolkit/<source_path_2>
```

If the diff is empty after applying, the changes may not have been applied correctly. Investigate before proceeding.

---

### Phase C3: Validate Contribution

Run the FULL toolkit test suite against the modified toolkit source. ALL checks must pass -- no exceptions.

#### Step C3.1: Shellcheck

If shellcheck was found missing in Step C0.0, **skip this step** and note it as "skipped (shellcheck not installed)" in the validation summary table. The contribution can proceed without shellcheck, but inform the user that shellcheck validation should be done manually before the upstream PR is merged.

```bash
shellcheck -x -S warning .claude/toolkit/hooks/*.sh .claude/toolkit/lib/*.sh .claude/toolkit/toolkit.sh
```

Note: Run all tests from the project root using paths to the toolkit directory. Do NOT `cd` into the subtree — the subtree shares the project's `.git` directory and `cd`-ing into it would change the working directory context.

#### Step C3.2: Python tests

```bash
python3 -m pytest .claude/toolkit/tests/ -v
```

Note: If tests fail with import errors (e.g., `ModuleNotFoundError`), the test suite may have path dependencies that assume it runs from the toolkit root. In that case, run in a subshell to isolate the directory change: `(cd .claude/toolkit && python3 -m pytest tests/ -v)`. Using a subshell ensures the working directory is automatically restored even if the tests fail. This is a known edge case when running tests from a consuming project.

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

#### Step C3.5b: Skill tests

```bash
bash .claude/toolkit/tests/test_skills.sh
```

Note: If the test fails with path errors, run in a subshell: `(cd .claude/toolkit && bash tests/test_skills.sh)`. This is the same workaround as C3.2 for path dependencies.

#### Step C3.6: Settings determinism

Note: This is already included in C3.2's full test run. This explicit step ensures settings determinism is verified even if C3.2 was partially skipped or failed for unrelated reasons.

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
| Skill tests | pass/fail | [details] |
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

Create a patch file from the validated changes. Scope the diff to ONLY the contributed files (not all toolkit changes), and strip the `.claude/toolkit/` prefix so paths are relative to the toolkit root:

```bash
git diff -- .claude/toolkit/<source_path_1> .claude/toolkit/<source_path_2> | sed 's|^--- a/.claude/toolkit/|--- a/|; s|^+++ b/.claude/toolkit/|+++ b/|; s|^diff --git a/.claude/toolkit/|diff --git a/|; s| b/.claude/toolkit/| b/|' > /tmp/toolkit-contribution.patch
```

Note: The `sed` patterns use `^` anchors to only rewrite diff header lines (`--- a/`, `+++ b/`, `diff --git a/`). This prevents accidental rewriting of file content that happens to contain `.claude/toolkit/` as text.

After generating, verify the patch is valid:

```bash
wc -l /tmp/toolkit-contribution.patch
```

If the patch is empty (0 lines), the diff was not captured correctly. Check that the contributed files were modified.

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

**Direct push workflow** (for maintainers with write access to the toolkit repo):

**IMPORTANT**: The `.claude/toolkit/` directory is NOT a standalone git repository — it shares the project's `.git`. You cannot create branches inside it. Always clone the toolkit repo separately to contribute changes.

```bash
# Clone the toolkit repo and apply the patch
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
# Revert ONLY the contributed files (one per contributed file)
git restore .claude/toolkit/<source_path_1>
git restore .claude/toolkit/<source_path_2>
```

Note: `git restore` is the modern replacement for `git checkout -- <path>`. Both work, but `git restore` is clearer in intent. If `git restore` is not available (git < 2.23), fall back to `git checkout -- <path>`.

Do NOT use `git restore .claude/toolkit/` or `git checkout -- .claude/toolkit/` as this discards ALL local toolkit changes, including unrelated work.

**Ask the user first** before reverting -- they may want to keep the local changes (e.g., while waiting for the PR to be merged).

---

### Phase C5: Summary

Present a mandatory structured summary of the entire contribute flow.

The summary must include ALL of the following sections:

- **Changes proposed**: [count] files, with a brief description of each change
- **Generalizability results**: table showing all 10 checks (H1-H7, Q1-Q3) for each file with pass/fail status
- **Validation results**: table showing all 8 test suite checks and their pass/fail status
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
> | Skill tests | pass |
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
| `git` not installed | Inform user and stop. Git is required for diffing, patch generation, and submission. |
| `jq` not installed | Inform user and stop. jq is required for manifest operations. |
| `python3` not found or < 3.11 | Inform user and stop. python3 3.11+ is required for running the test suite (C3.2) and `tomllib` support. Provide install guidance: `brew install python@3.11` (macOS) or see [python.org](https://python.org). |
| No customized files found | Inform the user that there are no candidates to contribute. Suggest using `toolkit.sh customize <path>` to take ownership of a file first, then making changes and re-running `/toolkit-contribute`. |
| Customized file was deleted | If a file is marked as customized in the manifest but does not exist on disk, skip it and inform the user. They may need to restore it or update the manifest. |
| Generalizability gate failure | Show which specific checks failed (H1-H7) with detailed guidance on what needs to change. Offer to help revise the change to make it generic, or let the user skip the file. Do not proceed with a file that fails any hard requirement. |
| Test failures after applying changes | Present the test output and determine whether the failure is caused by the contribution or is pre-existing. **Ask the user** whether to investigate, adjust the contribution, or abort. Do not ignore test failures. |
| Skill test failures (C3.5b) | If `test_skills.sh` fails, check whether the contributed changes affect a skill file. Skill tests validate frontmatter, companion files, and SKILL.md structure. Fix the skill to match expected format or adjust the contribution. |
| Python test import errors (C3.2) | If pytest fails with `ModuleNotFoundError`, run tests in a subshell: `(cd .claude/toolkit && python3 -m pytest tests/ -v)`. This isolates path dependencies. See Step C3.2 note. |
| Toolkit source drift | Show both the user's base version and the current toolkit source. Assess whether the changes conflict or can be merged cleanly. If ambiguous, present options (adapt, skip, abort) and **ask the user** to decide. Do not auto-merge when the result is uncertain. |
| Patch file already exists | Inform the user and offer to save to an alternative path with a timestamp suffix. Do not silently overwrite. |
| Empty patch generated | The diff was not captured. Verify the contributed files were actually modified in `.claude/toolkit/`. If the changes were already reverted, re-apply them before generating the patch. |
