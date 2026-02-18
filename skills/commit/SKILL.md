---
name: commit
description: Use when the current session has changes ready to commit.
user-invocable: true
model: haiku
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Commit Skill

Create a local commit containing only files touched in this session that are currently uncommitted. Does nothing if there are no uncommitted changes from the session.

## Critical Rules

| Rule | Description |
| ---- | ----------- |
| **1. Session files only** | Never commit files you did not touch in this session; cross-reference conversation history with `git status`. |
| **2. Never `git add .`** | Always stage specific files by name; bulk staging risks committing unrelated changes. |
| **3. Use `-F` for messages** | Write the commit message to a temp file and use `git commit -F` to avoid shell escaping and guard hook issues. |
| **4. No push, no amend, no force** | Only create new local commits; never push, amend, or use `--force`/`--no-verify`. |

---

## Workflow

### Step 1: Identify Uncommitted Changes

Run git status to find all uncommitted changes (staged, unstaged, and untracked files):

```bash
git status --porcelain
```

If the output is empty, stop immediately and tell the user there is nothing to commit.

### Step 2: Filter to Session Files

From the uncommitted changes, identify which files were touched in this Claude Code session.

**Detection strategy**: Rely on your conversation history to identify files you created or modified during this session. Cross-reference with `git status` output to confirm they are actually uncommitted. Specifically:

1. Review your conversation history for all Write, Edit, and Bash commands that created or modified files.
2. Build a list of files you touched in this session.
3. Intersect that list with the `git status --porcelain` output to find files that are both session-touched AND uncommitted.

Only include files that you (the AI assistant) created or modified during this session. Do NOT include:

- Files that were already modified before the session started
- Files you did not touch

If no session files have uncommitted changes, stop and tell the user there is nothing to commit.

### Step 3: Review the Changes

Read the diff for the files to be committed:

```bash
git diff <files>
git diff --cached <files>
```

For untracked files, read their contents to understand what was added.

### Step 4: Stage Files

Stage only the session files:

```bash
git add <file1> <file2> ...
```

NEVER use `git add .` or `git add -A`. Only stage specific files you touched in this session.

### Step 5: Generate Commit Message

Based on the diff, write a concise commit message that:

- Summarizes the nature of the changes (e.g., "Add feature X", "Fix bug in Y", "Refactor Z")
- Focuses on the "why" not the "what"
- Is 1-2 sentences max

Write the message to a temporary file, then commit:

```bash
git commit -F /tmp/commit-msg.txt
```

Include the Co-Authored-By trailer:

```text
Co-Authored-By: Claude <noreply@anthropic.com>
```

### Step 6: Confirm

Show the user the commit hash and a brief summary:

```text
Committed <hash>: <message>
Files: <list of committed files>
```

## Rules

- **Session files only** -- never commit files you did not touch in this session
- **No `git add .`** -- always stage specific files by name
- **No amend** -- always create a new commit
- **No push** -- only commit locally, never push
- **No force** -- never use `--force` or `--no-verify`
- **Use `-F` for commit messages** -- write message to a file first to avoid shell escaping issues
- **Do nothing if clean** -- if there are no uncommitted session files, say so and stop
