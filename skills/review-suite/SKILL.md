---
name: review
description: Use when code changes need review before merging or completing.
argument-hint: "[agent] [scope]"
user-invocable: true
---

# Review Suite Skill

Orchestrates code review agents for comprehensive analysis. Run single or multiple agents on various scopes.

## Aliases

```yaml
aliases:
  /review: /review-suite
  /r: /review-suite

defaults:
  agents: reviewer
  scope: uncommitted

shortcuts:
  thorough: --preset thorough
  pre-merge: --preset pre-merge
  spec-first: --preset spec-first
  all: --agents all
```

> **Customization**: Override defaults in `toolkit.toml` under `[skills.review-suite]`. Run `bash toolkit.sh customize skills/review-suite/SKILL.md` to take full ownership of this skill.

## Critical Rules (READ FIRST)

| Rule | Description |
| ---- | ----------- |
| **1. Evidence required for high/crit** | High and critical findings without file path, line number, and code snippet are downgraded to medium. |
| **2. No false positives** | Every finding must reference specific code; do not report hypothetical or speculative issues. |
| **3. Respect timeouts** | Timed-out agents are marked inconclusive, not passed; never silently drop a timeout. |
| **4. Scope bundle first** | Always resolve the scope via scope-resolver before launching any review agents. |
| **5. Deduplicate across agents** | Merge overlapping findings from different agents into a single entry in the review packet. |

### Rationalization Prevention

| Rationalization | Why It Is Wrong | Correct Behavior |
| --------------- | --------------- | ---------------- |
| "The code looks clean, no findings expected" | Pre-judging the outcome before running agents defeats the purpose of automated review; even clean-looking code has edge cases | Launch all configured agents on the resolved scope bundle; report whatever they find, including zero findings if that is the genuine result |
| "This is a style issue, not a bug" | Dismissing findings as style issues allows real quality problems to pass; severity classification is the agent's job, not the orchestrator's | Record the finding with the severity the agent assigned; only downgrade if the evidence rules require it (e.g., high without evidence becomes medium) |
| "No tests needed for this change" | The reviewer agent's gate criteria require test coverage for new public functions; skipping test review masks coverage gaps | Check the reviewer gate: if new public functions lack tests, mark the gate as failed; report the gap as a finding with `actionable: true` |
| "The agent timed out, so it probably found nothing" | Timed-out agents are inconclusive, not passing; treating a timeout as a pass hides potential issues | Mark the agent as `timed_out: true` with `gate_passed: null`; report partial findings and flag the timeout in the review packet summary |
| "This finding overlaps with another agent's finding, skip it" | Overlapping findings from different agents may have different evidence or severity; silent deduplication can lose the stronger evidence | Merge overlapping findings using the highest severity and most complete evidence from either agent; document both agents as sources |

---

## Usage

### Short Slash Commands

```bash
/review                    # reviewer on uncommitted (default)
/review my-feature         # reviewer on feature:my-feature
/review security           # security agent on uncommitted
/review qa:deep            # deep QA on uncommitted
/review all my-feature     # all 7 agents on feature:my-feature
/review thorough           # preset:thorough on uncommitted
/review spec-first         # preset:spec-first for spec compliance checking
/review architect          # deep architecture analysis (run infrequently)
/review commit-check       # fast post-commit sanity check on last commit
```

### Full Slash Command

```bash
/review-suite --agents reviewer --scope feature:my-feature
/review-suite --agents reviewer,qa,security --scope uncommitted
/review-suite --agents all --scope diffs:main..HEAD
/review-suite --agents qa:deep --scope feature:my-feature
/review-suite --preset thorough
/review-suite --preset pre-merge
/review-suite --preset spec-first
```

### Freeform Natural Language

```text
"review my feature"                         -> reviewer on feature scope
"security scan my changes"                  -> security on uncommitted
"deep test my feature"                      -> qa:deep on feature scope
"thorough qa and ux review on my feature"   -> qa + ux (thorough mode)
"full review this branch"                   -> all on diffs:main..HEAD
```

## Presets

| Preset | Agents | Mode |
| ------ | ------ | ---- |
| `default` | reviewer | smoke |
| `quick` | commit-check | smoke |
| `thorough` | reviewer, qa, security | thorough |
| `ux-docs` | ux, docs | smoke |
| `pre-merge` | all | thorough |
| `spec-first` | reviewer, docs, pm | thorough |

**When to use `spec-first`**: Use before implementation when working from a detailed spec or plan file. Catches spec drift, missing requirements, and documentation gaps. All 3 agents run in thorough mode focused on specification compliance rather than general code quality.

## Execution Flow

1. **Parse Arguments**
   - Extract agents, scope, mode from input
   - Apply defaults and presets

2. **Resolve Scope**
   - Call scope-resolver skill to get Scope Bundle
   - Captures: files, diff, risk_profile, entrypoints, commit_hash

3. **Launch Agents**
   - Read agent prompts from `.claude/agents/<name>.md`
   - Launch up to 3 agents in parallel via Task tool
   - Apply timeouts: smoke (10m), deep (60m)

4. **Collect Results**
   - Wait for all agents to complete
   - Enforce evidence requirements:
     - high/crit without evidence -> downgrade to med, actionable=false
     - bug without repro_steps -> actionable=false

5. **Merge into Review Packet**
   - Combine findings from all agents
   - Deduplicate overlapping findings
   - Sort by severity (crit -> high -> med -> low -> info)

6. **Write Artifacts**
   - Directory: `artifacts/<scope_slug>/<run_id>/`
     - `scope_bundle.json`
     - `review_packet.json`
     - `review_packet.md` (human-readable)
     - `<agent>_findings.json` (per-agent)
   - Update `latest` symlink

   **Directory Creation**: Use the Write tool directly - it auto-creates parent directories.
   Do NOT use `mkdir` with command substitution like `$(date ...)` as this causes permission prompts.
   Generate the run_id timestamp in your response (e.g., `YYYYMMDD-HHMMSS`) rather than via shell.

7. **Report Results**
   - Summary: findings count by severity
   - Gate status per agent: pass/fail/timeout/inconclusive
   - Link to artifacts

## Gate Criteria

| Agent | FAILS if... |
| ----- | ----------- |
| reviewer | crit/high actionable bug OR missing test for new public function |
| qa | Reproducible crash, broken nav, or failed smoke test |
| security | Secrets found OR high SAST issue |
| ux | Missing a11y id blocks automation OR screen reader nav |
| pm | (no gate - advisory only) |
| docs | README/install steps drift detected |
| architect | Critical resiliency issue OR severe architecture violation |

## Model Selection

**Note**: Subagents inherit the parent session's model by default. Use `/model sonnet` for cost savings.

**Model portability**: The model names below (haiku, sonnet, opus) represent version-agnostic performance tiers — fastest, balanced, and most capable respectively. As new model versions are released, these tier names remain valid. The table describes which tier each agent needs, not a pinned model version.

| Agent | Smoke Mode | Deep Mode | Rationale |
| ----- | ---------- | --------- | --------- |
| commit-check | haiku | haiku | Speed for background checks |
| security | haiku | sonnet | Tools do heavy lifting; sonnet correlates |
| docs | haiku | sonnet | String matching; sonnet sufficient |
| reviewer | (inherit) | opus | Bug/edge case finding benefits from opus |
| qa | (inherit) | opus | Complex test analysis benefits from opus |
| ux | (inherit) | opus | Nuanced a11y assessment benefits from opus |
| pm | (inherit) | opus | Thorough product analysis benefits from opus |
| architect | opus | opus | Always needs deep reasoning |

**Model behaviors**:

- `(inherit)`: Uses session model (opus/sonnet/haiku based on `/model` command)
- `haiku`: Always haiku regardless of session model (fastest, cheapest)
- `sonnet`: Always sonnet regardless of session model (balanced)
- `opus`: Always opus regardless of session model (most capable)

**Cost-saving tips**:

- Run `/model sonnet` before smoke reviews - inheriting agents will use sonnet
- Use smoke mode (default) for quick feedback
- Reserve deep mode for pre-merge or complex changes

**Override behavior**:

- `/review --model haiku` forces most agents to haiku (fast/cheap)
- **Exception**: architect always uses opus regardless of override (needs deep reasoning)

## Parallel Execution

| Config | Value |
| ------ | ----- |
| max_parallel_agents | 3 |
| smoke_timeout | 10 minutes |
| deep_timeout | 60 minutes |

### "Review All" Execution

When `--agents all` or "review all" is requested:

1. **Launch in batches** (respecting resource constraints):
   - Batch 1: reviewer, security, docs (no UI tools, run in parallel)
   - Batch 2: qa, then ux (UI tools - run sequentially if they share resources)
   - Batch 3: pm, architect (run in parallel)

2. **Mode applies to all agents**

3. **Example Task calls (smoke mode)**:

```python
# Batch 1 - launch in parallel
Task(subagent_type="reviewer", prompt="...", run_in_background=True)
Task(subagent_type="security", model="haiku", prompt="...", run_in_background=True)
Task(subagent_type="docs", model="haiku", prompt="...", run_in_background=True)

# Batch 2 (sequential for shared resources)
Task(subagent_type="qa", prompt="...")
Task(subagent_type="ux", prompt="...")

# Batch 3
Task(subagent_type="pm", prompt="...", run_in_background=True)
Task(subagent_type="architect", model="opus", prompt="...", run_in_background=True)
```

### Tool Coordination

Agents that use overlapping tools should not run simultaneously:

| Resource | Agents | Coordination |
| -------- | ------ | ------------ |
| Browser/Playwright | qa, ux | Can run in parallel (separate contexts) |
| Mobile simulator | qa, ux | Run sequentially |
| Security scanners | security, reviewer | Can run in parallel |

### Commit-Check Execution

When running the `commit-check` agent (via `/review commit-check` or preset `quick`):

1. **Scope**: Always uses the last commit (`diff:HEAD~1..HEAD`), ignoring the `--scope` argument
2. **Model**: Always haiku (fast background check)
3. **Timeout**: 60 seconds (hard limit for background checks)
4. **Output**: Status-based (`ok`/`warning`/`alert`) rather than severity-based findings
5. **Gate**: Advisory only — never blocks. `alert` status is highlighted to user, `warning` logged, `ok` silent

This agent is designed for fast post-commit sanity checks. For thorough review, use the `reviewer` agent.

### Timeout Handling

If agent times out:

- Mark `timed_out: true`
- Report partial findings with `severity: med`
- Do NOT count as gate pass — timed-out agents are treated as inconclusive

## Infrastructure Failures

If tooling fails (exit code 4):

- Mark `infra_failed: true`
- Set `gate_passed: null` (inconclusive)
- Report as environment issue, not product bug

## Keyword Mapping

### Agent Keywords

| Keyword | Agent |
| ------- | ----- |
| review, check, bugs | reviewer |
| test, qa | qa:smoke |
| deep test | qa:deep |
| security, secrets | security |
| ux, a11y, accessibility | ux |
| docs, documentation | docs |
| pm, product | pm |
| architect, architecture | architect |
| commit-check, sanity, quick | commit-check |
| all, full, everything | all |

### Scope Keywords

<!-- Customize these for your project's feature registry -->
Scope resolution uses the scope-resolver skill with your project's `features.json`.

**Diff Scopes**:

| Keyword | Scope |
| ------- | ----- |
| (none), changes, my changes | uncommitted |
| last commit | diff:HEAD~1 |
| this branch | diffs:main..HEAD |

## Review Packet Schema

The `review_packet.json` artifact uses this structure:

```json
{
  "run_id": "<YYYYMMDD-HHMMSS>",
  "scope": "feature:my-feature",
  "commit_hash": "abc1234",
  "agents_run": ["reviewer", "qa", "security"],
  "duration_ms": 45000,
  "summary": {
    "total_findings": 5,
    "by_severity": { "critical": 0, "high": 1, "medium": 3, "low": 1, "info": 0 },
    "gate_status": {
      "reviewer": "pass",
      "qa": "pass",
      "security": "fail"
    }
  },
  "findings": [
    {
      "id": "f-001",
      "agent": "security",
      "severity": "high",
      "type": "vulnerability",
      "summary": "SQL injection via unsanitized user input",
      "evidence": {
        "file": "src/db/queries.py",
        "line": 42,
        "snippet": "cursor.execute(f\"SELECT * FROM users WHERE id={user_id}\")"
      },
      "actionable": true,
      "gate_failing": true,
      "suggestion": "Use parameterized queries: cursor.execute('SELECT * FROM users WHERE id=?', (user_id,))"
    }
  ],
  "timed_out_agents": [],
  "infra_failed_agents": []
}
```

**Finding fields**:

| Field | Required | Description |
| ----- | -------- | ----------- |
| `id` | yes | Unique finding ID within the packet (e.g., `f-001`) |
| `agent` | yes | Which agent produced this finding |
| `severity` | yes | `critical`, `high`, `medium`, `low`, or `info` |
| `type` | yes | `bug`, `vulnerability`, `quality`, `a11y`, `docs`, `architecture`, `product` |
| `summary` | yes | One-line description of the issue |
| `evidence` | yes for high/crit | File path, line number, and code snippet |
| `actionable` | yes | `true` if the finding has a clear fix; `false` for informational |
| `gate_failing` | yes | `true` if this finding causes the agent's gate to fail |
| `suggestion` | no | Recommended fix |

**Evidence downgrade rule**: Findings with `severity: high` or `critical` that lack `evidence` are automatically downgraded to `medium` with `actionable: false`.

## Output

Returns a summary message with:

- Findings count by severity
- Gate status per agent
- Path to full review packet
- Any critical issues highlighted
