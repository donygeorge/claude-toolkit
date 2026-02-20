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

#### Step 0.0.5: Prerequisite tool checks

Verify required tools are available before proceeding:

```bash
git --version
jq --version
python3 --version
```

If `git` is not found, inform the user:

> `git` is required by the toolkit for version control and commits. Install it:
>
> - macOS: `xcode-select --install`
> - Ubuntu/Debian: `sudo apt-get install git`
> - Other: [git-scm.com/downloads](https://git-scm.com/downloads)

If `jq` is not found, inform the user:

> `jq` is required by the toolkit for JSON processing. Install it:
>
> - macOS: `brew install jq`
> - Ubuntu/Debian: `sudo apt-get install jq`
> - Other: [jqlang.github.io/jq/download](https://jqlang.github.io/jq/download/)

If `python3` is not found, inform the user:

> `python3 3.11+` is required by the toolkit. Install it from [python.org](https://python.org) or via your package manager.

If `python3` is found, verify the version is 3.11+ (required for `tomllib`):

```bash
python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
```

If the version is below 3.11, inform the user:

> Python [version] is installed but the toolkit requires 3.11+ for `tomllib` support. Please upgrade Python.

**Stop here** if any required tool is missing or Python is below 3.11. The toolkit cannot function without them.

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

If this command fails (non-zero exit, Python error, or non-JSON output), the toolkit may be corrupted or incompatible. Try:

1. Check Python version: `python3 --version` (must be 3.11+)
2. Re-run with verbose error: `python3 .claude/toolkit/detect-project.py --project-dir . 2>&1`
3. If it's a missing module error, the toolkit files may be incomplete — suggest `bash .claude/toolkit/toolkit.sh update --latest`

**Stop here** if detection cannot produce valid JSON output after these recovery steps.

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

Handle issues **in the order listed below**. The toolkit.toml check MUST be resolved first — `init --force` requires toolkit.toml to exist.

**If `toml_exists` is false** (subtree exists but no toolkit.toml):

```bash
bash .claude/toolkit/toolkit.sh init --from-example
```

Report to user: "No toolkit.toml found. Created one from the example template."

Note: `init --from-example` runs the full init flow (agents, skills, rules, config, manifest). After this completes, skip the missing skills/agents check below — the init just created them.

**If skills or agents are missing** (`missing_skills` or `missing_agents` non-empty):

Only run this if `init --from-example` was NOT just executed above (that already handles missing skills/agents). This is a partial install. Fill the gaps (requires toolkit.toml to exist — handle that first):

```bash
bash .claude/toolkit/toolkit.sh init --force
```

Report to user: "Detected missing skills/agents. Ran `toolkit.sh init --force` to fill gaps."

**If `toml_is_example` is true** (toolkit.toml is still the unmodified example):

Note: "toolkit.toml is still the default example. This setup will customize it for your project."

**If broken symlinks exist** (`broken_symlinks` non-empty):

Note: The `broken_symlinks` array contains paths **relative to `.claude/`** (e.g., `agents/reviewer.md`, not `.claude/agents/reviewer.md`).

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

#### Step 0.3.5: Detect migration edge cases

These checks catch problems from interrupted installs or partial migrations.

**Incomplete migration** (pre-toolkit backups exist but settings-project.json missing):

```bash
ls .claude/settings.json.pre-toolkit 2>/dev/null
ls .claude/settings-project.json 2>/dev/null
```

If `.pre-toolkit` backups exist but `settings-project.json` does NOT exist, a previous migration was incomplete. Fix:

```bash
cp .claude/settings.json.pre-toolkit .claude/settings-project.json
bash .claude/toolkit/toolkit.sh generate-settings
```

Report: "Found pre-toolkit backup but no settings-project.json. Restored project settings from backup."

**Non-executable hooks:**

Check each hook script for executability:

```bash
for hook in .claude/toolkit/hooks/*.sh; do
  [ -f "$hook" ] && [ ! -x "$hook" ] && echo "Not executable: $hook"
done
```

Note: Do NOT use `find ... -perm` for this check — the `-perm` flag syntax differs between macOS (`-perm +111`) and Linux (`-perm /111`), causing false results.

If any are found: `chmod +x .claude/toolkit/hooks/*.sh`

**Orphaned skill directories** (directory exists in `.claude/skills/` but is empty or missing SKILL.md):

```bash
if [ -d .claude/skills ]; then
  for d in .claude/skills/*/; do
    [ -d "$d" ] || continue
    [ -f "$d/SKILL.md" ] || echo "Missing SKILL.md in $d"
  done
fi
```

If found, re-copy files from the toolkit source for each orphaned skill directory. **Before copying, check if the corresponding toolkit source directory exists** — if `.claude/toolkit/skills/<name>/` does not exist, the skill directory is not from the toolkit (it may be a user-created skill). Leave it alone and move on.

For toolkit-sourced skills:

```bash
mkdir -p .claude/skills/<name>
cp .claude/toolkit/skills/<name>/* .claude/skills/<name>/
```

Note: Some skills have companion files (like `output-schema.json` or `milestone-template.md`), so copy ALL files from the toolkit source directory, not just `SKILL.md`.

#### Step 0.4: Check for toolkit version changes

```bash
bash .claude/toolkit/toolkit.sh status
```

If the status output mentions a version change or shows that the toolkit was recently updated, inform the user:

> Toolkit has been updated. New features may be available. This setup will refresh your configuration.

If the user wants to see what changed, read the toolkit CHANGELOG using the Read tool on `.claude/toolkit/CHANGELOG.md`.

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

If validation reports warnings or errors, report them and offer to fix (follow the auto-fix table in Phase 6.3). After fixes, re-run `toolkit.sh validate` to confirm. Then **stop** — do not re-run the full setup flow.

#### Step 0.6: Handle --reconfigure flag

If `--reconfigure` was passed, skip the state-based shortcuts above and proceed directly to Phase 1 for full re-detection. Existing `toolkit.toml` values will be preserved where they differ from detected defaults (you will ask the user about conflicts in Phase 4).

---

### Phase 1: Project Discovery

Run the detection script to auto-detect project properties. Note: this is the SAME command as Phase 0 Step 0.2 — if no changes were made in Phase 0 (no `init --force`, no `init --from-example`), you can skip re-running detection and reuse the JSON output you already parsed in Step 0.2. If Phase 0 made changes (init, symlink fixes, etc.), re-run detection to get fresh results that reflect the repaired state.

```bash
python3 .claude/toolkit/detect-project.py --project-dir .
```

If this fails, apply the same recovery steps as Phase 0 Step 0.2. If detection cannot run, ask the user to manually specify: project name, stacks, test command, lint command, format command. Proceed with manual values.

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
ruff --version    # Check if the tool is available
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

1. Check local installations first:
   - Python: check `.venv/bin/` or `poetry run <cmd>` or `pipx run <cmd>`
   - TypeScript/JS: check `npx <cmd>`, `npm run <script>`, `node_modules/.bin/<cmd>`
   - Check if `node_modules` is missing but `package.json` exists (needs `npm install`)
2. If the tool exists locally, use the local invocation (e.g., `npx eslint` instead of `eslint`)
3. If not found anywhere, offer to install it or ask for an alternative:

> The [type] command `[cmd]` was not found. Options:
>
> 1. **Install it** (recommended): [install command]
> 2. **Provide an alternative** command
> 3. **Skip** this tool for now

**Common install commands by stack:**

| Tool | Install command |
| ---- | -------------- |
| ruff (Python lint/format) | `pip install ruff` or `pipx install ruff` |
| eslint (TypeScript lint) | `npm install --save-dev eslint` |
| prettier (TypeScript format) | `npm install --save-dev prettier` |
| pytest (Python test) | `pip install pytest` |
| node_modules missing | `npm install` (installs all package.json deps) |

After installation, re-validate the command by running `<cmd> --version`.

4. If the user skips, leave that field empty in the config and note it in the output

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
- **Termination**: Allow at most 3 rounds of changes. After 3 rounds, proceed with the latest confirmed settings and note that the user can manually edit `toolkit.toml` later for further adjustments.

**Do NOT proceed to Phase 4 until the user explicitly confirms the table.** Implicit continuation from a re-validation round is not sufficient.

---

### Phase 4: Generate toolkit.toml

Generate or update `.claude/toolkit.toml` based on confirmed detection results.

#### Fresh setup (no existing toolkit.toml, or toolkit.toml is the unmodified example)

Read the example template for reference using the Read tool on `.claude/toolkit/templates/toolkit.toml.example`.

Use the **Write tool** (not bash heredocs) to create `.claude/toolkit.toml` with the confirmed detection results. Map detected values to TOML sections:

| Detection field | TOML location |
| --------------- | ------------- |
| `name` | `[project] name` |
| `stacks` | `[project] stacks` |
| `version_file` | `[project] version_file` |
| Lint commands | `[hooks.post-edit-lint.linters.<ext>] cmd` and `[hooks.task-completed.gates.lint] cmd` |
| Lint gate glob | `[hooks.task-completed.gates.lint] glob` (e.g., `"*.py"` for Python) |
| Format commands | `[hooks.post-edit-lint.linters.<ext>] fmt` |
| Test command | `[hooks.task-completed.gates.tests] cmd` |
| Test gate glob | `[hooks.task-completed.gates.tests] glob` (e.g., `"*.py"` for Python) |
| Source dirs | `[hooks.compact] source_dirs` |
| Source extensions | `[hooks.compact] source_extensions` |

Use the example template structure. Include comments explaining each section. For lint/format commands, set the gate glob patterns based on the detected source extensions (e.g., `"*.py"` for Python lint gate).

**Handling empty or skipped commands**: If a command (lint, test, or format) was not detected or the user chose to skip it:

- **Omit the key entirely** from the TOML section (do not set it to an empty string `""`)
- Add a TOML comment explaining the field is available: `# cmd = "your-test-command-here"  # No test command detected — add one when available`
- The toolkit hooks check whether the key exists before running the command, so omitting the key is safe and preferred over an empty string (which could cause the hook to attempt to run an empty command)

For any other detection field that was empty or skipped, use the example template defaults and add a comment noting it should be customized.

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

Read the template using the Read tool on `.claude/toolkit/templates/CLAUDE.md.template`.

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

### Phase 6: Settings Generation & Comprehensive Validation

Generate the merged settings, validate the installation, auto-fix any issues, then run deep semantic checks that go beyond what the CLI validator covers.

#### Step 6.1: Regenerate config cache

Before generating settings, ensure the config cache is fresh:

```bash
python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env
```

If this fails, `toolkit.toml` has syntax or schema errors. Read the error output, fix the TOML file using the **Edit tool**, and re-run. Common causes:

- Unknown TOML section (check against `.claude/toolkit/templates/toolkit.toml.example`)
- Wrong value type (e.g., string where int expected)
- Invalid enum value (e.g., `mode = "fast"` instead of `"deep"` or `"quick"`)

#### Step 6.2: Generate settings

```bash
bash .claude/toolkit/toolkit.sh generate-settings
```

This merges base + stack overlays + project overrides into `.claude/settings.json` and `.mcp.json`.

If this fails:

- Malformed `toolkit.toml` — fix and re-run Step 6.1 first
- Missing stack overlay — verify stacks in toolkit.toml match available stacks in `.claude/toolkit/templates/stacks/`
- Permission error — the command uses temp files + cp internally, but if it still fails, check directory permissions on `.claude/`

#### Step 6.3: Validate and auto-fix loop

Run validation:

```bash
bash .claude/toolkit/toolkit.sh validate
```

If validation reports errors or warnings, apply fixes for each issue type using the table below. Then **re-run validation**. Repeat up to **2 rounds** of fix-then-validate.

**Auto-fix procedures** (apply in order of priority):

| Issue | Fix |
| ----- | --- |
| **Missing skills or agents** | `bash .claude/toolkit/toolkit.sh init --force` |
| **Hooks not executable** | `chmod +x .claude/toolkit/hooks/*.sh` |
| **Broken symlinks** | `bash .claude/toolkit/toolkit.sh init --force` |
| **Stale config cache** | Re-run Step 6.1, then re-run Step 6.2 (settings depend on the cache) |
| **Manifest not found** | `bash .claude/toolkit/toolkit.sh init --force` |
| **settings.json invalid JSON** | Delete `.claude/settings.json` and re-run Step 6.2 |
| **No settings-project.json but custom settings exist** | If `.claude/settings.json.pre-toolkit` exists: `cp .claude/settings.json.pre-toolkit .claude/settings-project.json` then re-run Step 6.2. If no backup exists, ask the user to check `git log -p -- .claude/settings.json` for their original settings. |
| **Duplicate hooks in settings.json** | Read `.claude/settings-project.json`. Find hook entries whose event type + matcher combination already exists in `.claude/toolkit/templates/settings-base.json`. Remove those entries from `settings-project.json` using the **Edit tool**. Then re-run Step 6.2. |
| **MCP server / plugin overlap** | Read `.claude/settings.json` for `enabledPlugins` and `.mcp.json` for `mcpServers`. If a server name appears in both, the generate-settings dedup should have handled it. If it didn't, manually remove the overlapping entry from `settings-project.json` (if the user added it there) or inform the user. Re-run Step 6.2. |

After 2 rounds of fix-then-validate, if errors remain, report them to the user with specific file paths and what went wrong.

#### Step 6.4: Deep semantic validation

The CLI validator checks structural health. This step verifies **semantic correctness** that the validator cannot check. Read the relevant files and verify each property.

**A. Skill completeness** — verify every toolkit skill is registered with content:

```bash
ls -d .claude/toolkit/skills/*/
ls -d .claude/skills/*/
```

For EACH toolkit skill directory:

1. A matching directory must exist in `.claude/skills/`
2. That directory must contain a `SKILL.md` file
3. The `SKILL.md` must be non-empty (not 0 bytes)

If any skill is missing or empty, copy all files from toolkit source (some skills have companion files like `output-schema.json` or `milestone-template.md`):

```bash
mkdir -p .claude/skills/<name>
cp .claude/toolkit/skills/<name>/* .claude/skills/<name>/
```

**B. Agent completeness** — verify every toolkit agent is linked:

```bash
ls .claude/toolkit/agents/*.md
ls .claude/agents/*.md
```

For EACH toolkit agent file, verify a corresponding file or symlink exists in `.claude/agents/`. If missing, run `bash .claude/toolkit/toolkit.sh init --force`.

**C. Rule completeness** — verify every toolkit rule is linked:

```bash
ls .claude/toolkit/rules/*.md
ls .claude/rules/*.md
```

For EACH toolkit rule file, verify a corresponding file or symlink exists in `.claude/rules/`. If missing, run `bash .claude/toolkit/toolkit.sh init --force`.

**D. Settings merge integrity** — use jq to verify the merged settings contain expected content:

```bash
# Must have hooks with at least one event (null-safe)
jq '.hooks // {} | keys | length' .claude/settings.json
# Must have permissions with deny list (null-safe)
jq '.permissions // {} | .deny // [] | length' .claude/settings.json
```

Both counts should be > 0. If either is 0, the merge lost content — re-run Step 6.2.

If `.claude/settings-project.json` exists, verify project-specific keys survived the merge:

```bash
# Check which top-level keys the project overlay defines
jq 'keys' .claude/settings-project.json
# Verify each key exists in the merged output
jq 'keys' .claude/settings.json
```

Specifically check:

- If project has `enabledPlugins`: `jq '.enabledPlugins' .claude/settings.json` should list them
- If project has `sandbox`: `jq '.sandbox' .claude/settings.json` should show project's sandbox config
- If project has custom `env` vars: `jq '.env' .claude/settings.json` should include them
- If project has `mcpServers`: these are routed to `.mcp.json` (NOT `settings.json`) — check `jq '.mcpServers' .mcp.json` instead

If expected project content is missing from the merge, re-run Step 6.2. If still missing, report the specific missing keys to the user.

**E. MCP server integrity** — verify base servers are present:

```bash
# List base servers expected (null-safe)
jq '.mcpServers // {} | keys' .claude/toolkit/mcp/base.mcp.json
# List servers in generated .mcp.json (null-safe)
jq '.mcpServers // {} | keys' .mcp.json
# List enabledPlugins (if any)
jq '.enabledPlugins // []' .claude/settings.json
```

Each base server should be present in `.mcp.json` UNLESS it overlaps with an `enabledPlugins` entry (intentional dedup — this is correct behavior). If a base server is missing with no plugin overlap, re-run Step 6.2.

**Overlap check**: If a server name appears in BOTH `.mcp.json` and `enabledPlugins`, the dedup in `generate-settings.py` should have removed it from `.mcp.json`. If it didn't, manually remove the `.mcp.json` entry (the plugin takes priority) and re-run Step 6.2.

**F. Hook command resolution** — the CLI validator (`toolkit.sh validate`) already checks this thoroughly, including:

- Resolving `"$CLAUDE_PROJECT_DIR"` (quoted form first, then bare form)
- Handling `python3` prefixed commands
- Skipping system commands (e.g., `osascript`)

If Step 6.3 validate passed with 0 hook errors, this check is satisfied. If hook errors were reported and not fixed, run `bash .claude/toolkit/toolkit.sh init --force` to restore missing scripts.

**G. Config consistency** — verify toolkit.toml aligns with reality:

- Stacks in `toolkit.toml` should match what `detect-project.py` found (or what the user confirmed in Phase 3). If they differ and the user didn't override, update toolkit.toml using the **Edit tool** and re-run Steps 6.1-6.2.
- Config cache must be fresh: `toolkit-cache.env` should be newer than `toolkit.toml`. If stale, re-run Step 6.1.

#### Step 6.5: Final validation pass

After all auto-fixes and semantic checks, run one final validation:

```bash
bash .claude/toolkit/toolkit.sh validate
```

This **must** pass with 0 errors. Warnings are acceptable if they are documented edge cases (e.g., shellcheck not installed).

If errors persist, report each remaining error to the user with:

- The exact error message
- Which file is affected
- What was attempted to fix it
- What the user should check manually

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

#### Step 7.2: Verify format command

If a format command was configured, run its **check mode** (dry-run) on a real source file. The detection output includes a `check_cmd` field for each format command — use that if available:

```bash
# Example: verify format command in check mode (does not modify files)
ruff format --check src/example.py
# or: npx prettier --check src/example.ts
```

If no `check_cmd` was detected and the format tool has no known check mode, run `<cmd> --version` to at least verify it's callable.

If the format command fails:

1. Check if the failure is a real formatting issue (expected) or a configuration problem
2. If it is a configuration problem, adjust the command in toolkit.toml and re-run
3. Iterate up to 2 times

**Important**: Use check/dry-run mode only — do NOT modify source files during setup.

#### Step 7.3: Verify test command

If a test command was configured (from `[hooks.task-completed.gates.tests] cmd` in toolkit.toml), run it:

```bash
# Run the configured test command from toolkit.toml
```

If the test command fails:

1. Check if tests are genuinely failing (not a config issue) -- this is OK, report to user
2. If the command itself is broken (wrong path, missing dependency), adjust and re-run
3. Iterate up to 2 times

#### Step 7.4: Report verification results

> **Verification results**:
>
> - Lint: [passed/failed/skipped]
> - Format: [passed/failed/skipped]
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

# Claude Toolkit - generated config cache (lives at .claude/toolkit-cache.env)
.claude/toolkit-cache.env
```

If `.gitignore` already contains these entries, skip this step.

#### Step 8.1: Review changes

```bash
git status
git diff
```

Review the changes to ensure only expected files are modified. The typical files are:

- `.claude/toolkit.toml`
- `.claude/settings.json`
- `.mcp.json`
- `CLAUDE.md` (new or modified)
- `.claude/toolkit-manifest.json`
- `.claude/settings-project.json` (if existing settings were preserved)
- `.claude/skills/` (if init --force was run)
- `.claude/agents/` (if init --force was run)
- `.claude/rules/` (if init --force was run)
- `.claude/agent-memory/` (if init created agent memory directories)
- `.gitignore` (if toolkit entries were added)

Note: `.claude/toolkit-cache.env` will show in `git status` but is gitignored and should NOT be staged.

#### Step 8.2: Stage specific files

Stage each file individually. Do NOT use `git add .` or `git add -A`.

```bash
git add .claude/toolkit.toml
git add .claude/settings.json
git add .mcp.json
git add CLAUDE.md
git add .gitignore
```

Also stage these if they exist (created during setup):

```bash
git add .claude/settings-project.json 2>/dev/null
git add .claude/toolkit-manifest.json 2>/dev/null
```

If `init --force` was run (skills, agents, or rules were created/restored), stage them explicitly:

```bash
git add .claude/skills/*/* 2>/dev/null
git add .claude/agents/*.md 2>/dev/null
git add .claude/rules/*.md 2>/dev/null
```

If agent memory directories were created, stage them:

```bash
git add .claude/agent-memory/*/MEMORY.md 2>/dev/null
```

Note: `toolkit-cache.env` is generated and gitignored — do NOT stage it. Do NOT stage `.claude/settings.json.pre-toolkit` or `.mcp.json.pre-toolkit` (these are local backups).

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
| `git` not installed | Inform user. Cannot proceed — git is required for commit, remote operations, and subtree management. |
| `jq` not installed | Inform user. Cannot proceed without jq — it's required for all JSON operations. |
| `python3` not found or < 3.11 | Inform user. Required for detection, config cache, and settings generation. |
| `detect-project.py` not found | Toolkit may be outdated or corrupt. Run `bash .claude/toolkit/toolkit.sh update --latest` and retry. |
| `detect-project.py` crashes (Python error) | Check Python version (3.11+ required). Read error output. If module error, toolkit files may be incomplete. |
| Detection returns empty stacks | Ask user to specify stacks manually. Write them to toolkit.toml. |
| All commands fail validation | Offer to install missing tools (see Phase 2 install table). Ask user to provide working commands if install is declined. |
| `node_modules` missing | Run `npm install` if `package.json` exists. TypeScript tools (eslint, prettier) need this. |
| `toolkit.sh generate-settings` fails | Check toolkit.toml for syntax errors. Run `python3 .claude/toolkit/generate-config-cache.py --validate-only --toml .claude/toolkit.toml` to find issues. |
| `toolkit.sh validate` reports issues | Follow auto-fix loop in Step 6.3. Use fix table in priority order. |
| Missing skills after init | Copy manually: `cp -r .claude/toolkit/skills/<name> .claude/skills/<name>` |
| Hooks not executable | `chmod +x .claude/toolkit/hooks/*.sh` |
| Pre-toolkit backup exists, no settings-project.json | `cp .claude/settings.json.pre-toolkit .claude/settings-project.json` then regenerate settings |
| Duplicate hooks in merged settings | Edit `settings-project.json` to remove entries that overlap with toolkit base hooks |
| MCP server/plugin overlap persists | Check `enabledPlugins` vs `.mcp.json` servers. Remove the duplicate from whichever side the user doesn't need. |
| User provides no confirmation in Phase 3 | Remind the user that confirmation is needed. Do not proceed without it. |

## Output

After completion, report to the user:

- Toolkit state before setup (fresh, partial, existing)
- Stacks detected and validated
- Commands configured (lint, test, format)
- Files created or modified
- CLI validation result (pass/fail with error/warning counts)
- Deep validation results (skills: N/N, agents: N/N, rules: N/N, merge integrity: pass/fail, MCP integrity: pass/fail)
- Auto-fixes applied (list what was fixed and how)
- Any items needing manual attention
