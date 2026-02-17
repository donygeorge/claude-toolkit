# Toolkit Hardening — Comprehensive Implementation Plan

> **Status**: Draft
>
> **Last Updated**: 2026-02-16
>
> **Source**: 4-agent review (Architect, Prototyper, QA, Security)
>
> **Dependency**: Incorporates [streamline-bootstrap-setup.md](streamline-bootstrap-setup.md) as M6 (M0-M4 now implemented)

## Summary

Address 47 findings from a 4-agent deep review (Senior Architect, DX Prototyper, Senior QA, Security Engineer) covering long-term maintainability, developer experience, quality gaps, and security vulnerabilities. Organized into 7 incremental milestones, each a mergeable PR.

**Note**: The [streamline-bootstrap-setup plan](streamline-bootstrap-setup.md) (M0-M4) has been fully implemented. This adds `detect-project.py`, a simplified `bootstrap.sh`, a comprehensive `/setup-toolkit` skill, `BOOTSTRAP_PROMPT.md`, and updated `CLAUDE.md.template`. The test count has grown from 126 to 214+ pytest tests. M6 section 6.1 is now complete; sections 6.2-6.4 remain.

## Findings Reference

| ID | Severity | Title | Milestone |
|----|----------|-------|-----------|
| C1 | Critical | No tests for hook scripts | M1 |
| C2 | Critical | Command injection via unquoted variables in hooks | M1 |
| C3 | Critical | Config cache injection (TOML → bash) | M2 |
| C4 | Critical | Race conditions in concurrent hook execution | M2 |
| H1 | High | Monolithic toolkit.sh (~1027 lines) | M4 |
| H2 | High | Too many onboarding steps / no single-command setup | M6 (resolved by bootstrap-setup) |
| H3 | High | Duplicated pattern matching across hooks | M3 |
| H4 | High | No schema validation for settings merge output | M5 |
| H5 | High | No integrity verification for updates | M5 |
| H6 | High | macOS Bash 3.2 compatibility not enforced | M3 |
| H7 | High | Error messages inconsistent and sometimes cryptic | M3 |
| H8 | High | Guard hook bypass via settings manipulation | M2 |
| H9 | High | Temp file handling inconsistencies | M2 |
| H10 | High | Cognitive load / too many concepts | M6 (partially addressed by bootstrap-setup) |
| H11 | High | Missing `set -euo pipefail` in several hooks | M1 |
| M1 | Medium | No plugin/extension architecture for hooks | M7 |
| M2 | Medium | Stack system limited and hard to extend | M7 |
| M3 | Medium | `_config.sh` re-sourced on every hook invocation | M7 |
| M4 | Medium | Manifest corruption handling missing | M5 |
| M5 | Medium | Settings merge doesn't handle array deduplication correctly | M5 |
| M6 | Medium | No audit logging for guard decisions | M2 |
| M7 | Medium | Python scripts don't validate TOML structure deeply | M2 |
| M8 | Medium | File permissions not hardened | M2 |
| M9 | Medium | No dry-run / preview mode | M5 |
| M10 | Medium | README too long for quick reference | M6 (partially addressed — Quick Start added, still 400+ lines) |
| M11 | Medium | Hook output format not standardized | M3 |
| M12 | Medium | No health check / self-test command | M5 |
| M13 | Medium | smart-context framework tightly coupled | M7 |
| L1 | Low | Inconsistent shebang lines | M3 |
| L2 | Low | No changelog automation | M7 |
| L3 | Low | Agent prompts could use version pinning | M7 |
| L4 | Low | No telemetry / usage analytics | M7 |
| L5 | Low | git subtree merge conflicts | M5 |
| L6 | Low | Missing .editorconfig | M3 |
| L7 | Low | Python test fixtures duplicated | M7 |
| L8 | Low | No CONTRIBUTING.md | M6 |

---

## M1: Hook Security Hardening + Test Framework

**Goal**: Fix the two most critical security issues and establish the hook test framework so all subsequent milestones have a safety net.

**Addresses**: C1, C2, H11

**PR scope**: ~400 lines new, ~100 lines modified

### 1.1 Add `set -euo pipefail` consistency audit

**Files to modify**: All 16 hooks in `hooks/`

Hooks intentionally omit strict mode so they degrade gracefully (exit 0 on error). However, they should still use `set -u` (undefined variable check) to catch typos. The approach:

- Add `set -u` to all hooks that lack it (prevents silent undefined var bugs)
- Do NOT add `set -e` or `set -o pipefail` to hooks (they must degrade gracefully)
- Add `set -euo pipefail` only to `lib/manifest.sh` and `toolkit.sh` (already present)
- Document the rationale in a comment header block

**For each hook, verify**:
- [ ] Has `set -u` (or documents why not)
- [ ] All variables have defaults via `${VAR:-default}` pattern
- [ ] No undefined variable can silently produce wrong results

### 1.2 Fix command injection via unquoted variables

**Files to modify**: `hooks/guard-destructive.sh`, `hooks/auto-approve-safe.sh`, `hooks/post-edit-lint.sh`, `hooks/task-completed-gate.sh`, `hooks/guard-sensitive-write.sh`, `hooks/classify-error.sh`

Audit every hook for unquoted `$VARIABLE` usage in command contexts:

- **guard-destructive.sh**: Lines 49-131 — `echo "$COMMAND" | grep` is fine (COMMAND is quoted in echo), but the `grep -qE "$CRITICAL_PATHS"` on line 90 should use single quotes for the regex pattern since it's a literal
- **post-edit-lint.sh**: `$RESOLVED_FMT "$FILE_PATH"` — FILE_PATH from JSON input. Ensure FILE_PATH is validated (no `..` traversal, must be under project dir)
- **task-completed-gate.sh**: `xargs $LINT_CMD` — LINT_CMD comes from config, intentional word splitting. Add shellcheck disable comment and document the design choice
- **deny() helper** (line 41): The printf fallback doesn't escape `$REASON` — a reason containing `%s` or `\n` could break formatting. Use `%s` formatting correctly

**Specific fixes**:

```bash
# guard-destructive.sh line 90 — use variable but quote it
if echo "$COMMAND" | grep -qE "$CRITICAL_PATHS"; then

# post-edit-lint.sh — validate FILE_PATH
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
# Reject paths with .. or absolute paths outside project
case "$FILE_PATH" in
  *..* | /*) exit 0 ;;  # Skip — suspicious path
esac

# deny() fallback — already correct since printf %s handles it, but
# ensure REASON doesn't contain format specifiers by using %s properly
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
```

### 1.3 Create hook test framework

**Files to create**: `tests/test_hooks.sh` (~300 lines)

Create a bash test framework for hooks. Pattern: mock Claude Code inputs (JSON on stdin + env vars), run hooks, assert on exit code and stdout/stderr.

**Test harness pattern**:

```bash
#!/usr/bin/env bash
# Hook integration tests
set -euo pipefail

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TOOLKIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

_test() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -n "  TEST: $name ... "
}

_pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "PASS"
}

_fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1"
}

_run_hook() {
  local hook="$1"
  local input="$2"
  # Set up minimal environment
  export CLAUDE_PROJECT_DIR="$TEST_PROJECT_DIR"
  echo "$input" | bash "$TOOLKIT_DIR/hooks/$hook" 2>/dev/null
}
```

**Tests to include (minimum)**:

Guard-destructive tests:
- [ ] Blocks `git push`
- [ ] Blocks `git reset --hard`
- [ ] Blocks `rm -rf .`
- [ ] Blocks `rm -rf src/`
- [ ] Blocks `eval` commands
- [ ] Blocks pipe-to-shell (`| bash`)
- [ ] Allows safe commands (`git status`, `ls`, `echo`)
- [ ] Allows non-Bash tools (exit 0 for Read, Write, etc.)
- [ ] Respects `TOOLKIT_GUARD_ENABLED=false`

Auto-approve tests:
- [ ] Auto-approves Read/Glob/Grep tools
- [ ] Auto-approves safe bash commands (ls, cat, grep)
- [ ] Does NOT auto-approve git commit/add/push
- [ ] Does NOT auto-approve npx
- [ ] Does NOT auto-approve curl
- [ ] Auto-approves configured write paths
- [ ] Rejects writes outside project scope

Guard-sensitive-write tests:
- [ ] Blocks writes to `.env`
- [ ] Blocks writes to `credentials.json`
- [ ] Allows writes to normal source files

Edge cases:
- [ ] Empty JSON input doesn't crash any hook
- [ ] Missing jq falls back gracefully (or exits 0)
- [ ] Malformed JSON doesn't crash hooks
- [ ] File paths with spaces handled correctly
- [ ] File paths with special characters handled correctly

### Exit Criteria

- [ ] All 16 hooks have `set -u` or documented exception
- [ ] All unquoted variables in command contexts are fixed
- [ ] `shellcheck -x -S warning hooks/*.sh` passes
- [ ] `tests/test_hooks.sh` exists with 20+ test cases
- [ ] All hook tests pass
- [ ] Existing Python tests still pass: `python3 -m pytest tests/ -v`

---

## M2: Security Hardening

**Goal**: Fix config cache injection, race conditions, guard bypass, temp file issues, and add audit logging.

**Addresses**: C3, C4, H8, H9, M6, M7, M8

**PR scope**: ~250 lines modified, ~100 lines new

### 2.1 Harden config cache generation

**Files to modify**: `generate-config-cache.py`

The current `_escape_for_shell()` only escapes single quotes. This is correct for single-quoted strings, but add defense-in-depth:

- **Validate TOML keys**: Keys become bash variable names (`TOOLKIT_FOO_BAR`). Validate that generated variable names match `^[A-Z_][A-Z0-9_]*$`. Reject keys that would produce invalid or dangerous variable names
- **Reject control characters**: TOML values containing control characters (except `\n`, `\t`) should be rejected
- **Add TOML key injection test**: Add test in `tests/test_generate_config_cache.py` that attempts injection via TOML keys with special characters

```python
def _validate_env_key(key: str) -> bool:
    """Ensure generated env var name is safe for bash."""
    import re
    return bool(re.match(r'^[A-Z_][A-Z0-9_]*$', key))

def flatten(data: dict, prefix: str = "TOOLKIT") -> list[tuple[str, str]]:
    # ... existing code ...
    full_key = f"{prefix}_{norm_key}"
    if not _validate_env_key(full_key):
        raise ValueError(f"Unsafe variable name generated: '{full_key}' from key '{key}'")
    # ... rest ...
```

### 2.2 Atomic file writes + file locking

**Files to modify**: `hooks/_config.sh`, `lib/manifest.sh`, `hooks/session-end-cleanup.sh`, `hooks/pre-compact.sh`

- All writes to shared files (manifest.json, config cache, session state) must use atomic write pattern: write to temp file, then `mv`
- Add advisory locking for manifest updates using `flock` where available

```bash
# lib/hook-utils.sh (new, created in M3)
_atomic_write() {
  local target="$1"
  local content="$2"
  local tmp="${target}.tmp.$$"
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}
```

For manifest.sh, the pattern is already used in some places (line 466-467 of toolkit.sh) but not consistently. Standardize it.

### 2.3 Protect guard configuration from AI manipulation

**Files to modify**: `hooks/guard-sensitive-write.sh`

Add protection for toolkit configuration files themselves:

```bash
# Block writes to settings.json and toolkit.toml from AI
# (these should only be modified via toolkit.sh generate-settings)
case "$FILE_PATH" in
  */.claude/settings.json | */.claude/toolkit.toml | */.claude/toolkit-cache.env)
    deny "Direct modification of toolkit config blocked — use 'toolkit.sh generate-settings'"
    ;;
esac
```

### 2.4 Secure temp file handling

**Files to modify**: All hooks that create temp files (`pre-compact.sh`, `subagent-context-inject.sh`, others)

- Replace hardcoded `/tmp/toolkit_*` paths with `mktemp`
- Add cleanup traps: `trap 'rm -f "$tmpfile"' EXIT`
- Verify `mktemp` succeeded before using the file

### 2.5 Add audit logging for guard decisions

**Files to create**: Guard logging in `hooks/guard-destructive.sh`, `hooks/guard-sensitive-write.sh`

```bash
# Append to audit log (append-only, not affected by guards)
_audit_log() {
  local decision="$1"  # "DENY" or "ALLOW"
  local reason="$2"
  local log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude"
  local log_file="${log_dir}/guard-audit.log"
  # Only log if directory exists (don't create .claude/ just for logging)
  if [ -d "$log_dir" ]; then
    printf '%s %s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$decision" "$(basename "$0")" "$reason" >> "$log_file" 2>/dev/null || true
  fi
}
```

### 2.6 Harden file permissions

**Files to modify**: `generate-config-cache.py`, `toolkit.sh`

- Set `umask 077` before writing sensitive files (toolkit-cache.env, settings.json)
- In Python: use `os.open()` with explicit permissions for config cache output, or `os.chmod()` after write

### 2.7 Add TOML structure validation

**Files to modify**: `generate-config-cache.py`

Currently `validate_schema()` checks for unknown keys but is lenient on type mismatches (line 107-108). Tighten:

- Validate that `str` fields are actually strings
- Validate that `list` fields are actually lists
- Validate that `int` fields are actually ints
- Return errors for type mismatches instead of silently accepting

### Exit Criteria

- [ ] Config cache generation rejects unsafe variable names
- [ ] Control characters in TOML values are rejected
- [ ] All shared file writes use atomic write pattern
- [ ] Guard hooks log decisions to `guard-audit.log`
- [ ] Settings/config files protected from direct AI writes
- [ ] Temp files use `mktemp` with cleanup traps
- [ ] Generated files have 0600 permissions
- [ ] TOML type validation catches mismatches
- [ ] New tests added for injection attempts
- [ ] All existing tests pass
- [ ] `shellcheck -x -S warning hooks/*.sh` passes

---

## M3: Shared Hook Infrastructure

**Goal**: Extract duplicated code into shared utilities, standardize error messages and output format, enforce bash compatibility.

**Addresses**: H3, H6, H7, M11, L1, L6

**PR scope**: ~200 lines new (lib/hook-utils.sh), ~300 lines modified across hooks

### 3.1 Create `lib/hook-utils.sh`

**Files to create**: `lib/hook-utils.sh` (~100 lines)

Extract common patterns from hooks into shared functions:

```bash
#!/usr/bin/env bash
# Shared hook utilities — sourced by hooks that need common helpers.
# Unlike _config.sh (which every hook sources), this is opt-in.

# --- JSON input parsing ---
# Reads stdin into a variable and extracts fields via jq (or fallback)
hook_read_input() {
  HOOK_INPUT=$(cat)
  if command -v jq >/dev/null 2>&1; then
    HOOK_TOOL=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    HOOK_COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  else
    # Require jq — fallback regex parsing is fragile and untested
    HOOK_TOOL=""
    HOOK_COMMAND=""
    HOOK_FILE_PATH=""
    return 0
  fi
}

# --- Structured deny response ---
hook_deny() {
  local reason="$1"
  local context="${2:-}"
  _audit_log "DENY" "$reason"
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$context" ]; then
      jq -n --arg r "$reason" --arg c "$context" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r,additionalContext:$c}}'
    else
      jq -n --arg r "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    fi
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  exit 0
}

# --- Structured approve response ---
hook_approve() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
  exit 0
}

hook_approve_and_persist() {
  local tool_name="$1"
  jq -n --arg tool "$tool_name" \
    '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:{behavior:"allow",updatedPermissions:[{type:"toolAlwaysAllow",tool:$tool}]}}}'
  exit 0
}

# --- Audit logging ---
_audit_log() {
  local decision="$1"
  local reason="$2"
  local log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude"
  if [ -d "$log_dir" ]; then
    printf '%s %s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$decision" "$(basename "$0" .sh)" "$reason" >> "${log_dir}/guard-audit.log" 2>/dev/null || true
  fi
}

# --- Atomic file write ---
_atomic_write() {
  local target="$1"
  local content
  content=$(cat)  # read from stdin
  local tmp="${target}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$target"
}

# --- Logging helpers ---
hook_warn() { echo "[toolkit:$(basename "$0" .sh)] WARN: $*" >&2; }
hook_error() { echo "[toolkit:$(basename "$0" .sh)] ERROR: $*" >&2; }
hook_info() { echo "[toolkit:$(basename "$0" .sh)] $*" >&2; }
```

### 3.2 Migrate hooks to use shared utilities

**Files to modify**: `hooks/guard-destructive.sh`, `hooks/guard-sensitive-write.sh`, `hooks/auto-approve-safe.sh`

Replace duplicated `INPUT=$(cat)` + jq parsing + `deny()` helper with calls to `hook_read_input` and `hook_deny`. Keep the hooks focused on their matching logic only.

**Migration pattern** (for each hook):
1. Add `source "$(dirname "$0")/../lib/hook-utils.sh"` after `_config.sh`
2. Replace `INPUT=$(cat) ... jq parsing` with `hook_read_input`
3. Replace local `deny()` with `hook_deny`
4. Replace local `approve()` with `hook_approve`
5. Use `$HOOK_TOOL`, `$HOOK_COMMAND`, `$HOOK_FILE_PATH` instead of local vars

### 3.3 Standardize shebang lines

**Files to modify**: All `.sh` files

Standardize to:
- `#!/usr/bin/env bash` for scripts that are executed directly
- `#!/usr/bin/env bash` for hooks (they're executed by Claude Code)
- No shebang for `lib/*.sh` files (they're sourced, not executed) — actually keep it for safety

Pick `#!/usr/bin/env bash` consistently everywhere.

### 3.4 Add bash version compatibility check

**Files to modify**: `hooks/_config.sh`

Add a one-time check at config load time:

```bash
# Warn if bash version is too old for some features
# Most hooks work with bash 3.2, but document minimum
if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
  echo "Warning: claude-toolkit requires bash 3.2+, found ${BASH_VERSION}" >&2
fi
```

Also add a CI/linting check (documented in CLAUDE.md) to flag bash 4+ features:
- No associative arrays (`declare -A`)
- No `mapfile`/`readarray`
- No `${var,,}` lowercasing
- No `|&` (pipe stderr)

### 3.5 Add `.editorconfig`

**Files to create**: `.editorconfig`

```ini
root = true

[*]
end_of_line = lf
insert_final_newline = true
charset = utf-8
trim_trailing_whitespace = true

[*.sh]
indent_style = space
indent_size = 2

[*.py]
indent_style = space
indent_size = 4

[*.json]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[Makefile]
indent_style = tab
```

### 3.6 Standardize error messages

**Files to modify**: All hooks

Establish pattern:
- Errors: `hook_error "message"` → `[toolkit:hook-name] ERROR: message` on stderr
- Warnings: `hook_warn "message"` → `[toolkit:hook-name] WARN: message` on stderr
- Info: `hook_info "message"` → `[toolkit:hook-name] message` on stderr
- Never print to stdout (stdout is for structured JSON responses to Claude Code)

### Exit Criteria

- [ ] `lib/hook-utils.sh` exists with shared functions
- [ ] At least 3 hooks migrated to use shared utilities
- [ ] All `.sh` files use `#!/usr/bin/env bash`
- [ ] `.editorconfig` exists
- [ ] Error messages follow `[toolkit:hook-name]` pattern
- [ ] Bash 3.2 compatibility check added
- [ ] `shellcheck -x -S warning hooks/*.sh lib/*.sh` passes
- [ ] All hook tests pass
- [ ] All Python tests pass

---

## M4: CLI Modularization

**Goal**: Break toolkit.sh into modular subcommand files for independent testability and maintainability.

**Addresses**: H1

**PR scope**: ~200 lines moved (not new), ~50 lines new (dispatcher)

### 4.1 Extract subcommands to `lib/cmd-*.sh`

**Files to create**:
- `lib/cmd-init.sh` (~280 lines, extracted from toolkit.sh lines 109-388)
- `lib/cmd-update.sh` (~110 lines, extracted from toolkit.sh lines 394-503)
- `lib/cmd-customize.sh` (~42 lines, extracted from toolkit.sh lines 568-609)
- `lib/cmd-status.sh` (~135 lines, extracted from toolkit.sh lines 615-750)
- `lib/cmd-validate.sh` (~130 lines, extracted from toolkit.sh lines 756-885)
- `lib/cmd-generate-settings.sh` (~80 lines, extracted from toolkit.sh lines 891-969)

**Files to modify**:
- `toolkit.sh` — becomes a thin dispatcher (~100 lines): path resolution, helper functions, source commands, dispatch

### 4.2 Extract `cmd_init` internal helpers

The `cmd_init` function is 280 lines doing 8 distinct operations. Split into:

```bash
# In lib/cmd-init.sh
_init_toml()          # Handle toolkit.toml (lines 131-147)
_init_agents()        # Symlink agents (lines 149-175)
_init_skills()        # Copy skills (lines 177-202)
_init_rules()         # Symlink rules (lines 204-228)
_init_rule_templates() # Copy rule templates (lines 230-291)
_init_agent_memory()  # Create memory dirs (lines 293-312)
_init_git_remote()    # Set up git remote (lines 314-340)
_init_config()        # Generate settings (lines 342-347)
_init_manifest()      # Create manifest (lines 349-377)

cmd_init() {
  # Parse args, validate prereqs, then call each helper
  _init_toml "$@"
  _init_agents "$@"
  _init_skills "$@"
  # ... etc
}
```

### 4.3 Add `_refresh_symlinks` to shared location

Move `_refresh_symlinks()` (currently in toolkit.sh lines 505-562) into `lib/cmd-update.sh` since it's only used by the update flow.

### Exit Criteria

- [ ] `toolkit.sh` is under 150 lines (dispatcher + helpers)
- [ ] Each `lib/cmd-*.sh` contains one subcommand
- [ ] `cmd_init` uses helper functions for each distinct operation
- [ ] All CLI integration tests pass: `bash tests/test_toolkit_cli.sh`
- [ ] All manifest tests pass: `bash tests/test_manifest.sh`
- [ ] `shellcheck -x -S warning toolkit.sh lib/*.sh` passes
- [ ] CLI behavior is identical before/after (no user-visible changes)

---

## M5: Validation, Diagnostics & Resilience

**Goal**: Add schema validation, manifest recovery, dry-run mode, health checks, and update safety.

**Addresses**: H4, H5, M4, M5, M9, M12, L5

**PR scope**: ~400 lines new, ~100 lines modified

### 5.1 Add JSON schema validation for settings merge

**Files to modify**: `generate-settings.py`

Add a validation function that checks the merged output:

```python
SETTINGS_SCHEMA = {
    "required_top_level": ["hooks", "permissions"],
    "known_top_level": ["hooks", "permissions", "env", "preferences"],
    "hooks_required_fields": ["event", "hooks"],
    "hook_entry_fields": ["command"],
}

def validate_settings_schema(merged: dict) -> list[str]:
    """Validate merged settings match expected Claude Code schema."""
    warnings = []
    # Check for unknown top-level keys
    known = {"hooks", "permissions", "env", "preferences", "mcpServers"}
    for key in merged:
        if key not in known:
            warnings.append(f"Unknown top-level key: '{key}' (typo?)")
    # Validate hook entries have required fields
    # ... etc
    return warnings
```

Print warnings (not errors) for unrecognized keys, so typos are caught but don't block generation.

### 5.2 Add manifest corruption recovery

**Files to modify**: `lib/manifest.sh`

```bash
_validate_manifest() {
  local manifest_path="$1"
  if [[ ! -f "$manifest_path" ]]; then
    return 1
  fi
  if ! jq empty "$manifest_path" 2>/dev/null; then
    echo "Warning: Manifest is corrupted. Regenerating..." >&2
    # Backup the corrupted file
    cp "$manifest_path" "${manifest_path}.corrupted.$(date +%s)"
    return 1
  fi
  return 0
}
```

Call `_validate_manifest` at the start of every manifest operation. If corrupted, regenerate via `manifest_init`.

### 5.3 Add dry-run mode to CLI

**Files to modify**: `toolkit.sh` (dispatcher), `lib/cmd-init.sh`, `lib/cmd-generate-settings.sh`

Add `--dry-run` flag to `init` and `generate-settings` commands:

```bash
# In dispatcher
DRY_RUN=false
case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
esac
export DRY_RUN

# In helpers, check before mutating:
if [[ "$DRY_RUN" == true ]]; then
  _info "[dry-run] Would create symlink: agents/${agent_name}"
else
  ln -sf "$relative_path" "$target"
fi
```

### 5.4 Add `toolkit.sh doctor` command

**Files to create**: `lib/cmd-doctor.sh` (~100 lines)

A comprehensive health check that goes beyond `validate`:

```bash
cmd_doctor() {
  echo "Running toolkit health check..."

  # 1. Check all required tools exist (bash, jq, python3, git)
  # 2. Check bash version
  # 3. Check Python version
  # 4. Check jq version
  # 5. Verify hooks can parse sample JSON (run each hook with test input)
  # 6. Check symlink targets exist
  # 7. Verify config cache is not stale
  # 8. Verify settings.json matches what generate-settings would produce
  # 9. Check for known compatibility issues
  # 10. Print summary with actionable advice
}
```

### 5.5 Add update integrity verification

**Files to modify**: `lib/cmd-update.sh`

After `git subtree pull`, add:

```bash
# Verify pulled scripts pass shellcheck
echo "Verifying toolkit integrity..."
if command -v shellcheck &>/dev/null; then
  if ! shellcheck -x -S warning "${TOOLKIT_DIR}"/hooks/*.sh "${TOOLKIT_DIR}"/lib/*.sh "${TOOLKIT_DIR}"/toolkit.sh 2>/dev/null; then
    _warn "Updated toolkit has shellcheck warnings. Review before using."
  fi
fi

# Show what changed
echo ""
echo "Changes in this update:"
git -C "$PROJECT_DIR" diff --stat HEAD~1 -- .claude/toolkit/ 2>/dev/null || true
```

### 5.6 Fix settings merge array deduplication

**Files to modify**: `generate-settings.py`

The current array dedup (lines 238-247) correctly deduplicates. Verify edge cases:
- Mixed type arrays (string + int) — currently handled via `repr()` key
- Empty arrays — verify concat with empty produces correct result
- Add test cases for these edge cases in `test_generate_settings.py`

### Exit Criteria

- [ ] Settings merge warns on unknown keys
- [ ] Manifest operations recover from corruption
- [ ] `toolkit.sh init --dry-run` shows what would change without mutating
- [ ] `toolkit.sh doctor` exists and checks tool versions, hook health, config freshness
- [ ] Update shows diff and runs shellcheck on pulled code
- [ ] New edge case tests for array merge
- [ ] All tests pass

---

## M6: Developer Experience & Onboarding

**Goal**: Reduce onboarding friction, improve documentation, lower cognitive load. Incorporates the [streamline-bootstrap-setup plan](streamline-bootstrap-setup.md).

**Addresses**: H2, H10, M10, L8

**Dependency**: Executes `streamline-bootstrap-setup.md` milestones M0-M3

**PR scope**: Covered by the referenced plan, plus additions below

### 6.1 Execute streamline-bootstrap-setup plan

Follow the milestones defined in `docs/plans/streamline-bootstrap-setup.md`:

- **M0**: Create `detect-project.py` for auto-detection
- **M1**: Simplify `bootstrap.sh` to git-only operations
- **M2**: Rewrite `/setup-toolkit` skill as comprehensive orchestrator
- **M3**: Update CLAUDE.md template + docs

### 6.2 Split README into quick-start + reference

**Files to modify**: `README.md`
**Files to create**: `docs/reference.md`, `docs/concepts.md`

- `README.md`: Trim to <200 lines — installation, quick-start (5-minute guide), link to detailed docs
- `docs/reference.md`: Full configuration reference, all options, all hooks, all stacks
- `docs/concepts.md`: Mental model explainer — what are hooks, agents, skills, rules, manifest, stacks (2-minute read)

### 6.3 Add CONTRIBUTING.md

**Files to create**: `CONTRIBUTING.md`

Cover:
- How to add a new hook
- How to add a new agent
- How to add a new skill
- How to add a new stack
- Testing requirements
- Shellcheck requirements
- Generic-by-default philosophy

### 6.4 Add `toolkit.sh explain` command

**Files to create**: `lib/cmd-explain.sh`

```bash
cmd_explain() {
  local topic="${1:-overview}"
  case "$topic" in
    overview)
      echo "Claude Toolkit is a collection of hooks, agents, skills, and rules"
      echo "that integrate into your .claude/ directory for safe, autonomous AI development."
      echo ""
      echo "Components:"
      echo "  hooks/   — Scripts that run automatically (guards, linting, quality gates)"
      echo "  agents/  — Prompts for specialized AI agents (reviewer, qa, security, etc.)"
      echo "  skills/  — Templates for common workflows (review, implement, plan, etc.)"
      echo "  rules/   — Coding convention documents loaded by Claude Code"
      echo ""
      echo "Run '$0 explain <topic>' for details: hooks, agents, skills, rules, config, stacks"
      ;;
    hooks)    # ... detailed hook explanation ...
    agents)   # ... detailed agent explanation ...
    # etc
  esac
}
```

### Exit Criteria

- [ ] `detect-project.py` exists and works
- [ ] `bootstrap.sh` simplified per streamline plan
- [ ] `/setup-toolkit` skill rewritten per streamline plan
- [ ] README.md under 200 lines with quick-start focus
- [ ] `docs/reference.md` has full configuration reference
- [ ] `docs/concepts.md` explains mental model
- [ ] `CONTRIBUTING.md` exists
- [ ] `toolkit.sh explain` command works
- [ ] All tests pass

---

## M7: Polish & Long-Term Maintainability

**Goal**: Address remaining medium/low items — extension points, performance, test cleanup.

**Addresses**: M1, M2, M3, M13, L2, L3, L4, L7

**PR scope**: ~300 lines across multiple files

### 7.1 Make stack system self-describing

**Files to modify**: `templates/stacks/` directory, `generate-settings.py`

Make adding a new stack require only dropping a JSON file:
- Each stack JSON gets a `_meta` key (ignored by merge) with description and required tools
- `toolkit.sh status` auto-discovers available stacks from the directory
- Document the stack file format in `CONTRIBUTING.md`

```json
{
  "_meta": {
    "name": "python",
    "description": "Python stack: ruff linting, pytest testing",
    "required_tools": ["ruff", "pytest"]
  },
  "hooks": { ... }
}
```

### 7.2 Custom hook directory support

**Files to modify**: `templates/settings-base.json`, `hooks/_config.sh`

Allow projects to add custom hooks in `.claude/hooks-custom/`:
- `_config.sh` checks for and sources custom hooks directory
- Settings merge includes custom hooks alongside toolkit hooks
- Document in `CONTRIBUTING.md`

### 7.3 Config caching optimization

**Files to modify**: `hooks/_config.sh`

Currently every hook invocation re-sources `_config.sh` which reads the cache file. For performance:

- Cache parsed config in environment variables (already the pattern)
- Add mtime check: skip re-sourcing if env var `_TOOLKIT_CONFIG_LOADED` is already set and mtime hasn't changed
- This is a minor optimization — only pursue if hook latency becomes noticeable

### 7.4 Add version metadata to agent prompts

**Files to modify**: All agent `.md` files

Add YAML frontmatter with version:

```yaml
---
version: "1.3.0"
toolkit_min_version: "1.3.0"
---
```

This allows `toolkit.sh status` to show which agent versions are deployed and whether they match the toolkit version.

### 7.5 Consolidate test fixtures

**Files to modify**: `tests/fixtures/`

Review and consolidate overlapping fixtures. Remove duplicated test data.

### 7.6 Decouple smart-context

**Files to modify**: `hooks/smart-context.py`, `smart-context/framework.py`

Make smart-context a standalone module that can be used or replaced independently:
- Remove direct `_config.sh` dependencies from the Python module
- Accept configuration via CLI arguments instead of environment variables
- Add `--help` and `--version` flags

### Exit Criteria

- [ ] New stacks can be added by dropping a JSON file in `templates/stacks/`
- [ ] Custom hooks directory `.claude/hooks-custom/` supported
- [ ] Agent prompts have version metadata
- [ ] Test fixtures consolidated
- [ ] smart-context has clean module boundary
- [ ] All tests pass
- [ ] `CHANGELOG.md` updated for all changes

---

## Cross-Cutting Requirements

These apply to every milestone:

1. **All `.sh` files pass** `shellcheck -x -S warning`
2. **All Python tests pass**: `python3 -m pytest tests/ -v`
3. **All bash tests pass**: `tests/test_hooks.sh`, `tests/test_toolkit_cli.sh`, `tests/test_manifest.sh`
4. **Agents and skills remain GENERIC** — no project-specific content
5. **`CHANGELOG.md` updated** for each milestone
6. **Backward compatible** — existing toolkit.toml files continue to work

## Milestone Dependency Graph

```text
M1 (Hook Security + Tests)
  ↓
M2 (Security Hardening)
  ↓
M3 (Shared Infrastructure)  ←─── depends on M1 test framework
  ↓
M4 (CLI Modularization)     ←─── independent, can parallel with M3
  ↓
M5 (Validation & Diagnostics)
  ↓
M6 (DX & Onboarding)        ←─── incorporates streamline-bootstrap-setup plan
  ↓
M7 (Polish)
```

M1 → M2 → M3 are sequential (each builds on the previous).
M4 can start in parallel after M1.
M5 can start after M3 or M4 (whichever finishes last).
M6 depends on M5 (needs doctor/dry-run for the setup flow).
M7 is the final polish pass.

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Migrating hooks to shared utils breaks behavior | Hook test framework (M1) catches regressions before M3 migration |
| Modularizing toolkit.sh introduces bugs | CLI integration tests already exist; run before/after |
| Security hardening is too aggressive | Each guard change is tested with hook tests; dry-run mode provides safety net |
| Config cache hardening rejects valid configs | Schema validation runs in warning mode first; only errors block |
| Bootstrap simplification breaks existing users | Old flags kept as optional backward-compatible args |

## Evaluation Criteria

The plan is complete when:

1. **Zero critical findings remain**: C1-C4 all resolved
2. **Hook test coverage**: 30+ test cases covering all guard hooks
3. **CLI modular**: toolkit.sh under 150 lines, each command in its own file
4. **Onboarding**: New project setup takes under 5 minutes with `/setup-toolkit`
5. **All tests pass**: Python (126+), bash hooks (30+), CLI integration, manifest
6. **Shellcheck clean**: All `.sh` files pass with no warnings

---

## Feedback Log

_No feedback yet._
