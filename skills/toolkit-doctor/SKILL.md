---
name: toolkit-doctor
description: Use when diagnosing toolkit health issues or optimizing configuration.
user-invocable: true
---

# Toolkit Doctor Skill

Perform a deep health evaluation of the toolkit installation. Goes beyond the CLI `toolkit.sh doctor` (which checks infrastructure basics) by analyzing configuration coherence, live-testing commands, auditing dependencies and API keys, checking CLAUDE.md content, identifying optimization opportunities, and testing hook behavior in depth.

> **Relationship to `toolkit.sh doctor`**: The CLI command remains available for quick terminal/CI checks. This skill flow includes everything the CLI checks as Phase H0, then goes much deeper with AI-assisted analysis and interactive fixes.

> **User Interaction Principle**: Present all findings before applying fixes. Categorize by severity so the user can prioritize. Never auto-fix without confirmation.

## Usage

```bash
/toolkit-doctor    # Run deep health evaluation and optimization
```

## When to Use

- After a toolkit update, to verify nothing is broken
- When hooks or commands are behaving unexpectedly
- Periodically, to identify optimization opportunities
- When troubleshooting configuration issues

---

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Report findings by severity** | Categorize every finding as ERROR, WARN, OPT, or INFO using the severity system; never mix severities. |
| **2. Offer fixes interactively** | Present all findings to the user before applying any fixes; let the user choose which fixes to apply. |
| **3. Never auto-fix without confirmation** | Even for obviously safe fixes, always ask the user before modifying files or running commands. |
| **4. Test fixes before applying** | After applying a fix, re-run the relevant check to verify the fix actually resolved the issue. |

---

## Severity System

All findings across all phases use this four-tier severity system:

| Severity | Symbol | Meaning | Action |
| -------- | ------ | ------- | ------ |
| Error | `[ERROR]` | Something is broken or misconfigured and will cause failures | Must fix (auto-fix offered where possible) |
| Warning | `[WARN]` | Potential problem that may cause unexpected behavior | Should fix (auto-fix offered where possible) |
| Optimization | `[OPT]` | Working but could be improved for better experience | Optional (auto-fix offered where possible) |
| Info | `[INFO]` | Informational observation, no action needed | No action |

Accumulate findings throughout all phases. Each finding records: severity, phase, description, and whether an auto-fix is available.

---

## Execution Flow

Execute these phases in order. Do NOT skip phases.

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

- **Stale stack**: toolkit.toml lists a stack that detection no longer finds -> `[WARN]` ("Stack '[name]' configured in toolkit.toml but not detected in project")
- **Missing stack**: Detection finds a stack not listed in toolkit.toml -> `[OPT]` ("Stack '[name]' detected but not configured -- add to toolkit.toml for stack-specific tooling")
- **Auto-fix available**: Offer to update `[project] stacks` in toolkit.toml to match detection

#### H1.2: Settings.json freshness

Generate what `settings.json` should contain by running the merge logic in-memory, then compare against the actual file. If they differ, identify which sections diverge (hooks, deny patterns, env vars, etc.) and report:

- Different content -> `[WARN]` ("settings.json is stale -- [section] differs from what generate-settings would produce")
- **Auto-fix available**: `bash .claude/toolkit/toolkit.sh generate-settings`

#### H1.3: Config cache freshness

Compare toolkit.toml mtime against toolkit-cache.env mtime. Additionally, regenerate the cache in-memory and compare content against the current file. This catches cases where the file was touched but content is wrong.

- Stale or content mismatch -> `[WARN]` ("Config cache is stale or has incorrect content")
- **Auto-fix available**: `python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output .claude/toolkit-cache.env`

#### H1.4: toolkit.toml commands vs detected commands

Compare the commands configured in toolkit.toml against what `detect-project.py` would produce:

| toolkit.toml key | Detection field |
| ----------------- | --------------- |
| `[hooks.post-edit-lint.linters.<ext>] cmd` | `lint.<stack>.cmd` |
| `[hooks.task-completed.gates.tests] cmd` | `test.cmd` |
| `[hooks.task-completed.gates.lint] cmd` | `lint.<stack>.cmd` |

- If toolkit.toml differs from detection AND differs from the example default -> `[INFO]` (likely intentional customization)
- If toolkit.toml matches the example default but detection finds a working alternative -> `[OPT]` ("Detected '[cmd]' as lint command, but toolkit.toml still uses example default '[default_cmd]'")

#### H1.5: TOML schema validation

```bash
python3 .claude/toolkit/generate-config-cache.py --validate-only --toml .claude/toolkit.toml
```

If the `--validate-only` flag is not supported, attempt cache generation and check for errors:

```bash
python3 .claude/toolkit/generate-config-cache.py --toml .claude/toolkit.toml --output /dev/null
```

- Validation errors -> `[ERROR]` with the specific schema error message

---

### Phase H2: Command Validation (Live Testing)

Test that configured commands actually work -- not just "is the binary available" but "does the command succeed when invoked."

#### H2.1: Lint command

1. Read the configured lint gate command (from `toolkit-cache.env` or by parsing `toolkit.toml`: `[hooks.task-completed.gates.lint] cmd`)
2. Extract the executable (first word of the command)
3. Check if executable exists:
   - If it is a path (contains `/`), check with `test -x <path>` -- if the path references a virtual environment (e.g., `.venv/bin/ruff`) that does not exist, report `[ERROR]` ("Lint command references '.venv/bin/ruff' but '.venv/' does not exist")
   - If it is a bare command, check with `command -v <exe>`
4. If found, run `<exe> --version` to verify it works
5. Find a source file matching the gate glob pattern and run the full lint command on it
6. Classify the result:
   - Command not found -> `[ERROR]` with install guidance
   - Command crashes (non-lint failure) -> `[ERROR]`
   - Command finds lint issues (exit code from lint violations) -> `[INFO]` ("Lint command works -- found lint issues in sample file, which is expected")
   - Command passes clean -> `[INFO]` ("Lint command works correctly")
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
   - Command not found -> `[ERROR]`
   - Makefile target missing -> `[ERROR]` ("Test command 'make test-changed' references missing Makefile target")
   - Command starts but tests fail -> `[INFO]` ("Test command works -- some tests fail, which may be expected")
   - Command works -> `[INFO]`

#### H2.3: Format commands

For each extension configured in `[hooks.post-edit-lint.linters.<ext>]`:

1. Read the `fmt` command
2. Extract the executable and check availability
3. If a `fallback` is configured, check if the fallback is available too
4. Missing formatter -> `[WARN]` ("Format command for .[ext] files references '[exe]' which is not found")
5. Missing fallback when primary is missing -> `[WARN]`

#### H2.4: Post-edit lint commands

Same pattern as H2.3 but for the `cmd` field in each linter extension section.

---

### Phase H3: Dependency & API Key Audit

Check that external dependencies and credentials referenced across the configuration are available.

#### H3.1: MCP server dependencies

Read `.mcp.json` and check each configured MCP server:

| Server | Dependency Check | API Key Check | If Missing |
| ------ | ---------------- | ------------- | ---------- |
| context7 | `command -v npx` | None required | `[WARN]` npx not found -- context7 MCP will not work |
| playwright | `command -v npx` | None required | `[WARN]` npx not found -- playwright MCP will not work |
| codex | Check codex server config | `OPENAI_API_KEY` env var set? | `[WARN]` OPENAI_API_KEY not set -- codex MCP may not authenticate |

For any additional MCP servers found in `.mcp.json` that are not in the table above, check that the configured `command` is available.

- **Manual fix guidance**: Provide install commands (e.g., "Install Node.js: `brew install node`", "Set OPENAI_API_KEY: `export OPENAI_API_KEY=...`")

#### H3.2: Required, optional, and security tools

Read from the toolkit config:

- `[hooks.setup] required_tools` -- each missing tool -> `[ERROR]` with install guidance
- `[hooks.setup] optional_tools` -- each missing tool -> `[INFO]`
- `[hooks.setup] security_tools` -- each missing tool -> `[OPT]` with install guidance

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

Each missing expected tool for a configured stack -> `[WARN]` ("Stack 'python' is configured but 'pip3' is not found")

---

### Phase H4: CLAUDE.md Content Analysis

Check that the project's `CLAUDE.md` (at the project root) is consistent and complete. Skip this phase entirely if no project `CLAUDE.md` exists -- report `[INFO]` ("No project CLAUDE.md found -- consider creating one with `/toolkit-setup`") and proceed.

**Important**: Analyze the project's root `CLAUDE.md`, NOT the toolkit's own `CLAUDE.md` at `.claude/toolkit/CLAUDE.md`.

#### H4.1: Template marker detection

Read the project's `CLAUDE.md` and search for:

- Unfilled template placeholders: patterns matching `{{...}}`
- HTML comment markers from the template: `<!-- ... -->` (indicates sections not yet customized)
- Empty placeholder sections (e.g., a heading followed immediately by another heading with no content)

Each unfilled placeholder -> `[OPT]` ("CLAUDE.md has unfilled placeholder: '{{PLACEHOLDER_NAME}}'")
Each template comment -> `[OPT]` ("CLAUDE.md has template comment that should be replaced with project content")

#### H4.2: Command consistency with toolkit.toml

Extract command references from CLAUDE.md -- look for lines inside code blocks (`` ``` `` sections) that appear to be shell commands (lines starting with common command prefixes or containing tool names).

Cross-reference extracted commands with toolkit.toml configuration:

- CLAUDE.md says `make test` but toolkit.toml test gate uses `pytest` -> `[WARN]` ("CLAUDE.md references 'make test' but toolkit.toml test gate uses 'pytest' -- these should be consistent")
- CLAUDE.md says `ruff check` but toolkit.toml uses `.venv/bin/ruff check` -> `[INFO]` (minor path difference)

This check is heuristic. Report only clear contradictions, not stylistic differences.

#### H4.3: Dead command detection

For each command found in CLAUDE.md code blocks, do a quick availability check:

1. Extract the executable (first word)
2. If it is `make <target>`, check if the Makefile has that target
3. Otherwise, check `command -v <exe>`

Each unreachable command -> `[WARN]` ("CLAUDE.md references '[command]' but it is not available")

Do not flag commands that are clearly examples or placeholders (e.g., lines with `<placeholder>` syntax).

#### H4.4: Missing toolkit section

If CLAUDE.md exists but does not mention "toolkit" anywhere (case-insensitive search), report:

- `[OPT]` ("CLAUDE.md does not mention the toolkit -- consider adding a section. Run `/toolkit-setup` to add one automatically.")

---

### Phase H5: Optimization Opportunities

Identify configuration that works but could be improved.

#### H5.1: Default values that should be customized

Read `.claude/toolkit.toml` and compare key fields against the example template defaults (`templates/toolkit.toml.example`):

| Field | Example Default | Finding if Unchanged |
| ----- | --------------- | -------------------- |
| `[project] name` | `"my-project"` | `[OPT]` "Project name is still the example default 'my-project'" |
| `[hooks.subagent-context] critical_rules` | `[]` | `[OPT]` "No critical rules configured -- subagents will not receive project-specific rules" |
| `[hooks.subagent-context] available_tools` | `[]` | `[OPT]` "No available tools configured for subagent context" |
| `[hooks.subagent-context] stack_info` | `""` | `[OPT]` "No stack info configured -- subagents will not know the project's tech stack" |
| `[toolkit] remote_url` | `"git@github.com:user/claude-toolkit.git"` | `[OPT]` "Toolkit remote URL is still the example placeholder" |

**Auto-fix available**: For `[project] name`, offer to set it to the detected project name (from `detect-project.py`). For `stack_info`, offer to auto-generate from configured stacks.

#### H5.2: Auto-approve path relevance

Read the configured auto-approve write paths and check each glob pattern against the actual project structure:

```bash
# For each pattern like "*/app/*", check if the directory exists
ls -d app/ 2>/dev/null
```

Patterns that do not match any existing directory -> `[INFO]` ("Auto-approve path pattern '*/app/*' does not match any directory in this project -- it will have no effect until an 'app/' directory is created")

This is informational only -- the paths might be created later.

#### H5.3: Missing stack overlays

For each stack detected by `detect-project.py`, check if a corresponding stack overlay JSON exists at `.claude/toolkit/templates/stacks/<stack>.json`:

- Stack detected but no overlay file -> `[INFO]` ("No stack overlay found for detected stack '[name]' -- the toolkit does not yet have built-in support for this stack")
- Stack configured in toolkit.toml but overlay file missing -> `[WARN]` ("Stack '[name]' configured in toolkit.toml but no overlay file exists at templates/stacks/[name].json")

#### H5.4: Customized file drift

Read the manifest at `.claude/toolkit-manifest.json`. For each file marked as customized, compare the manifest's recorded `toolkit_hash` against the current toolkit source hash:

```bash
shasum -a 256 .claude/toolkit/<source_path> | cut -d' ' -f1
```

If the hash differs from the manifest's `toolkit_hash`, the toolkit source has changed since customization (drift):

- `[OPT]` ("Customized file '[path]' has upstream drift -- the toolkit source was updated since you customized it. Review upstream changes with `/toolkit-update` or re-customize from the new source.")

If the manifest does not exist, skip this check and report `[WARN]` ("Manifest not found -- cannot check for customization drift. Run `toolkit.sh init` to create a manifest.")

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

Check the exit code and stdout. Each unexpected result -> `[ERROR]` ("Hook '[hook]' returned unexpected result for '[category]' input: expected [expected], got exit code [actual]")

#### H6.2: Hook conflict detection

Analyze the logical relationship between guard hooks and auto-approve:

1. Read the auto-approve write paths from the toolkit config
2. Read the sensitive-write guard's deny patterns (from the hook source code -- look for patterns like `.env`, `credentials`, `.ssh`, `settings.json`)
3. Check if any auto-approve pattern would match a file that the guard would deny

For example, if auto-approve includes `*/.claude/*` and guard-sensitive-writes denies `.claude/settings.json`, that is a potential conflict where the auto-approve would approve a write that the guard would subsequently deny.

Each conflict found -> `[WARN]` ("Potential conflict: auto-approve pattern '[pattern]' overlaps with guard-sensitive-writes deny pattern for '[file]' -- the guard takes precedence, but the auto-approve entry is misleading")

#### H6.3: Hook timeout appropriateness

Read hook timeouts from `.claude/settings.json` (the `hooks` array, where each hook entry may have a `timeout` field):

- Guard hooks (names starting with `guard-`) with timeout > 30000ms -> `[INFO]` ("Guard hook '[name]' has a [N]s timeout -- guards should respond quickly")
- Task-completed gates with timeout < 60000ms -> `[INFO]` ("Task-completed gate has a [N]s timeout -- tests may need more time")
- Any hook with timeout > 300000ms -> `[INFO]` ("Hook '[name]' has a [N]s timeout -- this is unusually long")

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
> | 1 | H2 | Lint command '.venv/bin/ruff' not found -- .venv/ does not exist | Yes |
> | 2 | H3 | Required tool 'jq' not found | Manual: `brew install jq` |
>
> ### Warnings ([count])
>
> | # | Phase | Finding | Fix Available |
> | - | ----- | ------- | ------------- |
> | 1 | H1 | settings.json is stale -- hooks section differs | Yes |
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

## Error Handling

| Error | Recovery |
| ----- | -------- |
| `toolkit.sh doctor` fails entirely | Report `[ERROR]` with the error output. Ask user whether to continue with deeper analysis or abort. |
| `detect-project.py` fails | Skip H1.1 and H1.4 (stack and command comparison). Report `[WARN]` ("Detection script failed -- some coherence checks were skipped"). Continue with remaining phases. |
| toolkit.toml parse error | Report `[ERROR]` in H1.5. Skip H1.4 and H5.1 (these require parsed TOML). Continue with remaining phases. |
| CLAUDE.md does not exist | Skip Phase H4 entirely. Report `[INFO]` ("No project CLAUDE.md found"). |
| `.mcp.json` does not exist | Skip H3.1. Report `[INFO]` ("No .mcp.json found -- run `toolkit.sh generate-settings` to create one"). |
| Hook sample input test crashes | Report `[ERROR]` for the specific hook. Continue testing remaining hooks. |
| Manifest not found | Skip H5.4 (drift check). Report `[WARN]` ("Manifest not found -- cannot check for customization drift"). |
| settings.json does not exist | Skip H1.2 and H6.3 (settings freshness and timeout checks). Report `[WARN]`. |
