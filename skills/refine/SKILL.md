---
name: refine
description: Use when existing code needs iterative quality improvement.
argument-hint: '"scope or description" [--resume] [--max-iterations N]'
user-invocable: true
model: opus
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - TodoWrite
  - mcp__plugin_playwright_playwright__*
---

# Refine Skill

Iterative evaluate-fix-validate convergence loop. Evaluates code quality, fixes findings, validates fixes, and repeats until convergence.

## Aliases

```yaml
aliases:
  /refine: /refine
  /polish: /refine
  /iterate: /refine
  /loop: /refine

defaults:
  max_iterations: 8
  convergence_threshold: 2  # max new findings per iteration before plateau is detected
  deferred_drop_after: 2
```

> **Customization**: Override defaults in `toolkit.toml` under `[skills.refine]`. Run `bash toolkit.sh customize skills/refine/SKILL.md` to take full ownership of this skill.

## Usage

```bash
/refine my-feature                # Refine feature scope
/refine cross:backend             # Refine all backend code
/refine cross:tests               # Refine all tests
/refine cross:frontend            # Refine all frontend code
/refine "improve error handling"  # Natural language
/refine --resume                  # Resume last interrupted session
/refine my-feature --max-iterations 5 # Limit iterations
```

## Architecture

```text
+---------------------------------------------------------------------+
| REFINE ORCHESTRATOR |
|  |
| +---------+    +----------------------------------------------+ |
|  | Scope | ---> | ITERATION LOOP |  |
|  | Resolve |  |  |  |
| +---------+ | +---------+  +---------+  +-------------+ |  |
|  |  | Phase A |  | Phase B |  | Phase C |  |  |
|  |  | EVALUATE | -> | CONVERGE | -> | FIX |  |  |
|  |  | (Task()) |  | CHECK |  | (Task()) |  |  |
|  | +---------+  +----+----+  +------+------+ |  |
|  |  |  |  |  |
|  | +------+------+ +-----+-------+ |  |
|  |  | CONVERGED? |  | Phase D |  |  |
|  |  | -> Report |  | VALIDATE |  |  |
|  | +-------------+ | (reviewer |  |  |
|  |  | + qa) |  |  |
|  | +------+------+ |  |
|  |  |  |  |
|  | +------+------+ |  |
|  |  | Phase E |  |  |
|  |  | COMMIT |  |  |
|  | +------+------+ |  |
|  |  |  |  |
|  | +------+------+ |  |
|  |  | Phase F |  |  |
|  |  | UPDATE |  |  |
|  |  | STATE |  |  |
|  | +-------------+ |  |
| +----------------------------------------------+ |
|  |
| +--------------------------------------------------------------+ |
|  | CONVERGENCE REPORT |  |
|  | Clean-room verification -> Final summary |  |
| +--------------------------------------------------------------+ |
+---------------------------------------------------------------------+
```

## Scope Inference

The refine skill infers scope from keywords in the user's prompt. Scope resolution uses the project's feature registry (if available).

### Keyword Mapping

<!-- Customize these keyword mappings for your project -->

| Keywords in prompt | Inferred scope | Files |
| ------------------- | ---------------- | ------- |
| backend, server, python, service | `cross:backend` | `src/**/*.py` or `app/**/*.py` |
| tests, testing, pytest | `cross:tests` | `tests/**/*.py` |
| frontend, web, static, js | `cross:frontend` | `src/**/*.{js,ts}` or `app/static/**` |
| everything, all code | `cross:all` | combined |

### Explicit Scope

```bash
/refine feature:my-feature    # Explicit feature scope
/refine cross:backend         # Explicit cross-cutting scope
```

---

## State Management

All state is persisted to enable resume capability.

### State Directory

```text
artifacts/refine/<scope-slug>/<run-id>/
|-- state.json
|-- findings.json
|-- deferred.json
|-- iteration-1/
|   |-- eval-findings.json
|   |-- fix-summary.json
|   +-- validate-report.json
|-- iteration-2/
|   +-- ...
+-- convergence-report.md
```

---

## Execution Flow

### Step 0: Initialize

1. Parse arguments: scope, `--resume`, `--max-iterations`
2. If `--resume`, load state from latest run
3. If new run: resolve scope, create state, expand file globs
4. Check file count for large-scope chunking

### Step 1: Iteration Loop

For each iteration (1 to max_iterations):

#### Phase A: Evaluate (Fresh Agent)

Spawn a fresh Task() agent (opus model) to evaluate the scope.

**Agent evaluates for**:

- **Correctness**: Bugs, logic errors, edge cases, null handling
- **Code quality**: Dead code, unused imports, unclear naming, missing type hints
- **Consistency**: Pattern violations, style inconsistencies
- **Safety**: Missing error handling, unvalidated inputs
- **Test coverage**: Missing tests for complex logic
- **Documentation**: Missing/stale docstrings on public functions

**Agent output**: JSON array of findings with id, file, line, severity, category, description, suggestion, effort.

#### Phase B: Convergence Check

**Convergence signals** (ANY triggers convergence):

1. **Clean eval**: Zero new findings from Phase A
2. **Plateau**: Fewer than 2 new findings for 2 consecutive iterations
3. **All deferred**: All remaining findings are deferred
4. **No changes**: Phase C made zero code changes
5. **Max iterations**: Reached limit

#### Phase C: Fix (Fresh Agent)

Spawn a fresh Task() agent to fix findings.

**Fix prioritization**:

1. Critical and high severity first
2. Trivial and small effort preferred
3. Skip `large` effort findings (defer them)
4. Group fixes by file

#### Phase D: Validate

Run validation:

1. Project test command for changed files
2. Linter
3. If validation fails: fix failures (max 3 attempts)

#### Phase E: Commit

Stage only modified files and commit.

#### Phase F: Update State & Evolve Scope

1. Update state files
2. Drop findings deferred 2+ consecutive times
3. **Scope evolution** — discover and add related files:
   - **Discovery mechanism**: During Phase A (Evaluate) and Phase C (Fix), the agent may encounter imports, callers, or dependencies outside the current scope. Track these as candidate files.
   - **Module priority**: Prefer files in the same module/directory as existing scope files. Files in unrelated modules are lower priority and should only be added if they have direct dependency relationships.
   - **Per-iteration limit**: Add at most **10 new files** per iteration to avoid scope explosion.
   - **Total limit**: The scope may grow by at most **30 files** across all iterations combined (tracked in `state.json` as `scope_additions_total`). Once this limit is reached, no further files are added.
   - **Reporting**: Log each scope addition with the reason (e.g., "Added `utils/helpers.py` — imported by `services/auth.py` which is in scope").

---

## Convergence Intelligence

### Clean Eval

The strongest signal. If a fresh evaluator finds nothing, the scope is clean.

### Plateau Detection

Track `new_findings` per iteration. If last 2 iterations both had fewer than `convergence_threshold` (default: 2) new findings, diminishing returns have been reached. The threshold means "max new findings per iteration" — if an iteration produces fewer new findings than this value, it counts toward the plateau signal.

### Deferred Findings Lifecycle

```text
Finding F003 in iteration 1 -> deferred (count: 1)
Finding F003 in iteration 2 -> deferred again (count: 2)
Finding F003 in iteration 3 -> DROPPED (exceeded threshold)
```

---

## Clean-Room Verification

**Mandatory** when convergence is reached. Spawn a separate, fresh agent that:

1. Reads current state of all files (post-fixes)
2. Evaluates independently (same criteria as Phase A)
3. Reports any remaining issues

### Clean-Room Outcome Handling

| Issues Found | Action |
| ------------ | ------ |
| **0 issues** | Pass immediately. Convergence confirmed — proceed to final report. |
| **1-3 issues** | Fix inline (the clean-room agent fixes them directly), then re-verify with a second clean-room round. |
| **4+ issues** | Fail the milestone. Do NOT attempt to fix — the scope has not converged. Log the issues, escalate to the user, and recommend running another full `/refine` pass with adjusted scope or parameters. |

### Termination

Maximum **2 clean-room rounds**. After 2 rounds:

- If issues persist (1+ remaining after round 2), report them in the convergence report as "unresolved clean-room findings" and conclude. Do not start a 3rd round.
- The convergence report should clearly indicate whether clean-room verification passed (0 issues) or ended with residual findings.

---

## Large Scope Handling

For scopes with 61+ files:

1. Split into chunks of ~25 files each
2. Group by directory/module to keep related files together
3. Run Phase A in parallel (one eval agent per chunk)
4. Merge findings and deduplicate

---

## Convergence Report

Generated at convergence. Saved to `artifacts/refine/<scope-slug>/<run-id>/convergence-report.md`.

Includes: scope, summary, iteration history, clean-room verification results, deferred findings, files modified, commits.

---

## Error Handling

| Error | Recovery |
| ------- | ---------- |
| Eval agent fails | Retry once; if 2 consecutive failures, stop |
| Fix agent fails | Defer unfixed findings, continue |
| Validation fails | Max 3 fix attempts; if still failing, revert and defer |
| State corruption | Start fresh with same scope |
| Context exhaustion | Write state, produce partial report, resume later |

---

## Diff from /review

| Aspect | /review | /refine |
| -------- | --------- | --------- |
| Evaluation | Single pass | Multiple iterations |
| Fixes | Reports findings only | Fixes findings automatically |
| Convergence | N/A | Detects when scope is clean |
| Commits | None | One per iteration |
| Clean-room | No | Mandatory verification |
| State | Stateless | Persisted, resumable |
| Scope | Feature or diff | Feature, cross-cutting, or custom |
