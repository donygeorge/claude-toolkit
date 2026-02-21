# Selective Agent Installation — Implementation Plan

> **Status**: In Review
>
> **Last Updated**: 2026-02-21
>
> **Target Version**: 1.15.0

## Summary

Add `[agents]` configuration to `toolkit.toml` that controls which agent definitions are installed into `.claude/agents/` (and thus loaded into the system prompt). Currently all 10 agents (~49KB) are always installed. The default will be a minimal set (`reviewer`, `commit-check` — ~8.5KB), an **83% reduction**. Skills will gracefully fall back to reading agent prompts from the toolkit source directory when an agent is not installed.

## North Star

A fresh toolkit installation consumes less than 10KB of system prompt for agents, while still supporting all skill workflows via on-demand agent loading.

## Principles

1. **Backward compatible** — existing installations keep working without config changes
2. **Opt-in reduction** — new installs get the lean default; existing installs are only modified when users add the config
3. **Skills always work** — uninstalled agents are loaded on-demand by skills via the general-purpose subagent fallback
4. **Minimal diff** — change the installation/loading path, not the agent prompts themselves

## Research Findings

### Current State (verified 2026-02-21)

| Agent | Size | Primary Consumer |
| ----- | ---- | ---------------- |
| architect.md | 7.5KB | review-suite |
| plan.md | 6.5KB | plan skill |
| reviewer.md | 5.5KB | review-suite (default) |
| qa.md | 5.4KB | review-suite, implement |
| ux.md | 5.4KB | review-suite, implement |
| security.md | 5.3KB | review-suite |
| pm.md | 4.2KB | review-suite |
| docs.md | 4.0KB | review-suite |
| commit-check.md | 3.0KB | review-suite (quick preset) |
| gemini.md | 2.1KB | brainstorm (reads via Read tool, not subagent_type) |
| **Total** | **48.9KB** | |

### How Agents Are Used by Skills

| Skill | Agent Usage | subagent_type? |
| ----- | ----------- | -------------- |
| review-suite | Reads from `.claude/agents/<name>.md`, spawns via `Task(subagent_type="<name>")` | **Yes** — needs agents in `.claude/agents/` |
| brainstorm | Reads `agents/gemini.md` via Read tool, uses custom persona prompts | No — uses general-purpose |
| implement | Spawns milestone agents via `Task(subagent_type="general-purpose")` | No |
| loop | Spawns evaluate/fix agents via `Task(subagent_type="general-purpose")` | No |
| plan | Uses plan agent via `Task(subagent_type="plan")` | **Yes** — needs plan agent, but plan skill can be updated |

### Context Cost Comparison

| Strategy | System Prompt | Per-Invocation (installed) | Per-Invocation (fallback) |
| -------- | ------------- | ------------------------- | ------------------------ |
| Custom subagent_type (agent in .claude/agents/) | agent size added | ~1KB (just task description) | N/A |
| general-purpose fallback (agent NOT installed) | 0KB | N/A | ~10KB (Read + Task prompt) |

### Migration Behavior

| Scenario | Behavior |
| -------- | -------- |
| **New project** (`toolkit.sh init`) | Default `["reviewer", "commit-check"]` — lean install |
| **Existing project** (`toolkit.sh update`, no `[agents]` config) | Keep all existing agents, print migration hint |
| **Existing project** (`toolkit.sh update`, has `[agents]` config) | Apply config, clean up removed agents (unless customized) |

## Architecture

### Config Flow

```
toolkit.toml [agents].install
    |
generate-config-cache.py -> TOOLKIT_AGENTS_INSTALL env var
    |
_init_agents() / _refresh_symlinks() -- filter by install list
    |
.claude/agents/ -- only selected agents symlinked
```

### Skill Fallback Flow

```
review-suite tries: Task(subagent_type="reviewer")
    |
Does .claude/agents/reviewer.md exist?
    YES -> use custom subagent_type (efficient)
    NO  -> Read .claude/toolkit/agents/reviewer.md
           -> Task(subagent_type="general-purpose", prompt=<agent content + task>)
```

### Key Files

| File | Change |
| ---- | ------ |
| `generate-config-cache.py` | Add `agents.install` to SCHEMA |
| `hooks/_config.sh` | Add `TOOLKIT_AGENTS_INSTALL` default |
| `templates/toolkit.toml.example` | Add `[agents]` section |
| `lib/cmd-init.sh` | Filter `_init_agents()` by install list |
| `lib/cmd-update.sh` | Filter `_refresh_symlinks()`, clean up removed agents |
| `skills/review-suite/SKILL.md` | Add agent resolution with fallback logic |
| `lib/cmd-validate.sh` | Only check symlinks for installed agents |
| `lib/cmd-doctor.sh` | Report agent context budget |
| `lib/cmd-status.sh` | Show installed vs available agents |
| `lib/cmd-explain.sh` | Add agent context topic |
| `VERSION` | Bump to 1.15.0 |
| `CHANGELOG.md` | Add feature entry |

## Implementation Milestones

### M0: Add `[agents]` Config Section and Schema

Add the config infrastructure for agent selection without changing any installation behavior yet.

**Files to modify**:

- `generate-config-cache.py` — Add to SCHEMA dict (after line 130, the `"notifications"` block):

  ```python
  "agents": {
      "install": list,
  },
  ```

- `hooks/_config.sh` — Add default after line 103 (the skills section):

  ```bash
  # Agents
  TOOLKIT_AGENTS_INSTALL="${TOOLKIT_AGENTS_INSTALL:-[\"reviewer\",\"commit-check\"]}"
  ```

- `templates/toolkit.toml.example` — Add new section before the `[hooks.setup]` section (after the `[project]` block, around line 25):

  ```toml
  # ---------------------------------------------------------------------------
  # [agents] — Agent installation configuration
  # ---------------------------------------------------------------------------
  [agents]
  # Which agents to install in .claude/agents/ (loaded into Claude's system prompt).
  # Agents NOT installed are still available on-demand via skills (e.g., /review security).
  # Values: list of agent names (without .md extension)
  # Special values: ["all"] installs all agents, ["none"] installs no agents
  # Default: ["reviewer", "commit-check"]
  # Available: reviewer, qa, security, ux, pm, docs, architect, commit-check, plan, gemini
  install = ["reviewer", "commit-check"]
  ```

- `tests/fixtures/sample-toolkit.toml` — Add `[agents]` section with `install = ["reviewer", "commit-check"]`

- `tests/test_generate_config_cache.py` — Add test verifying `TOOLKIT_AGENTS_INSTALL` appears in generated output and schema accepts the new key

**Exit Criteria**:

- [x] `python3 generate-config-cache.py --validate-only --toml tests/fixtures/sample-toolkit.toml` exits 0
- [x] Generated cache contains `TOOLKIT_AGENTS_INSTALL='["reviewer","commit-check"]'`
- [x] `python3 -m pytest tests/test_generate_config_cache.py -v` passes
- [x] `shellcheck -x -S warning hooks/_config.sh` passes

---

### M1: Make `_init_agents()` Respect Config

Only symlink agents listed in `agents.install` during init.

**Files to modify**:

- `lib/cmd-init.sh` — Rewrite `_init_agents()` (lines 34-63):

  - Read install list from toolkit.toml via `_read_toml_array "$toml_file" "agents.install"`
  - If the `[agents]` key doesn't exist (returns empty), use default list: `reviewer` and `commit-check`
  - Handle magic values: if list contains `all`, iterate all agents; if list contains `none`, skip all
  - For each agent in `toolkit/agents/`, check if its name (without .md) is in the install list
  - Only symlink/copy agents that pass the filter
  - Log skipped agents: `_info "Skipping agents/<name>.md (not in agents.install)"`

  Existing helper functions to reuse:

  - `_read_toml_array()` in `toolkit.sh` line 95 — reads TOML arrays as newline-separated values
  - `_read_toml_value()` in `toolkit.sh` line 81 — reads single TOML values

- `lib/cmd-init.sh` — Update `_init_agents_dry_run()` (lines 504-517) with the same filtering logic

- `lib/cmd-init.sh` — Keep `_init_agent_memory()` (lines 184-204) creating memory dirs for ALL agents (memory dirs are negligible in size and needed for fallback path)

**Exit Criteria**:

- [x] `toolkit.sh init --from-example --dry-run` shows only `reviewer.md` and `commit-check.md` as agents to symlink
- [x] `toolkit.sh init --from-example` creates symlinks only for configured agents
- [x] With `install = ["all"]` in toml, all 10 agents are symlinked
- [x] With `install = ["none"]` in toml, no agents are symlinked
- [x] Agent memory directories are created for ALL agents regardless of install list
- [x] `shellcheck -x -S warning lib/cmd-init.sh` passes

---

### M2: Make `_refresh_symlinks()` Config-Aware

Update handles selective agent refresh and cleanup of deinstalled agents.

**Files to modify**:

- `lib/cmd-update.sh` — Modify `_refresh_symlinks()` (lines 11-68):

  - Read install list from toolkit.toml (same logic as M1)
  - **Migration check**: If `[agents]` key doesn't exist in toolkit.toml, treat as `all` for backward compatibility (do NOT remove any existing agents)
  - If `[agents]` key DOES exist, apply it:
    - Only refresh/create symlinks for agents in the install list
    - Remove agent files from `.claude/agents/` that are NOT in the list, unless they are marked `customized` in the manifest (preserve those with a warning)
  - Log cleanup: `_ok "Removed agents/<name>.md (no longer in agents.install)"`
  - Log preservation: `_warn "Agent <name> not in agents.install but is customized — keeping"`

  **Important distinction**: In `_init_agents()` (M1), the default for no config is `["reviewer", "commit-check"]` (new projects). In `_refresh_symlinks()` (this milestone), the default for no config is `all` (backward compat for existing projects).

- `lib/cmd-update.sh` — In `cmd_update()` (after line 182 where `_refresh_symlinks` is called), add a migration hint:

  ```bash
  # Migration hint for legacy installs
  # If no [agents] section exists AND all 10 agents are in .claude/agents/:
  #   _info "Tip: Add [agents] section to toolkit.toml to reduce context overhead"
  #   _info "  Default agents.install = [\"reviewer\", \"commit-check\"] saves ~40KB of context"
  ```

**Exit Criteria**:

- [ ] `toolkit.sh update` on a project WITHOUT `[agents]` config keeps all existing agents
- [ ] `toolkit.sh update` on a project WITH `agents.install = ["reviewer"]` removes other agent symlinks
- [ ] Customized agents are preserved even when removed from the install list
- [ ] Migration hint is printed when no `[agents]` config exists and all 10 agents present
- [ ] `shellcheck -x -S warning lib/cmd-update.sh` passes

---

### M3: Update review-suite Skill for General-Purpose Fallback

When a requested agent is not installed, the skill loads the agent prompt from the toolkit source and uses `general-purpose` subagent type.

**Files to modify**:

- `skills/review-suite/SKILL.md` — Modify the "Execution Flow" section, specifically step 3 "Launch Agents" (around line 115-118). Replace the current text with an expanded "Agent Resolution" section:

  ```
  3. **Resolve and Launch Agents**
     For each agent to launch, determine the loading strategy:

     **If installed** (`.claude/agents/<name>.md` exists):
     - Use `Task(subagent_type="<name>", prompt="<scope bundle>", ...)`
     - This is the most efficient path (~1KB context per agent)

     **If not installed** (file does NOT exist in `.claude/agents/`):
     - Read the agent prompt from `.claude/toolkit/agents/<name>.md` using the Read tool
     - Launch with `Task(subagent_type="general-purpose", prompt="<full agent prompt content>\n\n---\n\n<scope bundle and task instructions>")`
     - This uses more context per invocation (~10KB) but avoids always-on system prompt cost
     - Log: "Agent <name> not installed -- using general-purpose fallback"

     Launch up to 3 agents in parallel via Task tool
  ```

- `skills/review-suite/SKILL.md` — Update the example Task calls in "Review All" Execution section (around lines 214-229) to show both paths:

  ```python
  # If agent IS installed in .claude/agents/:
  Task(subagent_type="reviewer", prompt="...", run_in_background=True)

  # If agent is NOT installed (fallback):
  # First: Read(".claude/toolkit/agents/reviewer.md") to get agent prompt
  # Then: Task(subagent_type="general-purpose", prompt="<agent prompt>\n\n---\n\n...", run_in_background=True)
  ```

**No changes needed for other skills** — brainstorm already uses general-purpose, implement and loop use general-purpose, plan skill's usage is through the plan agent which is an optional install.

**Exit Criteria**:

- [ ] review-suite SKILL.md documents both the installed and fallback paths
- [ ] Example Task calls show both patterns
- [ ] Existing skill test assertions still pass
- [ ] The SKILL.md remains generic (no project-specific content)

---

### M4: Update Diagnostic Commands

Make validate, doctor, status, and explain agent-config-aware.

**Files to modify**:

- `lib/cmd-validate.sh` — Modify symlink check loop (lines 64-89):

  - Read agent install list from toolkit.toml
  - Only check agent symlinks for agents in the install list
  - Add a new check: warn about "orphaned" agents in `.claude/agents/` that are NOT in the install list (consuming context unnecessarily)

- `lib/cmd-doctor.sh` — Add a new check section (after section 9 "Symlink health", before section 10 "Manifest health"):

  - Count installed agent files and sum their sizes
  - Report: `"Agent context: X.XKB (N of 10 agents installed)"`
  - Warn if total exceeds 20KB: `"Consider reducing agents.install to save context"`
  - Also update the existing symlink health check (section 9, lines 228-253) to only count agent symlinks that should exist per the config

- `lib/cmd-status.sh` — Add agent info section after the "Available stacks" block (after line 57):

  - Read install list from toolkit.toml
  - Print installed agents with sizes
  - Print available (not installed) agents

- `lib/cmd-explain.sh` — Update the `agents` topic (lines 55-73):

  - Add information about the `[agents]` config section
  - Explain the context trade-off (always-on system prompt cost vs on-demand loading)
  - Mention the general-purpose fallback mechanism for skills
  - Update the topic list on line 20 and line 164

**Exit Criteria**:

- [ ] `toolkit.sh validate` does not report false errors for intentionally uninstalled agents
- [ ] `toolkit.sh validate` warns about orphaned agents not in config
- [ ] `toolkit.sh doctor` reports agent context budget with size and count
- [ ] `toolkit.sh status` shows installed vs available agents
- [ ] `toolkit.sh explain agents` mentions the `[agents]` config
- [ ] `shellcheck -x -S warning lib/cmd-validate.sh lib/cmd-doctor.sh lib/cmd-status.sh lib/cmd-explain.sh` passes

---

### M5: Update Tests

Ensure all new behavior is tested and existing tests are updated for the new defaults.

**Files to modify**:

- `tests/test_toolkit_cli.sh` — Add new test cases:

  - Test: init with default config installs only `reviewer.md` and `commit-check.md` (verify with `ls .claude/agents/`)
  - Test: init with `agents.install = ["all"]` installs all 10 agents
  - Test: init with `agents.install = ["none"]` installs no agents
  - Test: init with `agents.install = ["reviewer", "security"]` installs exactly those two
  - Test: dry-run shows correct agents based on config
  - Update any existing tests that assert all 10 agents are symlinked — these need to account for the new default

- `tests/test_generate_config_cache.py` — Add tests:

  - Test: `[agents]` section validates correctly
  - Test: `agents.install` accepts a list of strings
  - Test: unknown key under `[agents]` is rejected by schema validation

- `tests/test_toolkit_cli.sh` — Add update-specific tests (if the test infrastructure supports update simulation):

  - Test: update without `[agents]` config keeps all existing agents
  - Test: update with `agents.install = ["reviewer"]` removes non-listed agents

**Exit Criteria**:

- [ ] `bash tests/test_toolkit_cli.sh` passes with new tests
- [ ] `python3 -m pytest tests/test_generate_config_cache.py -v` passes
- [ ] No existing tests broken by the new defaults
- [ ] `bash tests/test_manifest.sh` still passes

---

### M6: Version Bump, CHANGELOG, and Documentation

**Files to modify**:

- `VERSION` — Change `1.14.0` to `1.15.0`

- `CHANGELOG.md` — Add under `[Unreleased]`:

  ```markdown
  ### Added

  - **Selective agent installation**: New `[agents]` section in `toolkit.toml` controls which agents are installed into `.claude/agents/`. Default installs only `reviewer` and `commit-check` (~8.5KB vs ~49KB for all 10 agents — 83% context reduction). Skills automatically fall back to on-demand loading for uninstalled agents. Existing installations are unaffected until the config is explicitly added.
  ```

- `docs/reference.md` — Add `[agents]` configuration reference (find the appropriate section for config documentation):

  ```markdown
  ### [agents] — Agent Installation

  | Key | Type | Default | Description |
  | --- | ---- | ------- | ----------- |
  | `install` | list | `["reviewer", "commit-check"]` | Agent names to install in `.claude/agents/`. Special values: `["all"]` or `["none"]`. |

  Available agents: `reviewer`, `qa`, `security`, `ux`, `pm`, `docs`, `architect`, `commit-check`, `plan`, `gemini`
  ```

- `CLAUDE.md` — No changes needed (agent counts and structure descriptions remain accurate)

**Exit Criteria**:

- [ ] `cat VERSION` outputs `1.15.0`
- [ ] CHANGELOG.md has the new feature entry under `[Unreleased]`
- [ ] `docs/reference.md` documents the `[agents]` config section
- [ ] All documentation is accurate and consistent

---

### M7: Final Verification

Run the full test suite and validate everything works end-to-end.

**Commands to run** (each must exit 0):

1. `python3 -m pytest tests/ -v` — all Python tests pass
2. `bash tests/test_toolkit_cli.sh` — all CLI tests pass (including new agent selection tests)
3. `bash tests/test_hooks.sh` — all hook tests pass
4. `bash tests/test_manifest.sh` — all manifest tests pass
5. `bash tests/test_skills.sh` — all skill tests pass
6. `shellcheck -x -S warning hooks/*.sh lib/*.sh toolkit.sh` — clean

**Manual verification**:

1. Create a scratch directory, run `toolkit.sh init --from-example`, verify only `reviewer.md` and `commit-check.md` exist in `.claude/agents/`
2. Modify the scratch project's toolkit.toml to `agents.install = ["all"]`, run `toolkit.sh init --force`, verify all 10 agents exist
3. Change to `agents.install = ["reviewer"]`, verify that the review-suite SKILL.md describes the fallback behavior

**Exit Criteria**:

- [ ] All 6 test/lint commands exit with code 0
- [ ] Manual verification confirms correct agent installation behavior
- [ ] `cat VERSION` outputs `1.15.0`

## Testing Strategy

### Automated Tests

- Full pytest suite (314+ tests) — schema validation and config cache generation
- CLI integration tests (67+ tests) — init/update agent selection behavior
- Hook integration tests (50 assertions) — _config.sh default works
- Manifest integration tests (27+ tests) — manifest tracks installed state
- Skill integration tests (89+ tests) — skill references remain valid

### Manual Verification

- Fresh init in scratch project — verify agent count in `.claude/agents/`
- Review-suite skill documentation — verify fallback instructions are clear
- Existing project update — verify no agents are removed without explicit config

## Risks & Mitigations

| Risk | Mitigation |
| ---- | ---------- |
| Breaking existing installations on update | `_refresh_symlinks()` defaults to `all` when no `[agents]` config exists — existing installs are never modified |
| Skills fail when agent not installed | Fallback path documented in review-suite SKILL.md — Claude reads from toolkit dir and uses general-purpose |
| Users confused about missing agents | `toolkit.sh status` shows installed vs available; `toolkit.sh explain agents` explains the trade-off |
| Customized agents accidentally removed | Manifest-tracked customized agents are always preserved, even if removed from install list |
| Test count regressions from test changes | Run full test suite in M7 verification; specific exit criteria per milestone |

## Open Questions

None — all decisions resolved during planning.

---

## Evaluation Criteria

After all milestones are complete, the implementation is successful if:

### Functional Correctness

1. **Default lean install**: `toolkit.sh init --from-example` installs only 2 agents (~8.5KB)
2. **Config respected**: `agents.install` list controls which agents appear in `.claude/agents/`
3. **Magic values**: `["all"]` and `["none"]` work correctly
4. **Backward compatible**: Update on existing projects without `[agents]` config preserves all agents
5. **Skill fallback**: review-suite SKILL.md documents both installed and general-purpose fallback paths
6. **Migration hint**: Update prints guidance for legacy installs with all 10 agents

### Code Quality

1. **Shellcheck clean**: Zero warnings on all .sh files
2. **All tests pass**: Across all test suites
3. **Schema validated**: `generate-config-cache.py` accepts the new `[agents]` section

### User Experience

1. **83% context reduction** for new installations (49KB to 8.5KB)
2. **Clear diagnostics**: `status`, `doctor`, `validate` all report agent context information
3. **Self-documenting**: `explain agents` describes the config and trade-offs
