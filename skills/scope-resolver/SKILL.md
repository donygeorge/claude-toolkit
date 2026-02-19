---
name: scope-resolver
description: Internal skill that resolves scope for review agents.
user-invocable: false
---

# Scope Resolver Skill

Resolves user intent (feature name, diff range, or "uncommitted") into a Scope Bundle for review agents.

## Critical Rules

| Rule | Description |
| ---- | ----------- |
| **1. Return valid Scope Bundle JSON** | Output must always be a complete JSON object matching the Scope Bundle schema; never return partial or prose output. |
| **2. Never modify files** | This skill is read-only; it resolves scope but must not create, edit, or delete any files. |
| **3. Fail fast on ambiguous scope** | If the scope key cannot be resolved to files, return an error immediately instead of guessing. |

## Aliases

- `scope-resolver`

## Input

Natural language or structured scope specification:

- `feature:my-feature` - Named feature from features.json
- `uncommitted` - Uncommitted changes (staged + unstaged)
- `diff:HEAD~1` - Single commit diff
- `diffs:main..HEAD` - Range of commits

## Output: Scope Bundle

Returns a JSON Scope Bundle with:

```json
{
  "scope_key": "feature:my-feature",
  "scope_slug": "feature-my-feature",
  "scope_type": "feature",
  "commit_hash": "abc1234",
  "files": ["list of files"],
  "diff": "unified diff (truncated for context)",
  "language_breakdown": {"python": 3, "swift": 5},
  "risk_profile": {
    "auth": false,
    "storage": true,
    "network": true,
    "crypto": false,
    "pii": false
  },
  "tests_touched": ["tests/test_*.py"],
  "likely_tests_missing": ["heuristic suggestions"],
  "entrypoints": {
    "routes": ["/api/data"],
    "screens": ["HomeView"]
  }
}
```

## Resolution Logic

### 1. Parse Scope Key

```text
Input: "my feature" or "my-feature" or "feature:my-feature"
Output: scope_key = "feature:my-feature", scope_slug = "feature-my-feature"

Input: "my changes" or "uncommitted" or nothing
Output: scope_key = "uncommitted", scope_slug = "uncommitted"

Input: "last commit" or "HEAD~1"
Output: scope_key = "diff:HEAD~1", scope_slug = "diff-HEAD-1"

Input: "this branch" or "main..HEAD"
Output: scope_key = "diffs:main..HEAD", scope_slug = "diffs-main-HEAD"
```

### 2. Resolve Files

For features: Read features.json, expand globs
For uncommitted: `git status --porcelain`
For diffs: `git diff --name-only <range>`

### 3. Generate Diff

```bash
# Uncommitted
git diff HEAD

# Specific commit
git diff HEAD~1

# Range
git diff main..HEAD
```

### 4. Detect Risk Profile

Scan files for patterns:

- `auth`: Files in auth/, login, token, session
- `storage`: Database access, file I/O
- `network`: HTTP clients, API calls
- `crypto`: Encryption, hashing
- `pii`: User data, personal info

### 5. Find Tests

- Map source files to test files by naming convention
- Flag new functions without corresponding tests

### 6. Get Entrypoints

From features.json for feature scopes, or infer from file paths.

## Project Configuration

Projects should create a `features.json` file to define their feature registry.
This file maps feature names to file globs and entrypoints.

<!-- Example features.json structure: -->
<!-- { -->
<!--   "features": { -->
<!--     "auth": { -->
<!--       "files": ["src/auth/**", "tests/test_auth*"], -->
<!--       "entrypoints": { "routes": ["/api/auth/*"], "screens": ["LoginView"] } -->
<!--     } -->
<!--   } -->
<!-- } -->

## Internal Usage

Called internally by review-suite orchestrator. Not typically invoked directly.

```bash
# Internal call pattern
scope_bundle = scope_resolver.resolve("feature:my-feature")
```
